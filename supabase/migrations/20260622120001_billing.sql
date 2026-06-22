-- =====================================================================
-- 0015 (v2) — Billing / pagamento recorrente (assinatura do SaaS)
-- Estado da assinatura por tenant + log de webhooks do provedor (Asaas no
-- MVP, plugável). Escrita SÓ pelo servidor (Edge Function com service_role);
-- o dono apenas LÊ o próprio billing. Nada de chave/segredo no banco.
-- =====================================================================

create table if not exists tenant_billing (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null unique references tenants (id) on delete cascade,
  provider           text not null default 'asaas',
  customer_id        text,         -- id do cliente no provedor
  subscription_id    text,         -- id da assinatura no provedor
  plano              text,
  valor              numeric(10, 2),
  ciclo              text,         -- MONTHLY | YEARLY | ...
  billing_type       text,         -- PIX | CREDIT_CARD | BOLETO
  status             text not null default 'inativo'
    check (status in ('inativo', 'trial', 'ativo', 'atrasado', 'cancelado')),
  proximo_vencimento date,
  updated_at         timestamptz not null default now(),
  created_at         timestamptz not null default now()
);
create index if not exists idx_tenant_billing_tenant on tenant_billing (tenant_id);

-- Log de eventos do provedor (idempotência + auditoria). Só o servidor acessa.
create table if not exists billing_events (
  id          uuid primary key default gen_random_uuid(),
  provider    text not null default 'asaas',
  event       text not null,
  external_id text,                -- id do pagamento/assinatura no provedor
  payload     jsonb,
  created_at  timestamptz not null default now()
);
create index if not exists idx_billing_events_external on billing_events (external_id);

-- Rastreio do depósito anti no-show no provedor (cobrança avulsa Pix).
alter table appointments add column if not exists deposito_charge_id text;

-- ----- RLS: dono LÊ o próprio billing; escrita só via service_role -----
alter table tenant_billing enable row level security;
alter table tenant_billing force row level security;
alter table billing_events enable row level security;
alter table billing_events force row level security;

create policy tenant_billing_select on tenant_billing for select to authenticated
  using (is_tenant_owner(tenant_id));
-- sem policies de insert/update/delete: apenas o service_role (que ignora RLS)
-- nas Edge Functions grava aqui. Default = negar para anon/authenticated.

-- billing_events: nenhuma policy → ninguém lê/escreve via API; só service_role.

grant select on tenant_billing to authenticated;
