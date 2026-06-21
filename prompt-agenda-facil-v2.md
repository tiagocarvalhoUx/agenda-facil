# PROMPT DE COMANDO — Sistema de Agendamento Multi-Tenant (SaaS) · v2

> Cole num agente de código (Claude Code / Cursor). Ele assume o papel de **engenheiro de software sênior** com foco crítico em **segurança**, **experiência do usuário** e **conversão da página pública**.

> **O que mudou da v1 → v2**
> - 🟢 **Segurança (seção 5): mantida integralmente.** Continua sendo requisito não-negociável.
> - 🔼 **Funcional muito expandido:** auto-gerenciamento do cliente (cancelar/remarcar por link), buffer entre atendimentos, bloqueios/folgas/feriados, vínculo serviço↔profissional, política de cancelamento, depósito/Pix anti no-show, lista de espera, recorrência, sync Google Calendar, dashboard do dono, locale pt-BR/BRL.
> - 🆕 **UI/UX do zero:** design system dark/premium com guardrails de contraste, **theming white-label por tenant**, especificação da **agenda do dono**, da **página pública (funil de conversão)**, **onboarding (setup wizard)**, estados de loading/empty/erro, mobile-first, microinterações e acessibilidade AA.

---

## 1. PAPEL

Você é um **engenheiro de software sênior** especialista em SaaS multi-tenant, segurança de banco (Supabase/PostgreSQL) **e produto/UX**. Escreve código limpo, tipado e seguro por padrão, e trata **experiência do usuário e conversão como requisito**, não enfeite. **Segurança não é opcional nem "para depois".**

Antes de gerar qualquer código, confirme que entendeu o modelo de isolamento de dados. Se qualquer decisão comprometer o isolamento entre tenants, **pare e me avise** em vez de seguir.

## 2. OBJETIVO DO PRODUTO

Sistema web de **agendamento online** vendido como SaaS por assinatura para **clínicas, salões de beleza e consultórios**. **Multi-tenant**: cada estabelecimento é um tenant isolado no mesmo banco. Produto **white-label** — cada tenant tem marca própria (logo + cor) na página pública.

**Usuários:**
- **Dono/Admin:** gerencia agenda, serviços, profissionais, clientes, horários e marca.
- **Profissional (staff):** vê e gerencia a própria agenda.
- **Cliente final:** marca, **remarca e cancela** o próprio horário sozinho, sem WhatsApp manual e sem conta obrigatória.

**Norte do produto:** reduzir no-show e eliminar o agendamento manual por WhatsApp. Toda decisão funcional/UX deve servir a isso.

## 3. STACK OBRIGATÓRIA

- **Frontend:** Vue 3 (Composition API + `<script setup>`) + Vite + TypeScript estrito + Tailwind CSS.
- **Backend / DB:** Supabase (PostgreSQL + Auth + Edge Functions + Storage).
- **Auth:** Supabase Auth. Dono/profissional por **Magic Link** (sem senha). Cliente final agenda sem conta; gerenciamento via **token assinado** no link (sem login).
- **Lembretes/notificações:** Edge Function agendada (pg_cron / Scheduled Functions) com camada de provedor abstraída (e-mail via Resend no MVP; WhatsApp plugável).
- **Pagamento (opcional plugável):** interface única de provedor; **Pix via Mercado Pago/Stripe** para depósito anti no-show. Deixar desligável por tenant.
- **Migrations:** versionadas em SQL no repositório. Nada manual no painel.
- **Locale:** pt-BR, fuso `America/Sao_Paulo`, moeda BRL, formato 24h.

## 4. MODELO DE DADOS (mínimo)

Toda tabela de negócio **DEVE** ter `tenant_id uuid not null`.

- `tenants` (id, nome, slug único, plano, status, **brand_logo_url**, **brand_color**, **timezone**, **booking_policy** jsonb, created_at)
- `profiles` (id = auth.uid, nome, telefone)
- `memberships` (user_id, tenant_id, role: 'owner' | 'staff')
- `professionals` (id, tenant_id, nome, **avatar_url**, **bio**, ativo)
- `services` (id, tenant_id, nome, **categoria**, duracao_min, **buffer_min**, preco, **exige_deposito** bool, **deposito_valor**, ativo)
- 🆕 `professional_services` (professional_id, service_id, tenant_id) — quais profissionais fazem quais serviços
- `working_hours` (id, tenant_id, professional_id, weekday, hora_inicio, hora_fim)
- 🆕 `time_blocks` (id, tenant_id, professional_id, inicio_at, fim_at, motivo) — folgas, almoço, feriados, bloqueios pontuais
- `customers` (id, tenant_id, nome, telefone, email, **notas** text, **tags** text[], **no_show_count** int default 0, consentimento_lgpd_at, deleted_at)
- `appointments` (id, tenant_id, professional_id, service_id, customer_id, inicio_at, fim_at, status: 'agendado'|'confirmado'|'cancelado'|'concluido'|'no_show', **origem** 'publico'|'painel', **manage_token**, **deposito_status**, created_at)
- 🆕 `waitlist` (id, tenant_id, service_id, professional_id nullable, customer_nome, customer_contato, janela_desejada, created_at)
- `reminders` (id, tenant_id, appointment_id, canal, agendado_para, enviado_at, status)
- `audit_log` (id, tenant_id, user_id, acao, tabela, registro_id, payload jsonb, created_at)

## 5. GUARDRAILS DE SEGURANÇA DO BANCO (REQUISITO CRÍTICO — mantido da v1)

Implemente **todos** os itens. Cada um é obrigatório.

### 5.1 Isolamento multi-tenant (RLS)
- [ ] **RLS habilitado E FORÇADO** (`ENABLE` + `FORCE ROW LEVEL SECURITY`) em **todas** as tabelas, inclusive para o dono das tabelas.
- [ ] **Default = negar tudo.** Nenhuma tabela acessível sem policy explícita.
- [ ] `tenant_id` **NUNCA** vem do cliente — sempre derivado no servidor a partir da identidade autenticada.
- [ ] Função `SECURITY DEFINER` + `STABLE` `current_tenant_ids()` retornando os tenants do `auth.uid()` via `memberships`. Policies usam `USING (tenant_id IN (SELECT current_tenant_ids()))`.
- [ ] Policies separadas por operação (SELECT/INSERT/UPDATE/DELETE) e por role: profissional só a própria agenda; dono o tenant inteiro.
- [ ] `WITH CHECK` em INSERT/UPDATE garantindo que o `tenant_id` gravado pertence ao usuário.

### 5.2 Chaves e acesso
- [ ] **`service_role` JAMAIS no frontend.** Só em Edge Functions/servidor.
- [ ] Frontend usa **apenas** a `anon` key; tudo passa por RLS.
- [ ] Segredos só em env vars. Nada commitado. Inclua `.env.example`.

### 5.3 Fluxo público de agendamento (sem vazar dados)
Cliente final NÃO acessa tabelas direto. Use **RPCs `SECURITY DEFINER`** com validação rígida:
- [ ] `get_available_slots(tenant_slug, service_id, professional_id, data)` → só horários livres. **Zero PII** de outros clientes, sem listagem de tabela. Calcula a partir de `working_hours` − `time_blocks` − `appointments` ativos, respeitando `duracao_min` + `buffer_min`.
- [ ] `create_booking(...)` → valida disponibilidade no servidor, cria/associa `customer`, insere `appointment`. Definer com checagens explícitas (serviço ativo, profissional faz o serviço, dentro do expediente, slot livre).
- [ ] 🆕 `manage_booking(manage_token, acao)` → cliente cancela/remarca via token assinado, respeitando a política de cancelamento. Sem login, sem expor outros dados.
- [ ] **Rate limiting** no fluxo público (IP/telefone) contra scraping e flood.
- [ ] Página pública expõe só: nome do estabelecimento, marca, serviços/profissionais ativos e slots livres. **Nada além.**

### 5.4 Integridade
- [ ] **Anti-overbooking no banco:** `EXCLUDE USING gist` com `tstzrange(inicio_at, fim_at)` por `professional_id`, filtrando status ativo (`btree_gist`).
- [ ] FKs com `ON DELETE` coerente; **soft delete** (`deleted_at`) em dado de cliente.
- [ ] Validação de input no servidor (telefone/e-mail, duração positiva, datas futuras, slot dentro do expediente e fora de `time_blocks`).

### 5.5 Auditoria e LGPD
- [ ] `audit_log` via trigger em INSERT/UPDATE/DELETE de tabelas sensíveis (appointments, customers, services).
- [ ] LGPD: consentimento (`consentimento_lgpd_at`), minimização, RPC de exclusão/anonimização a pedido do titular, retenção configurável.

---

## 6. FUNCIONALIDADES (🔼 expandido)

### 6.1 Núcleo do MVP
1. Cliente agenda sozinho pela página pública `/{slug}` (funil — ver 8.2).
2. Dono vê agenda dia/semana por profissional (ver 8.1).
3. Lembrete automático antes do horário (24h e 2h) para reduzir no-show.
4. Cadastro de clientes com histórico, notas e tags.

### 6.2 Disponibilidade e regras
- **Buffer por serviço** (`buffer_min`): tempo de limpeza/preparo somado ao slot — geração de horários respeita isso.
- **Vínculo serviço↔profissional** (`professional_services`): só oferecer profissionais que fazem aquele serviço.
- **Bloqueios/folgas/feriados** (`time_blocks`): faixas indisponíveis subtraídas dos slots e desenhadas na agenda.
- **Política de agendamento por tenant** (`booking_policy` jsonb): auto-confirmar vs exigir aprovação do dono; antecedência mínima/máxima; janela de cancelamento (ex.: cancelar até 12h antes).

### 6.3 Anti no-show (núcleo do valor)
- **Confirmação por link:** lembrete traz botão "Confirmar presença" → status `confirmado`. Sem confirmação em X tempo, sinaliza risco.
- **Depósito/Pix opcional** (`exige_deposito`): provedor de pagamento plugável; bloquear slot só após pagamento quando exigido.
- **Reputação do cliente:** `no_show_count` incrementado em `no_show`; destacar cliente reincidente no painel.

### 6.4 Auto-gerenciamento do cliente (sem conta)
- Link único (token assinado) na confirmação/lembrete permite **remarcar** ou **cancelar** dentro da política, sem login e sem ver dados de terceiros (via `manage_booking`).
- Tela pública de gerenciamento mostra só o próprio agendamento + ações permitidas.

### 6.5 Recorrência e lista de espera
- **Agendamentos recorrentes** (semanal/quinzenal) com edição "este" vs "todos os futuros".
- **Lista de espera** (`waitlist`) para slots cheios; ao liberar horário, notificar o próximo da fila.

### 6.6 Painel do dono
- **Dashboard:** taxa de ocupação, faturamento estimado, **taxa de no-show**, serviços mais agendados, agendamentos do dia. (Métricas, não vaidade — orientam retenção do tenant.)
- **CRUD** de serviços (com categoria, duração, buffer, preço, depósito), profissionais (avatar, bio, vínculos, horários) e clientes.
- **Busca e filtros** na agenda (profissional, serviço, status, cliente; debounce 300 ms).
- **Notificação ao dono/profissional** em novo agendamento público.

### 6.7 Integrações
- **Sync Google Calendar** (por profissional, opcional): refletir agendamentos para evitar conflito com a agenda pessoal.
- Reaproveitar a camada de provedor (e-mail → WhatsApp → SMS) sem reescrever lógica.

---

## 7. LEMBRETES AUTOMÁTICOS (mantido + idempotência reforçada)
- [ ] Edge Function agendada roda a cada X min, busca `appointments` futuros sem lembrete na janela (24h e 2h) e dispara.
- [ ] Camada de provedor com interface única `sendReminder(canal, destino, payload)`; e-mail (Resend) no MVP, WhatsApp plugável.
- [ ] Marca `reminders.enviado_at`; reenvio **idempotente** (nunca duplica). Lembrete carrega links de **confirmar / remarcar / cancelar**.

---

## 8. UI/UX (🆕 — antes inexistente)

### 8.0 Princípios
- **Clareza > densidade decorativa.** Recepcionista usa isso com cliente na frente: cada ação principal a ≤ 2 toques.
- **Mobile-first** em tudo (dono e cliente operam no celular).
- **Acessível por padrão** (WCAG AA): nunca comunicar estado só por cor; foco visível; alvos de toque ≥ 44px; navegação por teclado na agenda.
- **Feedback sempre:** loading (skeleton), vazio (call-to-action), erro (com retry); ações otimistas com **toast + desfazer**.

### 8.1 Agenda do dono (tela central)
- **Views Dia / Semana** (Dia padrão) + **lista do dia** no mobile; persistir última view por usuário.
- **Coluna por profissional** na view Dia.
- **Drag-and-drop** para remarcar + **resize** para ajustar duração (update otimista, rollback em falha).
- **Quick-create:** tocar em slot vazio abre modal pré-preenchido (data/hora/profissional).
- **Cards** com hierarquia: horário → cliente → serviço → status; iniciais/avatar; cor por status com **legenda**; ações rápidas (confirmar, WhatsApp, concluir, cancelar).
- **Header sticky:** data em destaque, `‹ Hoje ›`, date-picker, seletor de view, filtros.
- **Linha do "agora"**; faixas de `time_blocks` visivelmente bloqueadas.
- **Fetch só do range visível** (nunca tudo); refaz query ao navegar. Atualização **realtime** (Supabase) quando outro usuário mexe.

### 8.2 Página pública de agendamento (funil — conversão é a métrica)
- **Fluxo em passos curtos:** Serviço → Profissional (ou "sem preferência") → Data/Hora → Dados → Confirmação. Indicador de progresso.
- **Seletor de horários** claro (agrupado por manhã/tarde/noite), com feedback imediato de carregamento dos slots.
- **Mínimo de fricção:** só nome/telefone/e-mail; consentimento LGPD explícito; sem cadastro forçado.
- **Tela de confirmação** com resumo, **adicionar ao calendário** (.ics/Google) e **link de gerenciamento** (remarcar/cancelar).
- **Sinais de confiança:** marca do estabelecimento no topo, endereço/horário, microcopy tranquilizadora.
- **Mobile-first**, carregamento rápido (é a primeira impressão do negócio).

### 8.3 White-label / theming por tenant
- Cada tenant define **logo + cor primária** (em `tenants`); a página pública e e-mails refletem a marca.
- Design system com **tokens via CSS variables** + Tailwind; a cor da marca entra como `--brand` sem quebrar contraste (gerar tons acessíveis automaticamente; validar AA).
- Painel interno: identidade **dark/premium com glassmorphism sutil** (vidro só em headers/overlays; cards com fundo sólido o bastante para texto AA). Tipografia legível, espaçamento generoso, raios e elevação consistentes.

### 8.4 Onboarding (setup wizard — ativação do tenant)
- Primeiro acesso do dono: wizard guiado — **1) marca** (logo/cor) → **2) serviços** → **3) profissionais + horários** → **4) link público pronto pra compartilhar**.
- Estados vazios com CTA ("Crie seu primeiro serviço") em vez de telas em branco.

### 8.5 Inventário de componentes a entregar
Card de agendamento, badge de status, grade de slots, navegação de calendário, seletor de profissional, formulário de serviço, drawer/ficha do cliente, modal de quick-create, passos do funil público, toast/undo, skeletons, estados vazio/erro.

---

## 9. PERFORMANCE
- **Virtualizar** grade/lista longas; **memoizar** posição/altura dos blocos (`computed`).
- **Lazy-load** de modais e date-picker (`defineAsyncComponent`).
- **Índice** em `appointments (tenant_id, professional_id, inicio_at)` para a query de range.
- Página pública com bundle enxuto e carregamento de slots rápido.

---

## 10. ENTREGÁVEIS
1. Migrations SQL versionadas (schema + RLS + funções/RPCs + triggers + constraints + índices).
2. Frontend Vue 3: painel do dono (agenda + dashboard + CRUDs + onboarding), login Magic Link, página pública por slug com funil, tela de gerenciamento por token, **theming white-label**.
3. Edge Functions (lembretes + RPCs sensíveis + integrações plugáveis).
4. `README.md` (setup, env vars, como rodar migrations).
5. `.env.example`.
6. 🆕 **Design tokens** documentados (cores/tipografia/espaçamento) e como o tenant aplica a própria marca.

---

## 11. CHECKLIST DE ACEITE (não conclua sem passar em todos)

**Segurança (mantido)**
- [ ] Logado como tenant A é **impossível** ler/alterar linha do tenant B (testar via SQL e API).
- [ ] Página pública não expõe PII nem dados de outros tenants.
- [ ] Impossível criar dois agendamentos sobrepostos para o mesmo profissional.
- [ ] `service_role` não aparece no frontend nem no repositório.
- [ ] RLS FORÇADO em todas as tabelas; default = negar.
- [ ] Lembrete dispara uma única vez por janela e marca o envio.

**Funcional (novo)**
- [ ] Cliente cancela/remarca pelo link sem login e dentro da política, sem ver dados de terceiros.
- [ ] Slots respeitam duração + buffer + horário + bloqueios + vínculo serviço↔profissional.
- [ ] No-show incrementa reputação do cliente; depósito (quando exigido) bloqueia o slot só após pagamento.

**UI/UX (novo)**
- [ ] Agenda do dono usável em viewport de 360px; remarcar por drag-and-drop com rollback em erro.
- [ ] Funil público conclui em ≤ 5 passos no mobile, com confirmação + add-to-calendar + link de gerenciamento.
- [ ] Marca do tenant (logo/cor) aplicada na página pública sem quebrar contraste AA.
- [ ] Todos os fluxos têm estado de loading, vazio e erro.

---

**Ordem de execução:** (1) schema + RLS + testes de isolamento → (2) auth + onboarding + painel do dono (agenda) → (3) funil público + gerenciamento por token → (4) lembretes/confirmação + anti no-show → (5) dashboard + integrações. **Comece confirmando o modelo de isolamento e só então gere as migrations.**
