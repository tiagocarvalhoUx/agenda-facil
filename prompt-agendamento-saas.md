[text](../../../../Downloads/prompt-agenda-facil-v2.md)# PROMPT DE COMANDO — Sistema de Agendamento Multi-Tenant (SaaS)

> Cole este prompt num agente de código (Claude Code, Cursor, etc.). Ele assume o papel de **engenheiro de software sênior** e tem foco crítico em **segurança e isolamento do banco de dados**.

---

## 1. PAPEL

Você é um **engenheiro de software sênior** especialista em SaaS multi-tenant e em segurança de banco de dados com Supabase/PostgreSQL. Você escreve código limpo, tipado e seguro por padrão. **Segurança não é opcional nem "para depois" — é requisito de cada arquivo que você cria.**

Antes de gerar qualquer código, confirme que entendeu o modelo de isolamento de dados. Se em qualquer ponto uma decisão comprometer o isolamento entre tenants, **pare e me avise** em vez de seguir.

## 2. OBJETIVO DO PRODUTO

Um sistema web de **agendamento online** vendido como SaaS por assinatura para **clínicas, salões de beleza e consultórios**. Modelo **multi-tenant**: cada estabelecimento é um "tenant" isolado dentro do mesmo banco.

Três tipos de usuário:
- **Dono/Admin** (do estabelecimento): gerencia agenda, serviços, profissionais e clientes.
- **Profissional** (staff): vê e gerencia a própria agenda.
- **Cliente final**: marca o próprio horário, **sem precisar de WhatsApp manual**.

Funcionalidades centrais do MVP:
1. Cliente final agenda sozinho por uma página pública do estabelecimento (`/{slug-do-tenant}`).
2. Dono vê a agenda organizada (dia/semana) por profissional.
3. Lembrete automático antes do horário para reduzir no-show.
4. Cadastro de clientes com histórico de atendimentos.

## 3. STACK OBRIGATÓRIA

- **Frontend:** Vue 3 + Vite + TypeScript + Tailwind CSS (reaproveita a base que já tenho).
- **Backend / DB:** Supabase (PostgreSQL + Auth + Edge Functions + Storage).
- **Auth:** Supabase Auth. Login do dono/profissional por Magic Link (sem senha). Cliente final agenda sem conta obrigatória (ver fluxo público abaixo).
- **Lembretes:** Supabase Edge Function agendada (pg_cron / Scheduled Functions) com camada de provedor abstraída (e-mail via Resend no MVP; deixar interface pronta para WhatsApp depois).
- **Migrations:** versionadas em SQL no repositório. Nada de mudança manual no painel.

## 4. MODELO DE DADOS (mínimo)

Toda tabela de negócio **DEVE** ter a coluna `tenant_id uuid not null`.

- `tenants` (id, nome, slug único, plano, status, created_at)
- `profiles` (id = auth.uid, nome, telefone)
- `memberships` (user_id, tenant_id, role: 'owner' | 'staff') — vincula usuário ao tenant
- `professionals` (id, tenant_id, nome, ativo)
- `services` (id, tenant_id, nome, duracao_min, preco, ativo)
- `working_hours` (id, tenant_id, professional_id, weekday, hora_inicio, hora_fim)
- `customers` (id, tenant_id, nome, telefone, email, consentimento_lgpd_at)
- `appointments` (id, tenant_id, professional_id, service_id, customer_id, inicio_at, fim_at, status: 'agendado'|'confirmado'|'cancelado'|'concluido'|'no_show', created_at)
- `reminders` (id, tenant_id, appointment_id, canal, agendado_para, enviado_at, status)
- `audit_log` (id, tenant_id, user_id, acao, tabela, registro_id, payload jsonb, created_at)

## 5. GUARDRAILS DE SEGURANÇA DO BANCO (REQUISITO CRÍTICO)

Implemente **todos** os itens abaixo. Cada um é obrigatório.

### 5.1 Isolamento multi-tenant (RLS)
- [ ] **RLS habilitado E FORÇADO** (`ENABLE ROW LEVEL SECURITY` + `FORCE ROW LEVEL SECURITY`) em **todas** as tabelas — inclusive para o dono das tabelas.
- [ ] **Política padrão = negar tudo.** Nenhuma tabela acessível sem policy explícita.
- [ ] O `tenant_id` **NUNCA** é aceito vindo do cliente. É sempre derivado no servidor a partir da identidade autenticada.
- [ ] Função auxiliar `SECURITY DEFINER` e `STABLE` (ex.: `current_tenant_ids()`) que retorna os tenants aos quais o `auth.uid()` pertence via `memberships`. Toda policy usa essa função:
  `USING (tenant_id IN (SELECT current_tenant_ids()))`.
- [ ] Policies separadas por operação (SELECT/INSERT/UPDATE/DELETE) e por role. Profissional só enxerga a própria agenda; dono enxerga o tenant inteiro.
- [ ] Em `INSERT/UPDATE`, validar com `WITH CHECK` que o `tenant_id` gravado pertence ao usuário — impedir gravar dado em tenant alheio.

### 5.2 Chaves e acesso
- [ ] **`service_role` key JAMAIS no frontend.** Só dentro de Edge Functions / servidor.
- [ ] Frontend usa **apenas** a `anon` key; todo acesso passa por RLS.
- [ ] Segredos (keys, tokens de provedor) só em variáveis de ambiente. Nada commitado no repositório. Inclua `.env.example`.

### 5.3 Fluxo público de agendamento (sem vazar dados)
O cliente final NÃO acessa tabelas diretamente. Crie **RPCs `SECURITY DEFINER`** com validação rígida:
- [ ] `get_available_slots(tenant_slug, service_id, data)` → retorna **somente** horários livres. **Nenhum PII** de outros clientes, nenhuma listagem de tabela.
- [ ] `create_booking(tenant_slug, service_id, professional_id, inicio, nome, telefone, email)` → valida disponibilidade no servidor, cria/associa `customer`, insere `appointment`. Roda como definer mas com checagens explícitas (serviço existe e está ativo, horário dentro do expediente, slot ainda livre).
- [ ] **Rate limiting** no fluxo público (por IP/telefone) para impedir scraping e flood de agendamentos falsos.
- [ ] As páginas públicas expõem apenas: nome do estabelecimento, serviços ativos, profissionais, slots livres. **Nada além disso.**

### 5.4 Integridade de dados
- [ ] **Impedir overbooking** no nível do banco: índice/constraint que rejeita dois `appointments` sobrepostos para o mesmo profissional (ex.: `EXCLUDE USING gist` com `tstzrange` sobre `inicio_at/fim_at`, filtrando por `professional_id` e status ativo).
- [ ] Foreign keys com `ON DELETE` coerente; **soft delete** (coluna `deleted_at`) onde houver dado de cliente.
- [ ] Validação de input no servidor (formato de telefone/e-mail, duração positiva, datas futuras).

### 5.5 Auditoria e conformidade
- [ ] **`audit_log`** gravado por trigger em INSERT/UPDATE/DELETE das tabelas sensíveis (appointments, customers, services).
- [ ] **LGPD:** registrar consentimento do cliente (`consentimento_lgpd_at`), minimizar dados coletados, e ter RPC de exclusão/anonimização a pedido do titular. Retenção configurável.

## 6. LEMBRETES AUTOMÁTICOS
- [ ] Edge Function agendada roda a cada X minutos, busca `appointments` futuros sem lembrete enviado dentro da janela (ex.: 24h e 2h antes) e dispara via provedor.
- [ ] Camada de provedor com interface única (`sendReminder(canal, destino, payload)`); implementar e-mail (Resend) no MVP, deixar WhatsApp plugável.
- [ ] Marcar `reminders.enviado_at` e tratar reenvio idempotente (nunca enviar duplicado).

## 7. ENTREGÁVEIS
1. Migrations SQL versionadas (schema + RLS + funções + triggers + constraints).
2. Frontend Vue 3 com: painel do dono (agenda + CRUD de serviços/profissionais/clientes), login Magic Link, e página pública de agendamento por slug.
3. Edge Functions (lembretes + RPCs sensíveis se aplicável).
4. `README.md` com setup, variáveis de ambiente e como rodar as migrations.
5. `.env.example`.

## 8. CHECKLIST DE ACEITE (não conclua sem passar em todos)
- [ ] Logado como tenant A, é **impossível** ler ou alterar qualquer linha do tenant B (testar via SQL e via API).
- [ ] Página pública não expõe PII de clientes nem dados de outros tenants.
- [ ] Não é possível criar dois agendamentos sobrepostos para o mesmo profissional.
- [ ] `service_role` não aparece em nenhum arquivo do frontend nem no repositório.
- [ ] RLS está FORÇADO em todas as tabelas e o default é negar.
- [ ] Lembrete dispara uma única vez por janela e marca o envio.

---

**Ordem de execução sugerida:** (1) schema + RLS + testes de isolamento → (2) auth e painel do dono → (3) fluxo público de agendamento → (4) lembretes. **Comece confirmando o modelo de isolamento e só então gere as migrations.**
