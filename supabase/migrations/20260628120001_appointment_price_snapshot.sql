-- =====================================================================
-- 0012 — Snapshot de preço no agendamento (preco_total)
-- Congela o valor do serviço no momento da criação para que o histórico
-- financeiro NÃO mude quando o preço do serviço for reajustado depois.
-- Leituras usam coalesce(preco_total, services.preco) p/ retrocompatibilidade.
-- =====================================================================

alter table appointments
  add column if not exists preco_total numeric;

comment on column appointments.preco_total is
  'Preço do serviço congelado na criação (snapshot). Reajustes futuros no serviço não alteram este valor.';

-- Backfill: agendamentos existentes herdam o preço ATUAL do serviço — melhor
-- aproximação disponível; daqui pra frente o valor fica congelado no insert.
update appointments a
  set preco_total = s.preco
  from services s
  where s.id = a.service_id
    and a.preco_total is null;

-- ---------------------------------------------------------------------
-- create_booking: passa a gravar o preço congelado no insert (origem público)
-- Redefinição com a assinatura idêntica (preserva grants). Igual à 0011,
-- apenas acrescentando `preco_total` ao INSERT.
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
  -- Ao reaproveitar, NÃO sobrescreve o nome (preserva o primeiro cadastro);
  -- só atualiza email/consentimento e reativa se estava soft-deletado.
  select id into v_customer_id from customers
    where tenant_id = v_tenant.id and telefone = p_telefone;
  if v_customer_id is null then
    insert into customers (tenant_id, nome, telefone, email, consentimento_lgpd_at)
    values (v_tenant.id, p_nome, p_telefone, nullif(p_email, ''), now())
    returning id into v_customer_id;
  else
    update customers
      set email = coalesce(nullif(p_email, ''), email),
          consentimento_lgpd_at = now(),
          deleted_at = null
      where id = v_customer_id;
  end if;

  v_dep_status := case when v_svc.exige_deposito then 'pendente' else 'nao_exigido' end;

  -- ---- Cria o agendamento (EXCLUDE é a barreira final do overbooking) ----
  -- preco_total = preço do serviço CONGELADO neste momento.
  begin
    insert into appointments
      (tenant_id, professional_id, service_id, customer_id, inicio_at, fim_at,
       status, origem, deposito_status, preco_total)
    values
      (v_tenant.id, v_prof, p_service_id, v_customer_id, p_inicio, v_fim,
       'agendado', 'publico', v_dep_status, v_svc.preco)
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

-- ---------------------------------------------------------------------
-- get_owner_dashboard: faturamento usa o preço CONGELADO quando houver,
-- caindo no preço atual do serviço para linhas antigas (coalesce).
-- ---------------------------------------------------------------------
create or replace function get_owner_dashboard(p_tenant_id uuid, p_days integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_from        timestamptz := now() - make_interval(days => greatest(p_days, 1));
  v_tz          text;
  v_hoje        integer;
  v_total       integer;
  v_concluidos  integer;
  v_no_show     integer;
  v_cancelados  integer;
  v_faturamento numeric;
  v_top         jsonb;
begin
  if not is_tenant_owner(p_tenant_id) then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  select timezone into v_tz from tenants where id = p_tenant_id;

  -- agendamentos de hoje (ativos), no fuso do tenant
  select count(*) into v_hoje
  from appointments
  where tenant_id = p_tenant_id
    and deleted_at is null
    and status <> 'cancelado'
    and (inicio_at at time zone v_tz)::date = (now() at time zone v_tz)::date;

  -- métricas do período
  select
    count(*) filter (where status <> 'cancelado'),
    count(*) filter (where status = 'concluido'),
    count(*) filter (where status = 'no_show'),
    count(*) filter (where status = 'cancelado')
  into v_total, v_concluidos, v_no_show, v_cancelados
  from appointments
  where tenant_id = p_tenant_id
    and deleted_at is null
    and inicio_at >= v_from;

  -- faturamento: soma do preço CONGELADO (fallback p/ preço atual) dos concluídos
  select coalesce(sum(coalesce(a.preco_total, s.preco)), 0) into v_faturamento
  from appointments a
  join services s on s.id = a.service_id
  where a.tenant_id = p_tenant_id
    and a.deleted_at is null
    and a.status = 'concluido'
    and a.inicio_at >= v_from;

  -- serviços mais agendados (top 5)
  select coalesce(jsonb_agg(t), '[]'::jsonb) into v_top
  from (
    select s.nome, count(*) as total
    from appointments a
    join services s on s.id = a.service_id
    where a.tenant_id = p_tenant_id
      and a.deleted_at is null
      and a.status <> 'cancelado'
      and a.inicio_at >= v_from
    group by s.nome
    order by total desc
    limit 5
  ) t;

  return jsonb_build_object(
    'periodo_dias', p_days,
    'agendamentos_hoje', v_hoje,
    'total_periodo', v_total,
    'concluidos', v_concluidos,
    'no_show', v_no_show,
    'cancelados', v_cancelados,
    'faturamento_estimado', v_faturamento,
    'taxa_no_show', case when (v_concluidos + v_no_show) > 0
      then round(v_no_show::numeric / (v_concluidos + v_no_show), 4) else 0 end,
    'top_servicos', v_top
  );
end;
$$;

revoke all on function get_owner_dashboard(uuid, integer) from public;
grant execute on function get_owner_dashboard(uuid, integer) to authenticated;
