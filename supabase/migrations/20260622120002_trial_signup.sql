-- =====================================================================
-- 0016 (v2) — Trial de 7 dias + auto-criação do estabelecimento (self-serve)
-- - Todo tenant novo nasce com 7 dias grátis (status 'trial').
-- - Ao expirar sem assinatura ativa, o app bloqueia (paywall no frontend).
-- - create_tenant: novo usuário (ex.: login Google) cria o próprio
--   estabelecimento com segurança (RLS não deixa inserir tenant direto).
-- =====================================================================

alter table tenant_billing add column if not exists trial_ends_at timestamptz;

-- ----- Trial automático ao criar um tenant -----
create or replace function fn_init_trial()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into tenant_billing (tenant_id, status, trial_ends_at)
  values (new.id, 'trial', now() + interval '7 days')
  on conflict (tenant_id) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_init_trial on tenants;
create trigger trg_init_trial
  after insert on tenants
  for each row execute function fn_init_trial();

-- Backfill: tenants existentes sem billing ganham 7 dias a partir de agora
-- (para o dono atual continuar com acesso enquanto testa).
insert into tenant_billing (tenant_id, status, trial_ends_at)
select t.id, 'trial', now() + interval '7 days'
from tenants t
where not exists (select 1 from tenant_billing b where b.tenant_id = t.id);

-- ----- create_tenant: auto-criação do estabelecimento pelo próprio usuário -----
-- SECURITY DEFINER porque a RLS não permite INSERT direto em tenants. Cria o
-- tenant, o profile e a membership 'owner' para auth.uid(). Idempotente: se o
-- usuário já é dono de algum tenant, devolve esse.
create or replace function create_tenant(
  p_nome     text,
  p_slug     text,
  p_vertical text default 'outro'
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_tenant uuid;
begin
  if v_uid is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- já é dono de algum tenant? devolve o primeiro.
  select tenant_id into v_tenant
  from memberships where user_id = v_uid and role = 'owner'
  order by created_at limit 1;
  if v_tenant is not null then
    return v_tenant;
  end if;

  if p_nome is null or length(trim(p_nome)) = 0 then
    raise exception 'invalid_name' using errcode = 'P0001';
  end if;
  if p_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
    raise exception 'invalid_slug' using errcode = 'P0001';
  end if;
  if exists (select 1 from tenants where slug = p_slug) then
    raise exception 'slug_taken' using errcode = 'P0001';
  end if;

  insert into tenants (nome, slug, vertical)
  values (trim(p_nome), p_slug, nullif(p_vertical, ''))
  returning id into v_tenant;
  -- o trigger trg_init_trial já cria o tenant_billing com 7 dias.

  insert into profiles (id) values (v_uid) on conflict (id) do nothing;

  insert into memberships (user_id, tenant_id, role)
  values (v_uid, v_tenant, 'owner');

  return v_tenant;
end;
$$;

revoke all on function create_tenant(text, text, text) from public;
grant execute on function create_tenant(text, text, text) to authenticated;
