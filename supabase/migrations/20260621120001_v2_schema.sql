-- =====================================================================
-- 0010 (v2) — Evolução do schema para a v2 do produto
-- Aditiva e idempotente (add column if not exists / create table if not
-- exists). NÃO edita migrations já aplicadas. Cobre PROMPT v2 §4:
--   • buffer entre atendimentos, depósito anti no-show
--   • vínculo serviço↔profissional (professional_services)
--   • bloqueios/folgas/feriados (time_blocks)
--   • auto-gerenciamento do cliente (appointments.manage_token)
--   • reputação do cliente (no_show_count), notas e tags
--   • política de agendamento por tenant (booking_policy jsonb)
--   • white-label (brand_logo_url; accent_color já existe como cor da marca)
--   • lista de espera (waitlist)
-- =====================================================================

-- ----- tenants: marca + política de agendamento -----
-- accent_color (v1) é a cor primária da marca. Adicionamos logo e política.
alter table tenants add column if not exists brand_logo_url text;
alter table tenants add column if not exists booking_policy jsonb not null default jsonb_build_object(
  'auto_confirmar', true,        -- agendamento público já entra como 'confirmado'?
  'antecedencia_min_horas', 1,   -- precisa marcar com no mínimo X h de folga
  'antecedencia_max_dias', 60,   -- não deixa marcar além de X dias
  'cancelamento_ate_horas', 12   -- cliente pode cancelar/remarcar até X h antes
);

-- ----- professionals: perfil público (avatar + bio) -----
alter table professionals add column if not exists avatar_url text;
alter table professionals add column if not exists bio text;

-- ----- services: categoria, buffer, depósito -----
-- buffer_min: tempo de preparo/limpeza somado ao slot. fim_at do appointment
-- passa a representar o BLOCO ocupado (duracao + buffer); o fim "visível"
-- do atendimento é inicio + duracao_min.
alter table services add column if not exists categoria text;
alter table services add column if not exists buffer_min integer not null default 0
  check (buffer_min >= 0 and buffer_min <= 240);
alter table services add column if not exists exige_deposito boolean not null default false;
alter table services add column if not exists deposito_valor numeric(10, 2) not null default 0
  check (deposito_valor >= 0);

-- ----- customers: reputação, notas e tags -----
alter table customers add column if not exists notas text;
alter table customers add column if not exists tags text[] not null default '{}';
alter table customers add column if not exists no_show_count integer not null default 0
  check (no_show_count >= 0);

-- ----- appointments: token de auto-gerenciamento + estado do depósito -----
-- manage_token: 128 bits aleatórios (não derivável/adivinhável). É um bearer
-- token consultado server-side por manage_booking — sem login, sem PII de
-- terceiros. unique para lookup direto.
alter table appointments add column if not exists manage_token uuid not null default gen_random_uuid();
alter table appointments add column if not exists deposito_status text not null default 'nao_exigido'
  check (deposito_status in ('nao_exigido', 'pendente', 'pago', 'estornado'));
create unique index if not exists idx_appointments_manage_token on appointments (manage_token);

-- =====================================================================
-- Novas tabelas
-- =====================================================================

-- ----- professional_services: quais profissionais fazem quais serviços -----
create table if not exists professional_services (
  tenant_id       uuid not null references tenants (id) on delete cascade,
  professional_id uuid not null references professionals (id) on delete cascade,
  service_id      uuid not null references services (id) on delete cascade,
  created_at      timestamptz not null default now(),
  primary key (professional_id, service_id)
);
create index if not exists idx_prof_services_tenant on professional_services (tenant_id);
create index if not exists idx_prof_services_service on professional_services (service_id);

-- ----- time_blocks: folgas, almoço, feriados, bloqueios pontuais -----
create table if not exists time_blocks (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references tenants (id) on delete cascade,
  professional_id uuid not null references professionals (id) on delete cascade,
  inicio_at       timestamptz not null,
  fim_at          timestamptz not null,
  motivo          text,
  created_at      timestamptz not null default now(),
  check (fim_at > inicio_at)
);
create index if not exists idx_time_blocks_prof on time_blocks (professional_id, inicio_at);
create index if not exists idx_time_blocks_tenant on time_blocks (tenant_id, inicio_at);

-- ----- waitlist: fila de espera para slots cheios -----
create table if not exists waitlist (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references tenants (id) on delete cascade,
  service_id      uuid not null references services (id) on delete cascade,
  professional_id uuid references professionals (id) on delete set null, -- null = sem preferência
  customer_nome   text not null check (length(trim(customer_nome)) > 0),
  customer_contato text not null check (length(trim(customer_contato)) > 0),
  janela_desejada jsonb,            -- {de, ate} ou descrição livre da preferência
  status          text not null default 'aguardando'
    check (status in ('aguardando', 'notificado', 'convertido', 'cancelado')),
  notificado_at   timestamptz,
  created_at      timestamptz not null default now()
);
create index if not exists idx_waitlist_tenant on waitlist (tenant_id, created_at desc);
create index if not exists idx_waitlist_fila on waitlist (service_id, status, created_at);

-- ----- índice de performance da query de range da agenda (§9) -----
create index if not exists idx_appointments_range
  on appointments (tenant_id, professional_id, inicio_at);
