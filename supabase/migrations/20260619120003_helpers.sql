-- =====================================================================
-- 0003 — Funções auxiliares de identidade/tenant (§5.1)
-- SECURITY DEFINER + STABLE. São o único caminho que lê memberships dentro
-- das policies, evitando recursão de RLS. search_path fixo (anti-hijack).
-- O tenant_id NUNCA vem do cliente — é sempre derivado de auth.uid() aqui.
-- =====================================================================

-- Tenants aos quais o usuário autenticado pertence.
create or replace function current_tenant_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select tenant_id from memberships where user_id = auth.uid();
$$;

-- O usuário é OWNER do tenant informado?
create or replace function is_tenant_owner(p_tenant uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from memberships
    where user_id = auth.uid() and tenant_id = p_tenant and role = 'owner'
  );
$$;

-- Id do profissional (staff) ligado ao usuário dentro do tenant (ou null).
create or replace function current_professional_id(p_tenant uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select id from professionals
  where tenant_id = p_tenant and user_id = auth.uid() and deleted_at is null
  limit 1;
$$;

revoke all on function current_tenant_ids() from public;
revoke all on function is_tenant_owner(uuid) from public;
revoke all on function current_professional_id(uuid) from public;
grant execute on function current_tenant_ids() to authenticated;
grant execute on function is_tenant_owner(uuid) to authenticated;
grant execute on function current_professional_id(uuid) to authenticated;
