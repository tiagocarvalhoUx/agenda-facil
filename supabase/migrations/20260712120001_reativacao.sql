-- =====================================================================
-- 0712 — Reativação de Clientes por IA (Fase 1)
-- Campanhas de reativação: o dono segmenta clientes inativos (sem visita
-- há N dias e sem agendamento futuro), a IA redige a mensagem (Edge
-- Function `ai-campaign`) e o disparo é MANUAL via link wa.me — sem API
-- oficial e sem custo. As tabelas registram quem recebeu e permitem medir
-- conversão (cliente com agendamento criado APÓS o envio = reativado).
-- Escrita: apenas o dono do tenant. Idempotente (ver 0701) para poder ser
-- aplicada tanto pelo `db push` quanto direto pela Management API.
-- =====================================================================

create table if not exists campaigns (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references tenants (id) on delete cascade,
  nome              text not null,
  objetivo          text not null default '',
  mensagem          text not null,
  dias_inatividade  int  not null default 90 check (dias_inatividade between 1 and 3650),
  created_by        uuid,
  created_at        timestamptz not null default now(),
  constraint campaigns_nome_len check (char_length(nome) <= 80),
  constraint campaigns_msg_len check (char_length(mensagem) <= 2000)
);

create table if not exists campaign_recipients (
  id           uuid primary key default gen_random_uuid(),
  campaign_id  uuid not null references campaigns (id) on delete cascade,
  tenant_id    uuid not null references tenants (id) on delete cascade,
  customer_id  uuid not null references customers (id) on delete cascade,
  enviado_at   timestamptz,
  created_at   timestamptz not null default now(),
  unique (campaign_id, customer_id)
);

create index if not exists campaigns_tenant_idx on campaigns (tenant_id, created_at desc);
create index if not exists campaign_recipients_campaign_idx on campaign_recipients (campaign_id);

-- ----- RLS: leitura do tenant; escrita só do dono (igual bio_pages) -----
alter table campaigns enable row level security;
alter table campaigns force row level security;
alter table campaign_recipients enable row level security;
alter table campaign_recipients force row level security;

drop policy if exists campaigns_select on campaigns;
create policy campaigns_select on campaigns for select to authenticated
  using (tenant_id in (select current_tenant_ids()));

drop policy if exists campaigns_insert on campaigns;
create policy campaigns_insert on campaigns for insert to authenticated
  with check (tenant_id in (select current_tenant_ids()) and is_tenant_owner(tenant_id));

drop policy if exists campaigns_update on campaigns;
create policy campaigns_update on campaigns for update to authenticated
  using (tenant_id in (select current_tenant_ids()) and is_tenant_owner(tenant_id))
  with check (tenant_id in (select current_tenant_ids()) and is_tenant_owner(tenant_id));

drop policy if exists campaigns_delete on campaigns;
create policy campaigns_delete on campaigns for delete to authenticated
  using (tenant_id in (select current_tenant_ids()) and is_tenant_owner(tenant_id));

drop policy if exists campaign_recipients_select on campaign_recipients;
create policy campaign_recipients_select on campaign_recipients for select to authenticated
  using (tenant_id in (select current_tenant_ids()));

drop policy if exists campaign_recipients_insert on campaign_recipients;
create policy campaign_recipients_insert on campaign_recipients for insert to authenticated
  with check (tenant_id in (select current_tenant_ids()) and is_tenant_owner(tenant_id));

drop policy if exists campaign_recipients_update on campaign_recipients;
create policy campaign_recipients_update on campaign_recipients for update to authenticated
  using (tenant_id in (select current_tenant_ids()) and is_tenant_owner(tenant_id))
  with check (tenant_id in (select current_tenant_ids()) and is_tenant_owner(tenant_id));

drop policy if exists campaign_recipients_delete on campaign_recipients;
create policy campaign_recipients_delete on campaign_recipients for delete to authenticated
  using (tenant_id in (select current_tenant_ids()) and is_tenant_owner(tenant_id));

-- Privilégio de tabela (a RLS aplica o recorte; ver 0009).
grant select, insert, update, delete on campaigns, campaign_recipients to authenticated;

-- ---------------------------------------------------------------------
-- reativacao_inactive_customers — clientes "parados" do tenant: última
-- visita (não cancelada) há mais de p_dias e NENHUM agendamento futuro.
-- Exclui deletados/anonimizados e devolve se há consentimento LGPD para
-- o painel sinalizar. SECURITY DEFINER com guarda de membership.
-- ---------------------------------------------------------------------
create or replace function reativacao_inactive_customers(p_tenant uuid, p_dias int)
returns table (
  customer_id uuid,
  nome text,
  telefone text,
  ultima_visita timestamptz,
  total_visitas int,
  consentiu boolean
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select c.id,
         c.nome,
         c.telefone,
         max(a.inicio_at) as ultima_visita,
         count(a.id)::int as total_visitas,
         (c.consentimento_lgpd_at is not null) as consentiu
  from customers c
  join appointments a
    on a.customer_id = c.id
   and a.tenant_id = c.tenant_id
   and a.deleted_at is null
   and a.status in ('agendado', 'confirmado', 'concluido')
   and a.inicio_at <= now()
  where c.tenant_id = p_tenant
    and p_tenant in (select current_tenant_ids())
    and c.deleted_at is null
    and c.anonimizado_at is null
  group by c.id
  having max(a.inicio_at) < now() - make_interval(days => p_dias)
     and not exists (
       select 1 from appointments f
       where f.customer_id = c.id
         and f.tenant_id = c.tenant_id
         and f.deleted_at is null
         and f.status <> 'cancelado'
         and f.inicio_at > now()
     )
  order by max(a.inicio_at) asc
$$;

-- ---------------------------------------------------------------------
-- reativacao_campaign_stats — números por campanha do tenant:
-- destinatários, enviados e convertidos (agendamento criado após o envio,
-- não cancelado). É o "quantos clientes a campanha reativou".
-- ---------------------------------------------------------------------
create or replace function reativacao_campaign_stats(p_tenant uuid)
returns table (
  campaign_id uuid,
  total int,
  enviados int,
  convertidos int
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select cp.id,
         count(r.id)::int as total,
         count(r.enviado_at)::int as enviados,
         count(r.id) filter (
           where r.enviado_at is not null and exists (
             select 1 from appointments a
             where a.customer_id = r.customer_id
               and a.tenant_id = cp.tenant_id
               and a.deleted_at is null
               and a.status <> 'cancelado'
               and a.created_at > r.enviado_at
           )
         )::int as convertidos
  from campaigns cp
  left join campaign_recipients r on r.campaign_id = cp.id
  where cp.tenant_id = p_tenant
    and p_tenant in (select current_tenant_ids())
  group by cp.id
$$;

revoke all on function reativacao_inactive_customers(uuid, int) from public;
revoke all on function reativacao_campaign_stats(uuid) from public;
grant execute on function reativacao_inactive_customers(uuid, int) to authenticated;
grant execute on function reativacao_campaign_stats(uuid) to authenticated;
