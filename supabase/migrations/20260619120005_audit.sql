-- =====================================================================
-- 0005 — Auditoria (§5.5)
-- Trigger SECURITY DEFINER grava em audit_log em INSERT/UPDATE/DELETE das
-- tabelas sensíveis (appointments, customers, services). Definer permite
-- escrever mesmo com FORCE RLS ligado no audit_log.
-- =====================================================================

create or replace function fn_audit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tenant uuid;
  v_record uuid;
  v_payload jsonb;
begin
  if (tg_op = 'DELETE') then
    v_tenant  := old.tenant_id;
    v_record  := old.id;
    v_payload := to_jsonb(old);
  else
    v_tenant  := new.tenant_id;
    v_record  := new.id;
    v_payload := to_jsonb(new);
  end if;

  insert into audit_log (tenant_id, user_id, acao, tabela, registro_id, payload)
  values (v_tenant, auth.uid(), tg_op, tg_table_name, v_record, v_payload);

  if (tg_op = 'DELETE') then
    return old;
  end if;
  return new;
end;
$$;

create trigger trg_audit_appointments
  after insert or update or delete on appointments
  for each row execute function fn_audit();

create trigger trg_audit_customers
  after insert or update or delete on customers
  for each row execute function fn_audit();

create trigger trg_audit_services
  after insert or update or delete on services
  for each row execute function fn_audit();
