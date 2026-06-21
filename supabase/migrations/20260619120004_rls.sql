-- =====================================================================
-- 0004 — Row Level Security (§5.1)
-- RLS HABILITADO **E FORÇADO** em todas as tabelas (inclusive p/ o owner).
-- Default = negar tudo: habilitar RLS sem policy já bloqueia o acesso.
-- Policies separadas por operação e por role. tenant_id sempre validado
-- via current_tenant_ids(); INSERT/UPDATE validam com WITH CHECK.
-- =====================================================================

-- Habilita + força em TODAS as tabelas.
do $$
declare t text;
begin
  foreach t in array array[
    'tenants','profiles','memberships','professionals','services',
    'working_hours','customers','appointments','reminders',
    'audit_log','booking_attempts'
  ] loop
    execute format('alter table %I enable row level security;', t);
    execute format('alter table %I force row level security;', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- tenants — membro lê o próprio tenant; só owner edita.
-- ---------------------------------------------------------------------
create policy tenants_select on tenants for select to authenticated
  using (id in (select current_tenant_ids()));
create policy tenants_update on tenants for update to authenticated
  using (is_tenant_owner(id)) with check (is_tenant_owner(id));

-- ---------------------------------------------------------------------
-- profiles — cada um lê/edita o próprio perfil.
-- ---------------------------------------------------------------------
create policy profiles_select on profiles for select to authenticated
  using (id = auth.uid());
create policy profiles_insert on profiles for insert to authenticated
  with check (id = auth.uid());
create policy profiles_update on profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- ---------------------------------------------------------------------
-- memberships — vê o próprio vínculo; owner vê/gerencia os do seu tenant.
-- (is_tenant_owner é SECURITY DEFINER → não recursa em memberships)
-- ---------------------------------------------------------------------
create policy memberships_select on memberships for select to authenticated
  using (user_id = auth.uid() or is_tenant_owner(tenant_id));
create policy memberships_insert on memberships for insert to authenticated
  with check (is_tenant_owner(tenant_id));
create policy memberships_update on memberships for update to authenticated
  using (is_tenant_owner(tenant_id)) with check (is_tenant_owner(tenant_id));
create policy memberships_delete on memberships for delete to authenticated
  using (is_tenant_owner(tenant_id));

-- ---------------------------------------------------------------------
-- professionals — tenant inteiro lê; só owner escreve.
-- ---------------------------------------------------------------------
create policy professionals_select on professionals for select to authenticated
  using (tenant_id in (select current_tenant_ids()));
create policy professionals_insert on professionals for insert to authenticated
  with check (is_tenant_owner(tenant_id));
create policy professionals_update on professionals for update to authenticated
  using (is_tenant_owner(tenant_id)) with check (is_tenant_owner(tenant_id));
create policy professionals_delete on professionals for delete to authenticated
  using (is_tenant_owner(tenant_id));

-- ---------------------------------------------------------------------
-- services — tenant inteiro lê; só owner escreve.
-- ---------------------------------------------------------------------
create policy services_select on services for select to authenticated
  using (tenant_id in (select current_tenant_ids()));
create policy services_insert on services for insert to authenticated
  with check (is_tenant_owner(tenant_id));
create policy services_update on services for update to authenticated
  using (is_tenant_owner(tenant_id)) with check (is_tenant_owner(tenant_id));
create policy services_delete on services for delete to authenticated
  using (is_tenant_owner(tenant_id));

-- ---------------------------------------------------------------------
-- working_hours — tenant inteiro lê; só owner escreve.
-- ---------------------------------------------------------------------
create policy working_hours_select on working_hours for select to authenticated
  using (tenant_id in (select current_tenant_ids()));
create policy working_hours_insert on working_hours for insert to authenticated
  with check (is_tenant_owner(tenant_id));
create policy working_hours_update on working_hours for update to authenticated
  using (is_tenant_owner(tenant_id)) with check (is_tenant_owner(tenant_id));
create policy working_hours_delete on working_hours for delete to authenticated
  using (is_tenant_owner(tenant_id));

-- ---------------------------------------------------------------------
-- customers — tenant inteiro lê/escreve (PII fica no tenant).
-- ---------------------------------------------------------------------
create policy customers_select on customers for select to authenticated
  using (tenant_id in (select current_tenant_ids()));
create policy customers_insert on customers for insert to authenticated
  with check (tenant_id in (select current_tenant_ids()));
create policy customers_update on customers for update to authenticated
  using (tenant_id in (select current_tenant_ids()))
  with check (tenant_id in (select current_tenant_ids()));

-- ---------------------------------------------------------------------
-- appointments — owner vê o tenant inteiro; staff só a PRÓPRIA agenda.
-- ---------------------------------------------------------------------
create policy appointments_select on appointments for select to authenticated
  using (
    tenant_id in (select current_tenant_ids())
    and (is_tenant_owner(tenant_id) or professional_id = current_professional_id(tenant_id))
  );
create policy appointments_insert on appointments for insert to authenticated
  with check (
    tenant_id in (select current_tenant_ids())
    and (is_tenant_owner(tenant_id) or professional_id = current_professional_id(tenant_id))
  );
create policy appointments_update on appointments for update to authenticated
  using (
    tenant_id in (select current_tenant_ids())
    and (is_tenant_owner(tenant_id) or professional_id = current_professional_id(tenant_id))
  )
  with check (
    tenant_id in (select current_tenant_ids())
    and (is_tenant_owner(tenant_id) or professional_id = current_professional_id(tenant_id))
  );

-- ---------------------------------------------------------------------
-- reminders — leitura pelo tenant; escrita só pelo servidor (definer/cron).
-- ---------------------------------------------------------------------
create policy reminders_select on reminders for select to authenticated
  using (tenant_id in (select current_tenant_ids()));

-- ---------------------------------------------------------------------
-- audit_log — só owner lê; escrita exclusivamente via trigger (definer).
-- ---------------------------------------------------------------------
create policy audit_select on audit_log for select to authenticated
  using (is_tenant_owner(tenant_id));

-- ---------------------------------------------------------------------
-- booking_attempts — sem policy: ninguém acessa direto.
-- Escrita/leitura só via RPCs SECURITY DEFINER do fluxo público.
-- ---------------------------------------------------------------------
