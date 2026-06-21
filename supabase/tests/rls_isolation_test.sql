-- =====================================================================
-- Testes de isolamento multi-tenant (pgTAP) — cobre o CHECKLIST §8 do prompt.
-- Roda com:  supabase test db
--
-- Cada teste prova uma garantia de segurança:
--   • RLS habilitado E FORÇADO + default negar
--   • tenant A não lê/altera dados do tenant B
--   • staff só enxerga a própria agenda
--   • página pública não expõe PII
--   • overbooking é impossível no nível do banco
--   • usuário sem membership não vê nada
-- =====================================================================
begin;
select plan(16);

set local timezone = 'UTC';
create schema if not exists tests;
grant usage on schema tests to anon, authenticated;

-- ---------------------------------------------------------------------
-- Helpers de autenticação (simulam auth.uid() / role do PostgREST)
-- ---------------------------------------------------------------------
create or replace function tests._login(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid::text, 'role', 'authenticated')::text, true);
end $$;

create or replace function tests._anon() returns void
language plpgsql as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

-- Conta quantas linhas de clientes do tenant B um UPDATE atinge (sob RLS do
-- chamador). SECURITY INVOKER: roda como o role autenticado atual.
create or replace function tests._update_other_tenant() returns int
language plpgsql as $$
declare n int;
begin
  update customers set nome = 'hack'
    where tenant_id = 'bbbbbbbb-0000-0000-0000-000000000001';
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------------------------------------------------------------------
-- SETUP (como postgres/bypassrls): dois tenants isolados.
-- ---------------------------------------------------------------------
-- usuários
insert into auth.users (instance_id, id, aud, role, email) values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000a0001', 'authenticated', 'authenticated', 'ownerA@ex.com'),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000a0002', 'authenticated', 'authenticated', 'staffA@ex.com'),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000b0001', 'authenticated', 'authenticated', 'ownerB@ex.com'),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000e001', 'authenticated', 'authenticated', 'estranho@ex.com');

-- tenants
insert into tenants (id, nome, slug, timezone) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Tenant A', 'tenant-a', 'UTC'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'Tenant B', 'tenant-b', 'UTC');

-- memberships
insert into memberships (user_id, tenant_id, role) values
  ('00000000-0000-0000-0000-0000000a0001', 'aaaaaaaa-0000-0000-0000-000000000001', 'owner'),
  ('00000000-0000-0000-0000-0000000a0002', 'aaaaaaaa-0000-0000-0000-000000000001', 'staff'),
  ('00000000-0000-0000-0000-0000000b0001', 'bbbbbbbb-0000-0000-0000-000000000001', 'owner');

-- profissionais (staffA ligado a profA1)
insert into professionals (id, tenant_id, user_id, nome) values
  ('a1111111-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000a0002', 'Prof A1'),
  ('a2222222-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', null, 'Prof A2'),
  ('b1111111-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', null, 'Prof B1');

-- serviços
insert into services (id, tenant_id, nome, duracao_min, preco) values
  ('a5111111-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Serviço A', 60, 100),
  ('b5111111-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', 'Serviço B', 60, 100);

-- expediente: todos os dias 09:00–18:00 (UTC) para os profissionais de A
insert into working_hours (tenant_id, professional_id, weekday, hora_inicio, hora_fim)
select 'aaaaaaaa-0000-0000-0000-000000000001', p.id, d.wd, time '09:00', time '18:00'
from (values ('a1111111-0000-0000-0000-000000000001'::uuid), ('a2222222-0000-0000-0000-000000000001'::uuid)) p(id)
cross join generate_series(0, 6) d(wd);

-- clientes (PII)
insert into customers (id, tenant_id, nome, telefone, consentimento_lgpd_at) values
  ('ac111111-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Cliente A', '11999990001', now()),
  ('bc111111-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', 'Cliente B', '11999990002', now());

-- agendamentos: profA1 e profA2 cada um com 1; tenant B com 1
insert into appointments (tenant_id, professional_id, service_id, customer_id, inicio_at, fim_at) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a1111111-0000-0000-0000-000000000001', 'a5111111-0000-0000-0000-000000000001', 'ac111111-0000-0000-0000-000000000001', (current_date + 8 + time '10:00') at time zone 'UTC', (current_date + 8 + time '11:00') at time zone 'UTC'),
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a2222222-0000-0000-0000-000000000001', 'a5111111-0000-0000-0000-000000000001', 'ac111111-0000-0000-0000-000000000001', (current_date + 8 + time '12:00') at time zone 'UTC', (current_date + 8 + time '13:00') at time zone 'UTC'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'b1111111-0000-0000-0000-000000000001', 'b5111111-0000-0000-0000-000000000001', 'bc111111-0000-0000-0000-000000000001', (current_date + 8 + time '10:00') at time zone 'UTC', (current_date + 8 + time '11:00') at time zone 'UTC');

-- =====================================================================
-- 1–2. RLS habilitado E FORÇADO em tabelas sensíveis (§5.1)
-- =====================================================================
select ok(
  (select bool_and(relrowsecurity) from pg_class
   where relnamespace = 'public'::regnamespace
     and relname in ('tenants','appointments','customers','services','memberships')),
  'RLS habilitado nas tabelas de negócio'
);
select ok(
  (select bool_and(relforcerowsecurity) from pg_class
   where relnamespace = 'public'::regnamespace
     and relname in ('tenants','appointments','customers','services','memberships')),
  'RLS FORÇADO (force row level security) nas tabelas de negócio'
);

-- =====================================================================
-- 3–6. Owner do tenant A enxerga só o tenant A
-- =====================================================================
select tests._login('00000000-0000-0000-0000-0000000a0001');

select is(
  (select count(*) from appointments)::int, 2,
  'Owner A vê os 2 agendamentos do próprio tenant'
);
select is(
  (select count(*) from appointments where tenant_id = 'bbbbbbbb-0000-0000-0000-000000000001')::int, 0,
  'Owner A NÃO vê nenhum agendamento do tenant B'
);
select is(
  (select count(*) from customers where tenant_id = 'bbbbbbbb-0000-0000-0000-000000000001')::int, 0,
  'Owner A NÃO vê clientes (PII) do tenant B'
);
select is(
  (select count(*) from tenants)::int, 1,
  'Owner A enxerga apenas o próprio tenant na tabela tenants'
);

-- Owner A não consegue ALTERAR dado do tenant B (UPDATE não atinge linha)
select is(
  tests._update_other_tenant(), 0,
  'Owner A NÃO consegue alterar clientes do tenant B'
);

-- Owner A não consegue INSERIR em tenant alheio (WITH CHECK barra)
select throws_ok(
  $$ insert into services (tenant_id, nome, duracao_min) values ('bbbbbbbb-0000-0000-0000-000000000001', 'Intruso', 30) $$,
  '42501',
  null,
  'Owner A NÃO consegue inserir serviço no tenant B (WITH CHECK)'
);

-- =====================================================================
-- 7–8. Staff A só enxerga a PRÓPRIA agenda (§5.1 / ADENDO §11)
-- =====================================================================
select tests._login('00000000-0000-0000-0000-0000000a0002');

select is(
  (select count(*) from appointments)::int, 1,
  'Staff A vê apenas 1 agendamento (o do próprio profissional)'
);
select is(
  (select count(*) from appointments where professional_id <> 'a1111111-0000-0000-0000-000000000001')::int, 0,
  'Staff A NÃO vê agendamentos de outros profissionais (nem do mesmo tenant)'
);

-- =====================================================================
-- 9. Usuário sem membership não vê nada (default = negar)
-- =====================================================================
select tests._login('00000000-0000-0000-0000-00000000e001');
select is(
  (select count(*) from tenants)::int + (select count(*) from appointments)::int, 0,
  'Usuário sem vínculo não enxerga nenhuma linha (default deny)'
);

-- =====================================================================
-- 10–12. Fluxo público (anon) não vaza PII (§5.3)
-- =====================================================================
select tests._anon();

select ok(
  (get_public_establishment('tenant-a') ?& array['nome','servicos','profissionais']),
  'Capa pública expõe nome/serviços/profissionais'
);
select ok(
  not (get_public_establishment('tenant-a')::text ilike '%telefone%')
  and not (get_public_establishment('tenant-a')::text ilike '%cliente%'),
  'Capa pública NÃO contém PII de clientes'
);
select ok(
  (select count(*) from get_available_slots('tenant-a', 'a5111111-0000-0000-0000-000000000001', (current_date + 9)::date, 'a1111111-0000-0000-0000-000000000001')) > 0,
  'get_available_slots devolve horários livres (sem expor ocupados/PII)'
);

-- anon NÃO consegue ler a tabela de clientes diretamente (sem privilégio)
select throws_ok(
  $$ select count(*) from customers $$,
  '42501',
  null,
  'Anon NÃO lê a tabela customers diretamente (permission denied; só via RPC)'
);

-- =====================================================================
-- 13. Overbooking impossível no nível do banco (§5.4)
-- =====================================================================
reset role;
select throws_ok(
  $$ insert into appointments (tenant_id, professional_id, service_id, customer_id, inicio_at, fim_at)
     values ('aaaaaaaa-0000-0000-0000-000000000001', 'a1111111-0000-0000-0000-000000000001',
             'a5111111-0000-0000-0000-000000000001', 'ac111111-0000-0000-0000-000000000001',
             (current_date + 8 + time '10:30') at time zone 'UTC', (current_date + 8 + time '11:30') at time zone 'UTC') $$,
  '23P01', -- exclusion_violation
  null,
  'Constraint EXCLUDE impede agendamento sobreposto para o mesmo profissional'
);

select * from finish();
rollback;
