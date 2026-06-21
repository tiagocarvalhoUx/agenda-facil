-- =====================================================================
-- 0006 — Fluxo público SEM acesso direto a tabelas (§5.3)
-- O cliente final só chama estas RPCs SECURITY DEFINER. Elas:
--   • derivam o tenant pelo slug (nunca recebem tenant_id do cliente);
--   • validam tudo no servidor (serviço ativo, expediente, slot livre);
--   • retornam SOMENTE horários livres — nenhum PII de terceiros;
--   • aplicam rate limiting por IP/telefone (§5.3).
-- =====================================================================

-- Fuso do tenant (necessário para casar working_hours [time] com timestamptz).
alter table tenants add column if not exists timezone text not null default 'America/Sao_Paulo';

-- ---------------------------------------------------------------------
-- get_available_slots — retorna apenas slots livres do dia.
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
  v_tenant   tenants%rowtype;
  v_duracao  integer;
  v_step     interval;
begin
  select * into v_tenant from tenants where slug = p_tenant_slug and status = 'ativo';
  if not found then
    return; -- tenant inexistente/inativo: nada a expor
  end if;

  select duracao_min into v_duracao
  from services
  where id = p_service_id and tenant_id = v_tenant.id and ativo = true and deleted_at is null;
  if v_duracao is null then
    return; -- serviço inválido para este tenant
  end if;
  v_step := make_interval(mins => v_duracao);

  return query
  with profs as (
    select pr.id
    from professionals pr
    where pr.tenant_id = v_tenant.id
      and pr.ativo = true
      and pr.deleted_at is null
      and (p_professional_id is null or pr.id = p_professional_id)
  ),
  windows as (
    -- janela de expediente do dia (em timestamptz, no fuso do tenant)
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
      gs + v_step as cand_fim
    from windows w
    cross join lateral generate_series(w.win_start, w.win_end - v_step, v_step) as gs
    where gs + v_step <= w.win_end
      and gs > now() -- nunca oferecer horário passado
  )
  select c.cand_inicio, c.cand_fim, c.professional_id
  from candidates c
  where not exists (
    select 1 from appointments a
    where a.professional_id = c.professional_id
      and a.status <> 'cancelado'
      and a.deleted_at is null
      and tstzrange(a.inicio_at, a.fim_at) && tstzrange(c.cand_inicio, c.cand_fim)
  )
  order by c.cand_inicio, c.professional_id;
end;
$$;

-- ---------------------------------------------------------------------
-- create_booking — cria o agendamento com validação rígida + rate limit.
-- Retorna o id do appointment. Erros usam SQLSTATE 'P0001' com mensagens
-- estáveis ('rate_limited', 'slot_taken', etc.) consumidas pela UI.
-- ---------------------------------------------------------------------
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
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tenant      tenants%rowtype;
  v_duracao     integer;
  v_fim         timestamptz;
  v_prof        uuid;
  v_customer_id uuid;
  v_appt_id     uuid;
  v_recent_tel  integer;
  v_recent_ip   integer;
  v_weekday     int;
  v_local_time  time;
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

  -- ---- LGPD: consentimento explícito obrigatório (§5.5) ----
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

  -- ---- Serviço válido/ativo ----
  select duracao_min into v_duracao
  from services
  where id = p_service_id and tenant_id = v_tenant.id and ativo = true and deleted_at is null;
  if v_duracao is null then
    raise exception 'service_unavailable' using errcode = 'P0001';
  end if;
  v_fim := p_inicio + make_interval(mins => v_duracao);

  -- ---- Profissional: explícito ou "qualquer disponível" ----
  if p_professional_id is not null then
    select id into v_prof from professionals
    where id = p_professional_id and tenant_id = v_tenant.id and ativo = true and deleted_at is null;
    if v_prof is null then
      raise exception 'professional_unavailable' using errcode = 'P0001';
    end if;
  else
    -- escolhe o primeiro profissional ativo livre nesse intervalo
    select pr.id into v_prof
    from professionals pr
    where pr.tenant_id = v_tenant.id and pr.ativo = true and pr.deleted_at is null
      and not exists (
        select 1 from appointments a
        where a.professional_id = pr.id and a.status <> 'cancelado' and a.deleted_at is null
          and tstzrange(a.inicio_at, a.fim_at) && tstzrange(p_inicio, v_fim)
      )
    order by pr.created_at
    limit 1;
    if v_prof is null then
      raise exception 'slot_taken' using errcode = 'P0001';
    end if;
  end if;

  -- ---- Dentro do expediente do profissional? ----
  v_weekday := extract(dow from (p_inicio at time zone v_tenant.timezone))::int;
  v_local_time := (p_inicio at time zone v_tenant.timezone)::time;
  if not exists (
    select 1 from working_hours wh
    where wh.professional_id = v_prof
      and wh.weekday = v_weekday
      and v_local_time >= wh.hora_inicio
      and (v_local_time + make_interval(mins => v_duracao)) <= wh.hora_fim
  ) then
    raise exception 'outside_hours' using errcode = 'P0001';
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

  -- ---- Cria o agendamento (EXCLUDE é a barreira final do overbooking) ----
  begin
    insert into appointments
      (tenant_id, professional_id, service_id, customer_id, inicio_at, fim_at, status, origem)
    values
      (v_tenant.id, v_prof, p_service_id, v_customer_id, p_inicio, v_fim, 'agendado', 'publico')
    returning id into v_appt_id;
  exception when exclusion_violation then
    raise exception 'slot_taken' using errcode = 'P0001';
  end;

  -- Lembretes (24h/2h) são enfileirados pelo trigger fn_enqueue_reminders,
  -- que cobre agendamentos do público e do painel de forma uniforme.

  update booking_attempts set sucesso = true
    where tenant_id = v_tenant.id and telefone = p_telefone
      and created_at > now() - interval '1 minute';

  return v_appt_id;
end;
$$;

-- Exposição: anon (cliente final) + authenticated. NUNCA service_role no front.
revoke all on function get_available_slots(text, uuid, date, uuid) from public;
revoke all on function create_booking(text, uuid, uuid, timestamptz, text, text, text, boolean, text) from public;
grant execute on function get_available_slots(text, uuid, date, uuid) to anon, authenticated;
grant execute on function create_booking(text, uuid, uuid, timestamptz, text, text, text, boolean, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- get_public_establishment — dados públicos da capa (§15.1): nome, accent,
-- serviços ativos, profissionais ativos. NADA além disso.
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
    'vertical', v_tenant.vertical,
    'timezone', v_tenant.timezone,
    'servicos', coalesce((
      select jsonb_agg(jsonb_build_object('id', s.id, 'nome', s.nome,
                       'duracao_min', s.duracao_min, 'preco', s.preco)
                       order by s.nome)
      from services s
      where s.tenant_id = v_tenant.id and s.ativo = true and s.deleted_at is null
    ), '[]'::jsonb),
    'profissionais', coalesce((
      select jsonb_agg(jsonb_build_object('id', pr.id, 'nome', pr.nome) order by pr.nome)
      from professionals pr
      where pr.tenant_id = v_tenant.id and pr.ativo = true and pr.deleted_at is null
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function get_public_establishment(text) from public;
grant execute on function get_public_establishment(text) to anon, authenticated;
