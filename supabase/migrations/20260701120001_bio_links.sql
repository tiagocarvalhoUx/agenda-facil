-- =====================================================================
-- 0701 — Meus Links Públicos (link-in-bio)
-- Uma página de links por tenant, com handle global único, tema de cores,
-- perfil e uma lista ordenada de links (jsonb). Leitura pública SÓ via RPC
-- SECURITY DEFINER (nada de acesso direto por anon). Escrita: apenas o dono
-- do tenant. Imagens (avatar/banner) ficam no bucket público 'bio'.
-- Idempotente (create ... if not exists / drop policy if exists) para poder
-- ser aplicada tanto pelo `db push` quanto direto pela Management API.
-- =====================================================================

create table if not exists bio_pages (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null unique references tenants (id) on delete cascade,
  username      text not null,
  display_name  text not null default '',
  bio           text not null default '',
  theme         text not null default 'creme',
  avatar_url    text,
  links         jsonb not null default '[]'::jsonb,
  published     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint bio_username_format check (username ~ '^[a-z0-9][a-z0-9._-]{1,38}$'),
  constraint bio_theme_valid check (theme in ('creme','marrom','azul','preto_ouro','rosa')),
  constraint bio_len_display check (char_length(display_name) <= 40),
  constraint bio_len_bio check (char_length(bio) <= 80)
);

-- Handle único de forma global e case-insensitive.
create unique index if not exists bio_pages_username_key on bio_pages (lower(username));

-- updated_at automático.
create or replace function fn_bio_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists trg_bio_touch on bio_pages;
create trigger trg_bio_touch before update on bio_pages
  for each row execute function fn_bio_touch();

-- ----- RLS: leitura/escrita só do próprio tenant; escrita só do dono -----
alter table bio_pages enable row level security;
alter table bio_pages force row level security;

drop policy if exists bio_pages_select on bio_pages;
create policy bio_pages_select on bio_pages for select to authenticated
  using (tenant_id in (select current_tenant_ids()));

drop policy if exists bio_pages_insert on bio_pages;
create policy bio_pages_insert on bio_pages for insert to authenticated
  with check (tenant_id in (select current_tenant_ids()) and is_tenant_owner(tenant_id));

drop policy if exists bio_pages_update on bio_pages;
create policy bio_pages_update on bio_pages for update to authenticated
  using (tenant_id in (select current_tenant_ids()) and is_tenant_owner(tenant_id))
  with check (tenant_id in (select current_tenant_ids()) and is_tenant_owner(tenant_id));

drop policy if exists bio_pages_delete on bio_pages;
create policy bio_pages_delete on bio_pages for delete to authenticated
  using (tenant_id in (select current_tenant_ids()) and is_tenant_owner(tenant_id));

-- ---------------------------------------------------------------------
-- get_public_bio — dados públicos da página de links por handle. Só
-- páginas publicadas. Não expõe tenant_id nem timestamps.
-- ---------------------------------------------------------------------
create or replace function get_public_bio(p_username text)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'username', b.username,
    'display_name', b.display_name,
    'bio', b.bio,
    'theme', b.theme,
    'avatar_url', b.avatar_url,
    'links', b.links
  )
  from bio_pages b
  where lower(b.username) = lower(p_username) and b.published = true;
$$;

-- Disponibilidade do handle (para feedback inline no editor). Ignora a própria
-- página do tenant que está consultando.
create or replace function bio_username_available(p_username text, p_tenant uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select not exists (
    select 1 from bio_pages
    where lower(username) = lower(p_username) and tenant_id <> p_tenant
  );
$$;

revoke all on function get_public_bio(text) from public;
revoke all on function bio_username_available(text, uuid) from public;
grant execute on function get_public_bio(text) to anon, authenticated;
grant execute on function bio_username_available(text, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Storage: bucket público 'bio' para avatar e banners. Leitura pública;
-- escrita só do dono, e apenas dentro da pasta do próprio tenant
-- (primeiro segmento do path = tenant_id).
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('bio', 'bio', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
  set public = true,
      file_size_limit = 5242880,
      allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "bio_public_read" on storage.objects;
create policy "bio_public_read" on storage.objects for select to public
  using (bucket_id = 'bio');

drop policy if exists "bio_owner_insert" on storage.objects;
create policy "bio_owner_insert" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'bio'
    and coalesce((storage.foldername(name))[1], '') <> ''
    and (storage.foldername(name))[1] in (select current_tenant_ids()::text)
  );

drop policy if exists "bio_owner_update" on storage.objects;
create policy "bio_owner_update" on storage.objects for update to authenticated
  using (
    bucket_id = 'bio'
    and (storage.foldername(name))[1] in (select current_tenant_ids()::text)
  );

drop policy if exists "bio_owner_delete" on storage.objects;
create policy "bio_owner_delete" on storage.objects for delete to authenticated
  using (
    bucket_id = 'bio'
    and (storage.foldername(name))[1] in (select current_tenant_ids()::text)
  );
