-- =====================================================================
-- 0002 — Schema de negócio (multi-tenant)
-- Toda tabela de negócio carrega tenant_id uuid not null (PROMPT §4/§5.1).
-- Integridade (§5.4): EXCLUDE anti-overbooking, soft delete em dados de
-- cliente, FKs coerentes, validação de input via CHECK.
-- =====================================================================

-- ----- Tipos -----
create type membership_role as enum ('owner', 'staff');
create type appointment_status as enum ('agendado', 'confirmado', 'cancelado', 'concluido', 'no_show');
create type reminder_channel as enum ('email', 'whatsapp', 'sms');
create type reminder_status as enum ('pendente', 'enviado', 'falhou', 'cancelado');

-- ----- tenants -----
create table tenants (
  id          uuid primary key default gen_random_uuid(),
  nome        text not null check (length(trim(nome)) > 0),
  slug        text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  plano       text not null default 'trial',
  status      text not null default 'ativo' check (status in ('ativo', 'suspenso', 'cancelado')),
  -- Acento white-label por tenant (§13.1). Hex validado; contraste validado na app.
  accent_color text check (accent_color ~* '^#[0-9a-f]{6}$'),
  vertical    text check (vertical in ('clinica', 'salao', 'outro')),
  created_at  timestamptz not null default now()
);

-- ----- profiles (espelha auth.users) -----
create table profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  nome       text,
  telefone   text,
  created_at timestamptz not null default now()
);

-- ----- memberships (vincula usuário ao tenant + role) -----
create table memberships (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  tenant_id  uuid not null references tenants (id) on delete cascade,
  role       membership_role not null,
  created_at timestamptz not null default now(),
  unique (user_id, tenant_id)
);
create index idx_memberships_user on memberships (user_id);
create index idx_memberships_tenant on memberships (tenant_id);

-- ----- professionals -----
-- user_id liga o login (staff) à linha do profissional para o recorte de RLS
-- "staff só vê a própria agenda". Pode ser null (profissional sem login).
create table professionals (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references tenants (id) on delete cascade,
  user_id    uuid references auth.users (id) on delete set null,
  nome       text not null check (length(trim(nome)) > 0),
  ativo      boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  unique (tenant_id, user_id)
);
create index idx_professionals_tenant on professionals (tenant_id);

-- ----- services -----
create table services (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references tenants (id) on delete cascade,
  nome        text not null check (length(trim(nome)) > 0),
  duracao_min integer not null check (duracao_min > 0 and duracao_min <= 1440),
  preco       numeric(10, 2) not null default 0 check (preco >= 0),
  ativo       boolean not null default true,
  deleted_at  timestamptz,
  created_at  timestamptz not null default now()
);
create index idx_services_tenant on services (tenant_id);

-- ----- working_hours -----
create table working_hours (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references tenants (id) on delete cascade,
  professional_id uuid not null references professionals (id) on delete cascade,
  weekday         smallint not null check (weekday between 0 and 6), -- 0 = domingo
  hora_inicio     time not null,
  hora_fim        time not null,
  check (hora_fim > hora_inicio)
);
create index idx_working_hours_prof on working_hours (professional_id, weekday);

-- ----- customers (PII — soft delete + consentimento LGPD) -----
create table customers (
  id                   uuid primary key default gen_random_uuid(),
  tenant_id            uuid not null references tenants (id) on delete cascade,
  nome                 text not null check (length(trim(nome)) > 0),
  telefone             text not null check (telefone ~ '^\+?[0-9]{10,15}$'),
  email                text check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  consentimento_lgpd_at timestamptz,
  anonimizado_at       timestamptz,
  deleted_at           timestamptz,
  created_at           timestamptz not null default now(),
  -- dedupe por telefone dentro do tenant (parcial: ignora removidos)
  unique (tenant_id, telefone)
);
create index idx_customers_tenant on customers (tenant_id);

-- ----- appointments -----
create table appointments (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references tenants (id) on delete cascade,
  professional_id uuid not null references professionals (id) on delete restrict,
  service_id      uuid not null references services (id) on delete restrict,
  customer_id     uuid not null references customers (id) on delete restrict,
  inicio_at       timestamptz not null,
  fim_at          timestamptz not null,
  status          appointment_status not null default 'agendado',
  origem          text not null default 'painel' check (origem in ('painel', 'publico')),
  observacao      text,
  created_by      uuid references auth.users (id) on delete set null,
  deleted_at      timestamptz,
  created_at      timestamptz not null default now(),
  check (fim_at > inicio_at)
);
create index idx_appointments_tenant_inicio on appointments (tenant_id, inicio_at);
create index idx_appointments_prof_inicio on appointments (professional_id, inicio_at);

-- Anti-overbooking no nível do banco (§5.4): impede dois agendamentos
-- ativos sobrepostos para o MESMO profissional. Cancelados/removidos não contam.
alter table appointments
  add constraint appointments_no_overbooking
  exclude using gist (
    professional_id with =,
    tstzrange(inicio_at, fim_at) with &&
  )
  where (status <> 'cancelado' and deleted_at is null);

-- ----- reminders (idempotência por janela/canal) -----
create table reminders (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references tenants (id) on delete cascade,
  appointment_id uuid not null references appointments (id) on delete cascade,
  canal          reminder_channel not null default 'email',
  agendado_para  timestamptz not null,
  enviado_at     timestamptz,
  status         reminder_status not null default 'pendente',
  tentativas     smallint not null default 0,
  erro           text,
  -- nunca dois lembretes para a mesma janela/canal do mesmo agendamento
  unique (appointment_id, canal, agendado_para)
);
create index idx_reminders_due on reminders (agendado_para) where status = 'pendente';

-- ----- audit_log -----
create table audit_log (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null,
  user_id     uuid,
  acao        text not null,        -- INSERT | UPDATE | DELETE
  tabela      text not null,
  registro_id uuid,
  payload     jsonb,
  created_at  timestamptz not null default now()
);
create index idx_audit_tenant on audit_log (tenant_id, created_at desc);

-- ----- booking_attempts (rate limiting do fluxo público — §5.3) -----
create table booking_attempts (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references tenants (id) on delete cascade,
  ip         text,
  telefone   text,
  sucesso    boolean not null default false,
  created_at timestamptz not null default now()
);
create index idx_booking_attempts_window on booking_attempts (tenant_id, created_at desc);
