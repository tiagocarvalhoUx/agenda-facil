-- ONBOARDING DE PRODUÇÃO (rodar 1x no SQL Editor do Supabase).
-- Cria um estabelecimento (tenant) e torna o usuário (já cadastrado via login)
-- o DONO dele. Encontra o usuário pelo e-mail — então faça login no app ao
-- menos uma vez ANTES de rodar isto (para a linha existir em auth.users).
--
-- >>> EDITE as 4 variáveis abaixo <<<
do $$
declare
  v_nome     text := 'Studio Bem-Estar';          -- nome do estabelecimento
  v_slug     text := 'studio-bem-estar';           -- vira /studio-bem-estar na URL
  v_email    text := 'eliteprimestoreselite@gmail.com'; -- SEU e-mail de dono
  v_vertical text := 'salao';                      -- 'salao' | 'clinica' | 'outro'
  v_tz       text := 'America/Sao_Paulo';
  v_user     uuid;
  v_tenant   uuid;
begin
  select id into v_user from auth.users where email = v_email;
  if v_user is null then
    raise exception 'Usuário % não encontrado. Faça login no app uma vez antes de rodar este script.', v_email;
  end if;

  insert into tenants (nome, slug, vertical, timezone)
  values (v_nome, v_slug, v_vertical, v_tz)
  on conflict (slug) do update set nome = excluded.nome
  returning id into v_tenant;

  insert into profiles (id, nome)
  values (v_user, split_part(v_email, '@', 1))
  on conflict (id) do nothing;

  insert into memberships (user_id, tenant_id, role)
  values (v_user, v_tenant, 'owner')
  on conflict (user_id, tenant_id) do update set role = 'owner';

  raise notice 'OK: % é owner do tenant % (/%).', v_email, v_nome, v_slug;
end $$;
