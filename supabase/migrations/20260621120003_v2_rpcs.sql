-- =====================================================================
-- 0012 (v2) — RPCs do fluxo público, versão 2 (§5.3 / §6.2 / §6.4)
-- Reescreve get_available_slots e create_booking para respeitar:
--   • buffer_min (fim_at do appointment = BLOCO ocupado = duracao + buffer);
--   • time_blocks (folgas/feriados subtraídos da disponibilidade);
--   • vínculo serviço↔profissional (professional_services);
--   • booking_policy do tenant (antecedência mín/máx).
-- Adiciona:
--   • get_booking_by_token / manage_booking — auto-gerenciamento por token;
--   • join_waitlist — lista de espera para slots cheios.
-- Tudo SECURITY DEFINER, tenant derivado por slug, zero PII de terceiros.
-- =====================================================================

-- ---------------------------------------------------------------------
-- get_available_slots v2 — apenas slots livres, respeitando buffer,
-- time_blocks e o vínculo serviço↔profissional.
-- Retorno: inicio_at + fim_at VISÍVEL (= inicio + duracao_min).
-- ---------------------------------------------------------------------
create or replace function get_available_slots(
  p_tenant_slug   text,
  p_service_id    uuid,
  p_data          date,
  p_professional_id uuid default null
)
returns table (inicio_at timestamptz, fim_at timestamptz, professional_id uuid)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_tenant    tenants%rowtype;
  v_duracao   integer;
  v_buffer    integer;
  v_block     interval;   -- duracao + buffer (passo e ocupação)
  v_visible   interval;   -- duracao (fim mostrado ao cliente)
  v_has_links boolean;
begin
  select * into v_tenant from tenants where slug = p_tenant_slug and status = 'ativo';
  if not found then
    return;
  end if;

  select duracao_min, buffer_min into v_duracao, v_buffer
  from services
  where id = p_service_id and tenant_id = v_tenant.id and ativo = true and deleted_at is null;
  if v_duracao is null then
    return;
  end if;
  v_block   := make_interval(mins => v_duracao + coalesce(v_buffer, 0));
  v_visible := make_interval(mins => v_duracao);

  -- Há vínculo definido para este serviço? Se não houver nenhum, todos os
  -- profissionais ativos o realizam (retrocompatível).
  select exists (
    select 1 from professional_services
    where service_id = p_service_id and tenant_id = v_tenant.id
  ) into v_has_links;

  return query
  with profs as (
    select pr.id
    from professionals pr
    where pr.tenant_id = v_tenant.id
      and pr.ativo = true
      and pr.deleted_at is null
      and (p_professional_id is null or pr.id = p_professional_id)
      and (
        not v_has_links
        or exists (
          select 1 from professional_services ps
          where ps.professional_id = pr.id and ps.service_id = p_service_id
        )
      )
  ),
  windows as (
    select
      wh.professional_id,
      ((p_data::text || ' ' || wh.hora_inicio::text)::timestamp at time zone v_tenant.timezone) as win_start,
      ((p_data::text || ' ' || wh.hora_fim::text)::timestamp    at time zone v_tenant.timezone) as win_end
    from working_hours wh
    join profs on profs.id = wh.professional_id
    where wh.weekday = extract(dow from p_data)::int
  ),
  candidates as (
    select
      w.professional_id,
      gs as cand_inicio,
      gs + v_visible as cand_visible_fim,
      gs + v_block   as cand_block_fim
    from windows w
    cross join lateral generate_series(w.win_start, w.win_end - v_visible, v_block) as gs
    where gs + v_visible <= w.win_end
      and gs > now()
  )
  select c.cand_inicio, c.cand_visible_fim, c.professional_id
  from candidates c
  where not exists (
    -- sem sobreposição com agendamentos ativos (já incluem o buffer no fim_at)
    select 1 from appointments a
    where a.professional_id = c.professional_id
      and a.status <> 'cancelado'
      and a.deleted_at is null
      and tstzrange(a.inicio_at, a.fim_at) && tstzrange(c.cand_inicio, c.cand_block_fim)
  )
  and not exists (
    -- sem sobreposição com folgas/bloqueios
    select 1 from time_blocks tb
    where tb.professional_id = c.professional_id
      and tstzrange(tb.inicio_at, tb.fim_at) && tstzrange(c.cand_inicio, c.cand_block_fim)
  )
  order by c.cand_inicio, c.professional_id;
end;
$$;

revoke all on function get_available_slots(text, uuid, date, uuid) from public;
grant execute on function get_available_slots(text, uuid, date, uuid) to anon, authenticated;

-- ---------------------------------------------------------------------
-- create_booking v2 — agora retorna jsonb (appointment_id + manage_token +
-- status + deposito_status) para a tela de confirmação e o link de gestão.
-- Mantém rate limit, consentimento LGPD e validações da v1, e adiciona
-- buffer, time_blocks, vínculo serviço↔profissional e booking_policy.
-- ---------------------------------------------------------------------
drop function if exists create_booking(text, uuid, uuid, timestamptz, text, text, text, boolean, text);
create or replace function create_booking(
  p_tenant_slug     text,
  p_service_id      uuid,
  p_professional_id uuid,
  p_inicio          timestamptz,
  p_nome            text,
  p_telefone        text,
  p_email           text,
  p_consentimento   boolean,
  p_ip              text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tenant      tenants%rowtype;
  v_svc         services%rowtype;
  v_block       interval;
  v_fim         timestamptz;   -- fim do BLOCO (inclui buffer)
  v_visible_fim timestamptz;   -- fim visível do atendimento
  v_prof        uuid;
  v_customer_id uuid;
  v_appt_id     uuid;
  v_token       uuid;
  v_recent_tel  integer;
  v_recent_ip   integer;
  v_weekday     int;
  v_local_time  time;
  v_has_links   boolean;
  v_min_horas   numeric;
  v_max_dias    numeric;
  v_dep_status  text;
begin
  select * into v_tenant from tenants where slug = p_tenant_slug and status = 'ativo';
  if not found then
    raise exception 'tenant_not_found' using errcode = 'P0001';
  end if;

  -- ---- Rate limiting (§5.3): janela de 10 min ----
  select count(*) into v_recent_tel from booking_attempts
    where tenant_id = v_tenant.id and telefone = p_telefone
      and created_at > now() - interval '10 minutes';
  select count(*) into v_recent_ip from booking_attempts
    where tenant_id = v_tenant.id and ip = p_ip
      and created_at > now() - interval '10 minutes';
  if v_recent_tel >= 5 or (p_ip is not null and v_recent_ip >= 20) then
    insert into booking_attempts (tenant_id, ip, telefone, sucesso)
      values (v_tenant.id, p_ip, p_telefone, false);
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;
  insert into booking_attempts (tenant_id, ip, telefone, sucesso)
    values (v_tenant.id, p_ip, p_telefone, false);

  -- ---- LGPD: consentimento explícito ----
  if p_consentimento is not true then
    raise exception 'consent_required' using errcode = 'P0001';
  end if;

  -- ---- Validações de input ----
  if p_telefone !~ '^\+?[0-9]{10,15}$' then
    raise exception 'invalid_phone' using errcode = 'P0001';
  end if;
  if p_email is not null and p_email <> '' and p_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'invalid_email' using errcode = 'P0001';
  end if;
  if p_inicio <= now() then
    raise exception 'past_slot' using errcode = 'P0001';
  end if;

  -- ---- Política de agendamento (antecedência mín/máx) ----
  v_min_horas := coalesce((v_tenant.booking_policy ->> 'antecedencia_min_horas')::numeric, 0);
  v_max_dias  := coalesce((v_tenant.booking_policy ->> 'antecedencia_max_dias')::numeric, 365);
  if p_inicio < now() + make_interval(mins => (v_min_horas * 60)::int) then
    raise exception 'too_soon' using errcode = 'P0001';
  end if;
  if p_inicio > now() + make_interval(days => v_max_dias::int) then
    raise exception 'too_far' using errcode = 'P0001';
  end if;

  -- ---- Serviço válido/ativo ----
  select * into v_svc from services
  where id = p_service_id and tenant_id = v_tenant.id and ativo = true and deleted_at is null;
  if v_svc.id is null then
    raise exception 'service_unavailable' using errcode = 'P0001';
  end if;
  v_block       := make_interval(mins => v_svc.duracao_min + coalesce(v_svc.buffer_min, 0));
  v_fim         := p_inicio + v_block;
  v_visible_fim := p_inicio + make_interval(mins => v_svc.duracao_min);

  -- ---- Vínculo serviço↔profissional ----
  select exists (
    select 1 from professional_services
    where service_id = p_service_id and tenant_id = v_tenant.id
  ) into v_has_links;

  -- ---- Profissional: explícito ou "qualquer disponível" ----
  if p_professional_id is not null then
    select id into v_prof from professionals
    where id = p_professional_id and tenant_id = v_tenant.id and ativo = true and deleted_at is null;
    if v_prof is null then
      raise exception 'professional_unavailable' using errcode = 'P0001';
    end if;
    if v_has_links and not exists (
      select 1 from professional_services
      where professional_id = v_prof and service_id = p_service_id
    ) then
      raise exception 'professional_unavailable' using errcode = 'P0001';
    end if;
  else
    select pr.id into v_prof
    from professionals pr
    where pr.tenant_id = v_tenant.id and pr.ativo = true and pr.deleted_at is null
      and (not v_has_links or exists (
        select 1 from professional_services ps
        where ps.professional_id = pr.id and ps.service_id = p_service_id
      ))
      and not exists (
        select 1 from appointments a
        where a.professional_id = pr.id and a.status <> 'cancelado' and a.deleted_at is null
          and tstzrange(a.inicio_at, a.fim_at) && tstzrange(p_inicio, v_fim)
      )
      and not exists (
        select 1 from time_blocks tb
        where tb.professional_id = pr.id
          and tstzrange(tb.inicio_at, tb.fim_at) && tstzrange(p_inicio, v_fim)
      )
    order by pr.created_at
    limit 1;
    if v_prof is null then
      raise exception 'slot_taken' using errcode = 'P0001';
    end if;
  end if;

  -- ---- Dentro do expediente (fim visível dentro do horário) ----
  v_weekday := extract(dow from (p_inicio at time zone v_tenant.timezone))::int;
  v_local_time := (p_inicio at time zone v_tenant.timezone)::time;
  if not exists (
    select 1 from working_hours wh
    where wh.professional_id = v_prof
      and wh.weekday = v_weekday
      and v_local_time >= wh.hora_inicio
      and (v_local_time + make_interval(mins => v_svc.duracao_min)) <= wh.hora_fim
  ) then
    raise exception 'outside_hours' using errcode = 'P0001';
  end if;

  -- ---- Não cair sobre folga/bloqueio ----
  if exists (
    select 1 from time_blocks tb
    where tb.professional_id = v_prof
      and tstzrange(tb.inicio_at, tb.fim_at) && tstzrange(p_inicio, v_fim)
  ) then
    raise exception 'slot_taken' using errcode = 'P0001';
  end if;

  -- ---- Cliente: cria ou reaproveita por telefone (minimização LGPD) ----
  select id into v_customer_id from customers
    where tenant_id = v_tenant.id and telefone = p_telefone;
  if v_customer_id is null then
    insert into customers (tenant_id, nome, telefone, email, consentimento_lgpd_at)
    values (v_tenant.id, p_nome, p_telefone, nullif(p_email, ''), now())
    returning id into v_customer_id;
  else
    update customers
      set nome = p_nome,
          email = coalesce(nullif(p_email, ''), email),
          consentimento_lgpd_at = now(),
          deleted_at = null
      where id = v_customer_id;
  end if;

  v_dep_status := case when v_svc.exige_deposito then 'pendente' else 'nao_exigido' end;

  -- ---- Cria o agendamento (EXCLUDE é a barreira final do overbooking) ----
  begin
    insert into appointments
      (tenant_id, professional_id, service_id, customer_id, inicio_at, fim_at,
       status, origem, deposito_status)
    values
      (v_tenant.id, v_prof, p_service_id, v_customer_id, p_inicio, v_fim,
       'agendado', 'publico', v_dep_status)
    returning id, manage_token into v_appt_id, v_token;
  exception when exclusion_violation then
    raise exception 'slot_taken' using errcode = 'P0001';
  end;

  update booking_attempts set sucesso = true
    where tenant_id = v_tenant.id and telefone = p_telefone
      and created_at > now() - interval '1 minute';

  return jsonb_build_object(
    'appointment_id', v_appt_id,
    'manage_token', v_token,
    'status', 'agendado',
    'deposito_status', v_dep_status,
    'inicio_at', p_inicio,
    'fim_at', v_visible_fim
  );
end;
$$;

revoke all on function create_booking(text, uuid, uuid, timestamptz, text, text, text, boolean, text) from public;
grant execute on function create_booking(text, uuid, uuid, timestamptz, text, text, text, boolean, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- get_public_establishment v2 — inclui logo, política (bits públicos),
-- categoria/buffer/depósito dos serviços, avatar/bio dos profissionais e
-- o mapa serviço→profissionais para o funil filtrar corretamente.
-- ---------------------------------------------------------------------
create or replace function get_public_establishment(p_tenant_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_tenant tenants%rowtype; v_result jsonb;
begin
  select * into v_tenant from tenants where slug = p_tenant_slug and status = 'ativo';
  if not found then
    return null;
  end if;

  select jsonb_build_object(
    'nome', v_tenant.nome,
    'slug', v_tenant.slug,
    'accent_color', v_tenant.accent_color,
    'brand_logo_url', v_tenant.brand_logo_url,
    'vertical', v_tenant.vertical,
    'timezone', v_tenant.timezone,
    'booking_policy', jsonb_build_object(
      'antecedencia_min_horas', v_tenant.booking_policy -> 'antecedencia_min_horas',
      'antecedencia_max_dias',  v_tenant.booking_policy -> 'antecedencia_max_dias',
      'cancelamento_ate_horas', v_tenant.booking_policy -> 'cancelamento_ate_horas'
    ),
    'servicos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', s.id, 'nome', s.nome, 'categoria', s.categoria,
               'duracao_min', s.duracao_min, 'buffer_min', s.buffer_min,
               'preco', s.preco, 'exige_deposito', s.exige_deposito,
               'deposito_valor', s.deposito_valor,
               'profissionais', coalesce((
                 select jsonb_agg(ps.professional_id)
                 from professional_services ps where ps.service_id = s.id
               ), '[]'::jsonb))
             order by s.nome)
      from services s
      where s.tenant_id = v_tenant.id and s.ativo = true and s.deleted_at is null
    ), '[]'::jsonb),
    'profissionais', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', pr.id, 'nome', pr.nome,
               'avatar_url', pr.avatar_url, 'bio', pr.bio)
             order by pr.nome)
      from professionals pr
      where pr.tenant_id = v_tenant.id and pr.ativo = true and pr.deleted_at is null
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function get_public_establishment(text) from public;
grant execute on function get_public_establishment(text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- get_booking_by_token — dados do PRÓPRIO agendamento para a tela de
-- gestão. Nenhum dado de terceiros; só o que o titular precisa ver.
-- ---------------------------------------------------------------------
create or replace function get_booking_by_token(p_manage_token uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_result jsonb;
begin
  select jsonb_build_object(
    'appointment_id', a.id,
    'status', a.status,
    'inicio_at', a.inicio_at,
    'fim_at', a.fim_at,
    'deposito_status', a.deposito_status,
    'service_id', a.service_id,
    'professional_id', a.professional_id,
    'estabelecimento', t.nome,
    'slug', t.slug,
    'accent_color', t.accent_color,
    'brand_logo_url', t.brand_logo_url,
    'servico', s.nome,
    'duracao_min', s.duracao_min,
    'profissional', pr.nome,
    'cliente_nome', c.nome,
    'cancelamento_ate_horas', coalesce((t.booking_policy ->> 'cancelamento_ate_horas')::numeric, 0),
    -- pode cancelar/remarcar? (ativo, futuro e dentro da janela da política)
    'pode_gerenciar', (
      a.status in ('agendado', 'confirmado')
      and a.deleted_at is null
      and a.inicio_at > now() + make_interval(mins => (coalesce((t.booking_policy ->> 'cancelamento_ate_horas')::numeric, 0) * 60)::int)
    )
  ) into v_result
  from appointments a
  join tenants t       on t.id = a.tenant_id
  join services s      on s.id = a.service_id
  join professionals pr on pr.id = a.professional_id
  join customers c     on c.id = a.customer_id
  where a.manage_token = p_manage_token;

  return v_result; -- null se token inválido
end;
$$;

revoke all on function get_booking_by_token(uuid) from public;
grant execute on function get_booking_by_token(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------
-- manage_booking — cliente cancela ou remarca pelo token, respeitando a
-- janela de cancelamento (booking_policy). Sem login, sem PII de terceiros.
-- p_acao: 'cancelar' | 'remarcar'. p_novo_inicio obrigatório em 'remarcar'.
-- ---------------------------------------------------------------------
create or replace function manage_booking(
  p_manage_token uuid,
  p_acao         text,
  p_novo_inicio  timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_appt    appointments%rowtype;
  v_tenant  tenants%rowtype;
  v_svc     services%rowtype;
  v_block   interval;
  v_fim     timestamptz;
  v_janela  numeric;
  v_weekday int;
  v_local   time;
begin
  select * into v_appt from appointments where manage_token = p_manage_token and deleted_at is null;
  if v_appt.id is null then
    raise exception 'booking_not_found' using errcode = 'P0001';
  end if;
  if v_appt.status not in ('agendado', 'confirmado') then
    raise exception 'booking_not_manageable' using errcode = 'P0001';
  end if;

  select * into v_tenant from tenants where id = v_appt.tenant_id;
  v_janela := coalesce((v_tenant.booking_policy ->> 'cancelamento_ate_horas')::numeric, 0);

  -- Janela de cancelamento/remarcação (§6.2)
  if v_appt.inicio_at <= now() + make_interval(mins => (v_janela * 60)::int) then
    raise exception 'cancel_window_closed' using errcode = 'P0001';
  end if;

  if p_acao = 'cancelar' then
    update appointments set status = 'cancelado' where id = v_appt.id;
    return jsonb_build_object('status', 'cancelado');

  elsif p_acao = 'remarcar' then
    if p_novo_inicio is null then
      raise exception 'missing_new_time' using errcode = 'P0001';
    end if;
    if p_novo_inicio <= now() then
      raise exception 'past_slot' using errcode = 'P0001';
    end if;

    select * into v_svc from services where id = v_appt.service_id;
    v_block := make_interval(mins => v_svc.duracao_min + coalesce(v_svc.buffer_min, 0));
    v_fim := p_novo_inicio + v_block;

    -- dentro do expediente do mesmo profissional
    v_weekday := extract(dow from (p_novo_inicio at time zone v_tenant.timezone))::int;
    v_local   := (p_novo_inicio at time zone v_tenant.timezone)::time;
    if not exists (
      select 1 from working_hours wh
      where wh.professional_id = v_appt.professional_id
        and wh.weekday = v_weekday
        and v_local >= wh.hora_inicio
        and (v_local + make_interval(mins => v_svc.duracao_min)) <= wh.hora_fim
    ) then
      raise exception 'outside_hours' using errcode = 'P0001';
    end if;

    -- fora de folgas/bloqueios
    if exists (
      select 1 from time_blocks tb
      where tb.professional_id = v_appt.professional_id
        and tstzrange(tb.inicio_at, tb.fim_at) && tstzrange(p_novo_inicio, v_fim)
    ) then
      raise exception 'slot_taken' using errcode = 'P0001';
    end if;

    begin
      update appointments
        set inicio_at = p_novo_inicio,
            fim_at = v_fim,
            status = 'agendado'  -- volta a aguardar confirmação após remarcar
      where id = v_appt.id;
    exception when exclusion_violation then
      raise exception 'slot_taken' using errcode = 'P0001';
    end;

    return jsonb_build_object('status', 'agendado', 'inicio_at', p_novo_inicio);
  else
    raise exception 'invalid_action' using errcode = 'P0001';
  end if;
end;
$$;

revoke all on function manage_booking(uuid, text, timestamptz) from public;
grant execute on function manage_booking(uuid, text, timestamptz) to anon, authenticated;

-- ---------------------------------------------------------------------
-- join_waitlist — cliente entra na lista de espera de um serviço quando
-- não há slot. Valida tenant/serviço; sem PII de terceiros.
-- ---------------------------------------------------------------------
create or replace function join_waitlist(
  p_tenant_slug     text,
  p_service_id      uuid,
  p_nome            text,
  p_contato         text,
  p_professional_id uuid default null,
  p_janela          jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_tenant tenants%rowtype; v_id uuid;
begin
  select * into v_tenant from tenants where slug = p_tenant_slug and status = 'ativo';
  if not found then
    raise exception 'tenant_not_found' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from services
    where id = p_service_id and tenant_id = v_tenant.id and ativo = true and deleted_at is null
  ) then
    raise exception 'service_unavailable' using errcode = 'P0001';
  end if;
  if length(trim(coalesce(p_nome, ''))) = 0 or length(trim(coalesce(p_contato, ''))) = 0 then
    raise exception 'invalid_input' using errcode = 'P0001';
  end if;

  insert into waitlist (tenant_id, service_id, professional_id, customer_nome, customer_contato, janela_desejada)
  values (v_tenant.id, p_service_id, p_professional_id, p_nome, p_contato, p_janela)
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function join_waitlist(text, uuid, text, text, uuid, jsonb) from public;
grant execute on function join_waitlist(text, uuid, text, text, uuid, jsonb) to anon, authenticated;
