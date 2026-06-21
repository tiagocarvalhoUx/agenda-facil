-- =====================================================================
-- 0007 — LGPD: direito ao esquecimento (§5.5 / ADENDO §20)
-- Anonimiza o cliente preservando integridade do histórico (FKs intactas).
-- Só o OWNER do tenant pode executar. Auditado pelo trigger de customers.
-- =====================================================================

create or replace function anonimizar_cliente(p_customer_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_tenant uuid;
begin
  select tenant_id into v_tenant from customers where id = p_customer_id;
  if v_tenant is null then
    raise exception 'customer_not_found' using errcode = 'P0001';
  end if;
  if not is_tenant_owner(v_tenant) then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  update customers
    set nome = 'Cliente removido',
        telefone = 'anon-' || left(id::text, 12),
        email = null,
        anonimizado_at = now(),
        deleted_at = now()
  where id = p_customer_id;
end;
$$;

revoke all on function anonimizar_cliente(uuid) from public;
grant execute on function anonimizar_cliente(uuid) to authenticated;
