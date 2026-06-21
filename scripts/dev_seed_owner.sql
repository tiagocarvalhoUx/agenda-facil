-- Seed de DEMO (apenas dev): cria um dono logável + agendamentos de hoje no
-- tenant Studio Bem-Estar, para visualizar o painel por dentro. NÃO migration.
do $$
declare
  v_tenant uuid;
  v_ana uuid;
  v_rui uuid;
  v_svc_corte uuid;
  v_svc_mani uuid;
  v_svc_mass uuid;
  v_c1 uuid; v_c2 uuid; v_c3 uuid; v_c4 uuid;
  v_owner uuid := '00000000-0000-0000-0000-0000000d0001';
  -- "Hoje" no fuso do tenant, não em UTC: o container do Postgres roda em UTC,
  -- então current_date pode cair um dia à frente do "hoje" do navegador.
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  select id into v_tenant from tenants where slug = 'studio-bem-estar';
  select id into v_ana from professionals where tenant_id = v_tenant and nome = 'Ana Costa';
  select id into v_rui from professionals where tenant_id = v_tenant and nome = 'Rui Almeida';
  select id into v_svc_corte from services where tenant_id = v_tenant and nome = 'Corte de cabelo';
  select id into v_svc_mani from services where tenant_id = v_tenant and nome = 'Manicure';
  select id into v_svc_mass from services where tenant_id = v_tenant and nome = 'Massagem relaxante';

  -- usuário dono (passwordless / magic link)
  -- As colunas de token precisam ser '' (não NULL): o GoTrue atual faz Scan
  -- para string e quebra com NULL ("converting NULL to string is unsupported").
  insert into auth.users (
    instance_id, id, aud, role, email, email_confirmed_at, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    email_change_token_current, phone_change, phone_change_token, reauthentication_token
  )
  values ('00000000-0000-0000-0000-000000000000', v_owner, 'authenticated', 'authenticated',
          'dono@studio.com', now(), now(), now(),
          '', '', '', '', '', '', '', '')
  on conflict (id) do nothing;

  -- Identidade de e-mail: sem ela o generate_link/admin retorna
  -- "Database error finding user" nas versões recentes do GoTrue.
  insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (v_owner::text, v_owner,
          jsonb_build_object('sub', v_owner::text, 'email', 'dono@studio.com'),
          'email', now(), now(), now())
  on conflict do nothing;

  insert into profiles (id, nome) values (v_owner, 'Dona do Studio') on conflict (id) do nothing;
  insert into memberships (user_id, tenant_id, role) values (v_owner, v_tenant, 'owner')
    on conflict (user_id, tenant_id) do nothing;

  -- clientes
  insert into customers (tenant_id, nome, telefone, email, consentimento_lgpd_at) values
    (v_tenant, 'Marina Silva', '11988880001', 'marina@ex.com', now()),
    (v_tenant, 'Bruno Carvalho', '11988880002', 'bruno@ex.com', now()),
    (v_tenant, 'Carla Souza', '11988880003', null, now()),
    (v_tenant, 'Diego Lima', '11988880004', 'diego@ex.com', now())
  on conflict (tenant_id, telefone) do nothing;
  select id into v_c1 from customers where tenant_id = v_tenant and telefone = '11988880001';
  select id into v_c2 from customers where tenant_id = v_tenant and telefone = '11988880002';
  select id into v_c3 from customers where tenant_id = v_tenant and telefone = '11988880003';
  select id into v_c4 from customers where tenant_id = v_tenant and telefone = '11988880004';

  -- agendamentos de HOJE (no fuso do tenant), status variados (a agenda abre em hoje)
  delete from appointments where tenant_id = v_tenant; -- idempotente p/ re-run
  insert into appointments (tenant_id, professional_id, service_id, customer_id, inicio_at, fim_at, status, origem) values
    (v_tenant, v_ana, v_svc_corte, v_c1, (v_hoje + time '09:00') at time zone 'America/Sao_Paulo', (v_hoje + time '09:45') at time zone 'America/Sao_Paulo', 'confirmado', 'painel'),
    (v_tenant, v_ana, v_svc_mani,  v_c2, (v_hoje + time '10:30') at time zone 'America/Sao_Paulo', (v_hoje + time '11:30') at time zone 'America/Sao_Paulo', 'agendado', 'publico'),
    (v_tenant, v_rui, v_svc_mass,  v_c3, (v_hoje + time '13:00') at time zone 'America/Sao_Paulo', (v_hoje + time '14:30') at time zone 'America/Sao_Paulo', 'concluido', 'painel'),
    (v_tenant, v_rui, v_svc_corte, v_c4, (v_hoje + time '15:30') at time zone 'America/Sao_Paulo', (v_hoje + time '16:15') at time zone 'America/Sao_Paulo', 'no_show', 'publico');
end $$;
