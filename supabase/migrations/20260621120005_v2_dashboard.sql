-- =====================================================================
-- 0014 (v2) — Dashboard do dono (§6.6)
-- RPC SECURITY DEFINER que agrega métricas do tenant. Só o OWNER executa
-- (checagem explícita). Métricas que orientam retenção, não vaidade.
-- =====================================================================

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

  -- faturamento estimado: soma do preço dos serviços concluídos no período
  select coalesce(sum(s.preco), 0) into v_faturamento
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
    -- taxa de no-show sobre o que foi finalizado (concluído + faltou)
    'taxa_no_show', case when (v_concluidos + v_no_show) > 0
      then round(v_no_show::numeric / (v_concluidos + v_no_show), 4) else 0 end,
    'top_servicos', v_top
  );
end;
$$;

revoke all on function get_owner_dashboard(uuid, integer) from public;
grant execute on function get_owner_dashboard(uuid, integer) to authenticated;
