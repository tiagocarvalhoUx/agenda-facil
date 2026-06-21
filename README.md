# Agenda SaaS — Sistema de Agendamento Multi-Tenant

SaaS de agendamento online para clínicas, salões e consultórios. Multi-tenant
com isolamento forçado por RLS, fluxo público de agendamento sem conta, painel
para dono/profissional e lembretes automáticos.

Construído seguindo `prompt-agendamento-saas.md` (engenharia/segurança) e
`ADENDO-UIUX-Agendamento-SaaS.md` (UI/UX). **Segurança e isolamento de dados
são requisito de cada arquivo, não um "depois".**

## Stack

- **Frontend:** Vue 3 + Vite + TypeScript + Tailwind CSS + Pinia + Vue Router
- **Backend/DB:** Supabase (PostgreSQL + Auth + Edge Functions)
- **Auth:** Magic Link (dono/profissional). Cliente final agenda sem conta.
- **Lembretes:** Edge Function agendada + provedor abstraído (Resend no MVP).

## Modelo de isolamento (resumo)

- Toda tabela de negócio tem `tenant_id` e **RLS habilitado + FORÇADO**; default = negar.
- `tenant_id` **nunca** vem do cliente: é derivado de `auth.uid()` via `memberships`
  pela função `current_tenant_ids()` (`SECURITY DEFINER`, `STABLE`).
- **Owner** vê o tenant inteiro; **staff** só a própria agenda (ligação por
  `professionals.user_id`).
- Cliente final não acessa tabelas — só as RPCs `get_public_establishment`,
  `get_available_slots` e `create_booking` (`SECURITY DEFINER`, com validação e
  rate limiting). Nenhum PII de terceiros é exposto.
- `service_role` **só** em Edge Functions/servidor. Frontend usa apenas `anon`.

## Pré-requisitos

- Node 18+ e npm
- [Supabase CLI](https://supabase.com/docs/guides/cli) e Docker (para stack local)

## Setup

```bash
# 1. Dependências
npm install

# 2. Variáveis de ambiente
cp .env.example .env   # preencha VITE_SUPABASE_URL e VITE_SUPABASE_ANON_KEY

# 3. Banco local (sobe Postgres + aplica migrations + seed)
npm run db:start
npm run db:reset       # aplica supabase/migrations/* + supabase/seed.sql

# 4. App
npm run dev            # http://localhost:5173
```

A página pública do tenant de exemplo: `http://localhost:5173/studio-bem-estar`.

## Migrations (versionadas — nada manual no painel)

Em `supabase/migrations/`, na ordem:

| Arquivo | Conteúdo |
|---|---|
| `…_extensions.sql` | `pgcrypto`, `btree_gist` |
| `…_schema.sql` | tabelas, enums, **EXCLUDE anti-overbooking**, soft delete |
| `…_helpers.sql` | `current_tenant_ids`, `is_tenant_owner`, `current_professional_id` |
| `…_rls.sql` | RLS habilitado + **forçado**, policies por operação/role |
| `…_audit.sql` | trigger de auditoria (appointments/customers/services) |
| `…_public_rpcs.sql` | RPCs públicas + rate limiting |
| `…_lgpd.sql` | `anonimizar_cliente` (direito ao esquecimento) |
| `…_reminders.sql` | enfileiramento idempotente de lembretes (24h/2h) |
| `…_v2_schema.sql` | buffer/depósito/categoria em serviços, avatar/bio, `booking_policy`, notas/tags/`no_show_count`, `manage_token`; tabelas `professional_services`, `time_blocks`, `waitlist` |
| `…_v2_rls.sql` | RLS forçado + grants das novas tabelas |
| `…_v2_rpcs.sql` | `get_available_slots`/`create_booking` v2 (buffer + bloqueios + vínculo + política), `manage_booking`, `get_booking_by_token`, `join_waitlist` |
| `…_v2_noshow.sql` | trigger de reputação (`no_show_count`) + reenfileiramento de lembretes ao remarcar |
| `…_v2_dashboard.sql` | `get_owner_dashboard` (métricas, só owner) |

## Novidades da v2 (`prompt-agenda-facil-v2.md`)

- **Auto-gerenciamento do cliente sem login:** rota pública `/b/:token` (remarcar/
  cancelar via `manage_token` assinado, respeitando a janela da `booking_policy`).
- **Disponibilidade real:** slots respeitam **buffer**, **bloqueios/folgas**
  (`time_blocks`) e o **vínculo serviço↔profissional** (`professional_services`).
- **White-label por tenant:** logo + cor (com validação de contraste AA) e
  `booking_policy` (auto-confirmar, antecedência mín/máx, janela de cancelamento)
  em Configurações.
- **Onboarding wizard:** primeiro acesso do dono é redirecionado para
  `/app/onboarding` (marca → serviço → equipe+horários → link público).
- **Dashboard do dono** (`/app/dashboard`): ocupação do dia, faturamento
  estimado, **taxa de no-show**, serviços mais agendados.
- **Anti no-show:** `no_show_count` mantido por trigger e destacado na ficha do
  cliente; depósito opcional por serviço (`exige_deposito`/`deposito_valor`).
- **Lista de espera** no funil público quando não há horário (`join_waitlist`).
- **Quick-create** na agenda do dono e **bloqueios/folgas** em `/app/bloqueios`.

> **Validação local (Windows):** as migrations v2 aplicam limpas no Postgres do
> stack (`Applying migration …_v2_*.sql ✓`). Em algumas máquinas Windows os
> containers `storage`/`realtime`/`pg_meta` falham no health check do
> `supabase start` (limitação do ambiente, não do schema) — nesses casos use o
> projeto remoto via `supabase link` + `db push`, ou rode em WSL2.

```bash
npm run db:diff        # gera nova migration a partir de mudanças locais
npm run db:push        # aplica migrations no projeto remoto (após supabase link)
npm run gen:types      # regenera src/types/database.types.ts
```

## Lembretes (Edge Function)

```bash
# Segredos (NUNCA no frontend nem commitados)
supabase secrets set RESEND_API_KEY=re_xxx
supabase secrets set REMINDER_FROM_EMAIL="lembretes@seu-dominio.com"
supabase secrets set CRON_SECRET="$(openssl rand -hex 32)"

supabase functions deploy send-reminders
```

Agendar via `pg_cron` + `pg_net` (a cada 5 min), no SQL editor do projeto:

```sql
select cron.schedule(
  'send-reminders', '*/5 * * * *',
  $$ select net.http_post(
       url := 'https://SEU-PROJ.supabase.co/functions/v1/send-reminders',
       headers := jsonb_build_object('Authorization', 'Bearer SEU_CRON_SECRET')
     ); $$
);
```

A função é **idempotente**: marca `status='enviado'` antes de disparar, então
nunca reenvia a mesma janela.

## Integrações de calendário

- **Add-to-calendar (.ics):** já funciona na confirmação pública (`src/lib/ics.ts`)
  — o cliente baixa o evento e adiciona ao calendário dele sem login.
- **Google Calendar (sync por profissional):** ponto de extensão **opcional/
  plugável** previsto no prompt, **ainda não conectado**. Requer OAuth do Google
  (consent screen + tokens por profissional) e uma Edge Function que reflita
  `appointments` ↔ eventos. A camada de provedor de notificações
  (`functions/send-reminders/providers.ts`) é o molde para esse seam; a
  implementação completa depende de credenciais Google e não foi incluída para
  não enviar OAuth não testável.

## Checklist de aceite

**Segurança (PROMPT §8)** e **Design (ADENDO §21)** estão mapeados nos
comentários de cada migration/componente. Testes de isolamento recomendados:
logar como tenant A e confirmar via SQL/API que linhas do tenant B são
inacessíveis; verificar que a página pública não expõe PII; tentar dois
agendamentos sobrepostos para o mesmo profissional (deve falhar).

## Estrutura

```
src/
  components/   ui · public · agenda · feedback  (componentes com estados)
  composables/  useToast
  lib/          supabase · accent (contraste AA) · format (pt-BR) · ics · errors
  stores/       auth (contexto de tenant/role)
  views/        public/ · auth/ · app/
supabase/
  migrations/   schema + RLS + RPCs + triggers (versionado)
  functions/    send-reminders (provedor plugável)
  seed.sql      tenant de exemplo
```
