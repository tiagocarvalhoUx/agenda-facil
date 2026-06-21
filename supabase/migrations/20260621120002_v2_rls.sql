-- =====================================================================
-- 0011 (v2) — RLS + GRANTs das novas tabelas (§5.1)
-- Mesmo contrato da v1: RLS HABILITADO E FORÇADO, default = negar,
-- tenant_id validado via current_tenant_ids(), WITH CHECK em escrita.
--   • professional_services: tenant lê; só owner escreve.
--   • time_blocks: tenant lê; owner gerencia o tenant, staff só os próprios.
--   • waitlist: tenant lê/gerencia; INSERT público é via RPC SECURITY DEFINER.
-- =====================================================================

do $$
declare t text;
begin
  foreach t in array array['professional_services','time_blocks','waitlist'] loop
    execute format('alter table %I enable row level security;', t);
    execute format('alter table %I force row level security;', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- professional_services — tenant lê; só owner escreve.
-- ---------------------------------------------------------------------
create policy prof_services_select on professional_services for select to authenticated
  using (tenant_id in (select current_tenant_ids()));
create policy prof_services_insert on professional_services for insert to authenticated
  with check (is_tenant_owner(tenant_id));
create policy prof_services_delete on professional_services for delete to authenticated
  using (is_tenant_owner(tenant_id));

-- ---------------------------------------------------------------------
-- time_blocks — tenant lê; owner gerencia tudo, staff só o próprio bloqueio.
-- ---------------------------------------------------------------------
create policy time_blocks_select on time_blocks for select to authenticated
  using (tenant_id in (select current_tenant_ids()));
create policy time_blocks_insert on time_blocks for insert to authenticated
  with check (
    tenant_id in (select current_tenant_ids())
    and (is_tenant_owner(tenant_id) or professional_id = current_professional_id(tenant_id))
  );
create policy time_blocks_update on time_blocks for update to authenticated
  using (
    tenant_id in (select current_tenant_ids())
    and (is_tenant_owner(tenant_id) or professional_id = current_professional_id(tenant_id))
  )
  with check (
    tenant_id in (select current_tenant_ids())
    and (is_tenant_owner(tenant_id) or professional_id = current_professional_id(tenant_id))
  );
create policy time_blocks_delete on time_blocks for delete to authenticated
  using (
    tenant_id in (select current_tenant_ids())
    and (is_tenant_owner(tenant_id) or professional_id = current_professional_id(tenant_id))
  );

-- ---------------------------------------------------------------------
-- waitlist — tenant lê e gerencia. O INSERT do cliente final é feito por
-- RPC SECURITY DEFINER (join_waitlist); aqui cobrimos o painel.
-- ---------------------------------------------------------------------
create policy waitlist_select on waitlist for select to authenticated
  using (tenant_id in (select current_tenant_ids()));
create policy waitlist_insert on waitlist for insert to authenticated
  with check (tenant_id in (select current_tenant_ids()));
create policy waitlist_update on waitlist for update to authenticated
  using (tenant_id in (select current_tenant_ids()))
  with check (tenant_id in (select current_tenant_ids()));
create policy waitlist_delete on waitlist for delete to authenticated
  using (is_tenant_owner(tenant_id));

-- ---------------------------------------------------------------------
-- GRANTs de privilégio de tabela (a RLS aplica o recorte fino).
-- anon continua SEM privilégio de tabela: fluxo público só via RPC.
-- ---------------------------------------------------------------------
grant select, insert, update, delete on
  professional_services, time_blocks, waitlist
to authenticated;

-- ---------------------------------------------------------------------
-- Auditoria das novas tabelas sensíveis de disponibilidade.
-- ---------------------------------------------------------------------
create trigger trg_audit_time_blocks
  after insert or update or delete on time_blocks
  for each row execute function fn_audit();
