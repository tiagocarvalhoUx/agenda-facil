-- =====================================================================
-- 0010 — Notificações de novo agendamento (Web Push + Realtime)
-- Quando um cliente agenda pelo link público, o DONO recebe:
--   • Push nativo (mesmo com o app fechado) — via Edge Function notify-booking.
--   • Realtime in-app (toast/som/badge) — assinando INSERT em appointments.
-- Esta migration cria a tabela de inscrições push, habilita o pg_net para o
-- trigger chamar a Edge Function, publica appointments no Realtime e cria o
-- trigger de disparo. O segredo/URL da function ficam numa tabela privada
-- (singleton) preenchida uma única vez por ambiente — nunca no código.
-- =====================================================================

-- pg_net: permite ao banco fazer HTTP (chamar a Edge Function no INSERT).
create extension if not exists pg_net with schema extensions;

-- ----- push_subscriptions -----
-- Uma linha por dispositivo/navegador inscrito. endpoint é único (a mesma
-- inscrição não duplica). Ligada ao usuário (dono/staff) e ao tenant.
create table push_subscriptions (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references tenants (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  endpoint    text not null unique,
  p256dh      text not null,
  auth        text not null,
  user_agent  text,
  created_at  timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index idx_push_subs_tenant on push_subscriptions (tenant_id);
create index idx_push_subs_user on push_subscriptions (user_id);

-- RLS: cada usuário gerencia apenas as PRÓPRIAS inscrições, dentro do tenant
-- a que pertence. A Edge Function lê via service_role (ignora RLS).
alter table push_subscriptions enable row level security;
alter table push_subscriptions force row level security;

create policy push_subs_select on push_subscriptions for select to authenticated
  using (user_id = auth.uid());
create policy push_subs_insert on push_subscriptions for insert to authenticated
  with check (user_id = auth.uid() and tenant_id in (select current_tenant_ids()));
create policy push_subs_update on push_subscriptions for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy push_subs_delete on push_subscriptions for delete to authenticated
  using (user_id = auth.uid());

grant select, insert, update, delete on push_subscriptions to authenticated;

-- ----- Realtime: publica appointments para o painel assinar INSERT/UPDATE -----
-- A RLS continua valendo no Realtime: cada dono só recebe eventos do seu tenant.
alter publication supabase_realtime add table appointments;

-- ----- Config privada da Edge Function (singleton) -----
-- function_url + secret usados pelo trigger. NÃO exposto a anon/authenticated.
-- Preencher uma vez por ambiente (ver README). Sem linha = trigger é no-op
-- (não quebra dev local sem function publicada).
create table private_notify_config (
  id           boolean primary key default true check (id),
  function_url text not null,
  secret       text not null
);
revoke all on private_notify_config from anon, authenticated;

-- ----- Trigger: dispara o push ao criar agendamento público -----
create or replace function fn_notify_new_booking()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  cfg private_notify_config;
begin
  -- Só agendamentos vindos do link público (o dono já sabe dos que ele cria).
  if new.origem <> 'publico' then
    return new;
  end if;

  select * into cfg from private_notify_config where id = true;
  if cfg.function_url is null then
    return new; -- ambiente sem push configurado: nada a fazer
  end if;

  perform net.http_post(
    url     := cfg.function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || cfg.secret
    ),
    body    := jsonb_build_object('appointment_id', new.id),
    timeout_milliseconds := 5000
  );
  return new;
end;
$$;

create trigger trg_notify_new_booking
  after insert on appointments
  for each row execute function fn_notify_new_booking();
