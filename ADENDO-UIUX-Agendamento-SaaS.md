1# ADENDO DE UI/UX — Sistema de Agendamento Multi-Tenant (SaaS)

> Anexo ao "PROMPT DE COMANDO" do projeto. Cole junto ao prompt original num agente de código. Esta parte assume o papel de **UI/UX designer sênior** e tem foco em **conversão (cliente final), eficiência (dono/profissional) e confiança (LGPD)**. As regras de segurança/RLS do prompt original continuam valendo integralmente — **nenhuma decisão de UI pode contornar RLS, expor PII ou aceitar `tenant_id` do cliente.**

---

## 9. PAPEL (DESIGN)

Você é um **UI/UX designer sênior de produto**, especialista em SaaS B2B2C, sistemas de calendário/agenda e interfaces que precisam converter visitantes em agendamentos com mínimo atrito. Você projeta por **token**, documenta **estados** (não só o "happy path") e escreve **microcopy** que ajuda o usuário a agir. Você só usa a `anon` key no front; o desenho da UI nunca pede ou expõe dados além do que a RLS/RPC já libera.

Regra de ouro de design: **cada tela tem um único trabalho.** Se a tela tenta fazer duas coisas, divida.

---

## 10. PRINCÍPIOS DE PRODUTO

1. **Tempo até o agendamento < 60s** na página pública. Tudo que não acelera isso é distração.
2. **A agenda é o produto.** Para dono e profissional, a tela de agenda é a home — abre direto nela, sem dashboard intermediário.
3. **Glanceability.** Profissional precisa entender o dia em 1 olhada (cores de status, "agora", próximos).
4. **Confiança é UX.** Confirmações claras, consentimento LGPD honesto, nunca "dark patterns".
5. **Falha e vazio dão direção**, não desculpa. Todo estado vazio convida a uma ação.
6. **Mobile-first** para cliente final e profissional; **desktop-first** para o dono (densidade de informação).

---

## 11. OS TRÊS CONTEXTOS DE USO

| Persona | Dispositivo dominante | Contexto | "Job" único | Prioridade de design |
|---|---|---|---|---|
| **Cliente final** | Celular, 1 visita, internet ruim | "Quero marcar e ir embora" | Agendar em poucos toques sem conta | Velocidade, clareza, confiança |
| **Profissional (staff)** | Celular/tablet, entre atendimentos | "O que tenho hoje/agora?" | Ver e gerenciar a própria agenda | Glanceability, toque grande, foco no dia |
| **Dono/Admin** | Desktop, sessões de gestão | "Controlar o negócio" | CRUD + agenda do tenant inteiro | Densidade, atalhos, multi-profissional |

> **Implicação de RLS na UI:** o profissional só vê a própria agenda (a UI nunca renderiza outros profissionais para ele); o dono vê o tenant inteiro. A UI reflete exatamente o que a policy permite — não esconde com CSS o que deveria ser barrado no banco.

---

## 12. ARQUITETURA DE INFORMAÇÃO & NAVEGAÇÃO

**Público (cliente final)** — `/{slug}` — sem navegação global, é um funil linear:
`Estabelecimento → Serviço → Profissional (opcional) → Data → Horário → Dados + LGPD → Confirmação`

**Painel autenticado** (dono/profissional) — navegação lateral (desktop) / barra inferior (mobile):
- **Agenda** (home)
- **Clientes**
- **Serviços** *(dono)*
- **Profissionais** *(dono)*
- **Configurações** *(dono: marca, horários, lembretes, LGPD)*

A navegação é **role-aware**: itens que a role não acessa não aparecem (e a rota é protegida no servidor, não só escondida).

---

## 13. DESIGN SYSTEM — TOKENS

Implemente como CSS custom properties + mapeie no `tailwind.config`. **Nada de hex solto nos componentes** — sempre token.

### 13.1 Cor — sistema neutro + acento por tenant
O sistema é neutro e profissional; cada tenant injeta **um** `--accent` (white-label leve). Carregue `--accent` do registro do tenant **no servidor/SSR**, com fallback por vertical.

```css
:root {
  /* Neutros (slate levemente quente — calmo, clínico) */
  --bg:        #FBFBFA;
  --surface:   #FFFFFF;
  --surface-2: #F4F5F4;
  --border:    #E4E6E4;
  --text:      #1B2421;
  --text-muted:#5B6560;

  /* Primária do sistema (navegação, estrutura) — petróleo profundo */
  --ink:       #0E3A36;

  /* Acento configurável por tenant (CTA, seleção, destaque) */
  --accent:        #0E9F9A;   /* default */
  --accent-hover:  #0B8783;
  --accent-soft:   #E6F5F4;   /* fundos/realces suaves */
  --on-accent:     #FFFFFF;

  /* Semânticas */
  --success: #1A7F5A;
  --warning: #B45309;
  --danger:  #B42318;
  --info:    #1E6FB8;
}
```
Sugestões de `--accent` por vertical (default, ajustável pelo dono): **clínica/consultório** `#1E6FB8` (azul confiança) · **salão/estética** `#C84B6B` (rosa/coral) · **fallback** `#0E9F9A` (teal).

### 13.2 Cores de status do agendamento (crítico para a agenda)
Status sempre comunicado por **cor + ícone/rótulo** (nunca só cor — daltonismo):

| Status | Cor base | Tratamento visual |
|---|---|---|
| `agendado` | `--info` | barra lateral azul, fundo claro |
| `confirmado` | `--success` | barra verde, ícone ✓ |
| `cancelado` | `--danger` | texto riscado, fundo esmaecido |
| `concluido` | `--text-muted` | cinza, sem destaque |
| `no_show` | `--warning` | tracejado âmbar, ícone alerta |

### 13.3 Tipografia
- **Display/títulos:** `Plus Jakarta Sans` (600/700) — humanista, profissional, com personalidade sem ser "barulhento".
- **Texto/UI/dados:** `Inter` (400/500/600). **Horários e durações usam `font-variant-numeric: tabular-nums`** (alinhamento de colunas na agenda).

| Token | Tamanho/linha | Peso | Uso |
|---|---|---|---|
| `display-lg` | 32/40 | 700 | Hero da página pública |
| `h1` | 24/32 | 700 | Título de página |
| `h2` | 20/28 | 600 | Seções |
| `h3` | 16/24 | 600 | Cards, labels fortes |
| `body` | 16/24 | 400 | Texto padrão (mín. 16px no público — evita zoom no iOS) |
| `small` | 14/20 | 400 | Apoio |
| `caption` | 12/16 | 500 | Eyebrows/metadados (uppercase, `letter-spacing .04em`) |

### 13.4 Espaçamento, raio, sombra, motion
- **Espaçamento** (base 4px): `1=4 · 2=8 · 3=12 · 4=16 · 5=24 · 6=32 · 7=48 · 8=64`.
- **Raio:** `sm=6 · md=10 · lg=16 · pill=999`. (Arredondado mas sóbrio — não "bubbly".)
- **Sombra:** `sm` (cards), `md` (popover/menu), `lg` (modais). Sombras suaves, baixa opacidade.
- **Motion:** durações `120 / 180 / 240ms`; easing padrão `cubic-bezier(0.2, 0, 0, 1)`. **Respeitar `prefers-reduced-motion`** (sem animação não essencial).
- **Toque:** alvo mínimo **44×44px** (público e profissional).

### 13.5 Assinatura visual (o elemento memorável)
**"Trilho de horário vivo":** na agenda, uma linha fina com o token `--accent` marca o **horário atual** e desliza durante o dia; slots passados ficam esmaecidos. É o detalhe que dá vida e orientação temporal — único, mas discreto. Toda a ousadia mora aqui; o resto permanece quieto.

---

## 14. BIBLIOTECA DE COMPONENTES (com estados)

Documente **todos os estados** de cada componente: `default · hover · focus(visível) · active · disabled · loading · error`.

- **Button** — variantes `primary` (usa `--accent`), `secondary` (contorno), `ghost`, `danger`. Estado `loading` mostra spinner e desabilita.
- **Input / Select / DatePicker / PhoneInput** — label sempre visível (não placeholder-como-label), erro abaixo do campo em `--danger`, máscara de telefone BR.
- **SlotPicker** (público) — grade de horários como "pills" tocáveis; indisponível = desabilitado/oculto. Nunca mostra o porquê (sem PII).
- **AppointmentCard** — bloco na agenda; cor por status (13.2); mostra hora, serviço, cliente, profissional.
- **CalendarGrid** — visão dia/semana, colunas por profissional, "trilho de horário vivo".
- **Modal / Drawer / Sheet** — drawer lateral no desktop, bottom-sheet no mobile para criar/editar.
- **Toast** — feedback de ação (sucesso/erro), 4s, fila.
- **EmptyState** — ícone + frase + 1 CTA.
- **Skeleton** — placeholders para agenda, listas e SlotPicker.
- **Badge/Status pill**, **Avatar (iniciais)**, **ConsentCheckbox (LGPD)**, **DateNavigator** (hoje / setas / “hoje”).

---

## 15. FLUXOS-CHAVE

### 15.1 Fluxo público de agendamento (o fluxo que dá dinheiro)
Linear, 1 decisão por tela no mobile, com **stepper** e botão "voltar" sempre presentes.

1. **Capa do estabelecimento** — nome, logo, foto opcional, lista de **serviços ativos** (nome, duração, preço). CTA grande "Agendar". Exibe apenas o permitido pela RPC `get_available_slots`/dados públicos.
2. **Serviço** → 3. **Profissional** ("Qualquer disponível" como opção padrão, reduz atrito) → 4. **Data** (datas sem disponibilidade desabilitadas) → 5. **Horário** (SlotPicker; só slots livres).
3. **Identificação + LGPD** — nome, telefone, e-mail; **consentimento LGPD explícito** (checkbox não pré-marcado, com link para política). Sem criar conta.
4. **Confirmação** — resumo (serviço, profissional, data/hora, local), botão **"Adicionar ao calendário"** (.ics) e aviso de que receberá lembrete. Mensagem clara do que acontece a seguir.

**Anti-atrito / anti-abuso (alinhado ao rate limiting do backend):**
- Salvar progresso em memória (não recomeçar ao voltar).
- Em flood/limite atingido, mensagem honesta ("Muitas tentativas. Tente em alguns minutos.") — sem expor regra exata.
- Otimista no toque, mas **a disponibilidade é reconfirmada no servidor** na criação; se o slot caiu, mostrar erro e re-oferecer horários.

### 15.2 Agenda do dono (desktop)
- Abre na **semana atual**, todos os profissionais em colunas. Alternância **Dia / Semana**.
- Criar agendamento: clique num slot vazio → drawer com formulário (cliente buscável, serviço, profissional pré-preenchido pela coluna).
- **Overbooking:** a UI **não deixa** soltar/criar sobreposição; se o banco rejeitar (constraint `EXCLUDE`), toast claro: "Esse horário conflita com outro agendamento de [profissional]."
- Filtro por profissional/serviço; busca de cliente.

### 15.3 Agenda do profissional (mobile)
- Abre no **dia de hoje**, lista vertical com "agora" destacado. Toque no card → ações: confirmar, concluir, marcar no-show, cancelar.
- Só a própria agenda (garantido por RLS).

---

## 16. ESPECIFICAÇÃO TELA A TELA (HANDOFF)

### 16.1 Página pública — passo "Horário"
**Layout:** mobile 1 coluna; SlotPicker em grade 3–4 colunas de pills. Desktop ≥768px: calendário + slots lado a lado.

**Componentes:** `DateNavigator`, `SlotPicker`, `Button(primary)` "Continuar".

**Estados & interações:**
| Elemento | Estado | Comportamento |
|---|---|---|
| Slot pill | default → hover | borda `--accent`, fundo `--accent-soft` |
| Slot pill | selected | fundo `--accent`, texto `--on-accent` |
| Slot pill | indisponível | desabilitado (cinza) ou oculto |
| Continuar | sem seleção | desabilitado |
| Lista de slots | loading | 8 skeletons em grade |

**Responsivo:** Mobile (<768) pills 3 col; Tablet/Desktop (≥768) calendário à esquerda, slots à direita.

**Edge cases:** **Vazio** ("Sem horários nesse dia. Veja outra data." + atalho próximo dia disponível) · **Erro de rede** (retry) · **Slot tomado na hora de confirmar** (re-oferecer).

**Acessibilidade:** SlotPicker é um `radiogroup`; setas navegam; foco visível; cada pill com `aria-label="14:30, disponível"`.

### 16.2 Agenda (dono/profissional)
**Tokens:** `--surface` (fundo grade), `--border` (linhas de hora), `--accent` (trilho "agora"), cores de status (13.2).

**Estados:** loading = skeleton da grade; vazio = "Nenhum agendamento. [Novo agendamento]"; erro = banner com retry.

**Motion:** card aparece em 180ms; trilho "agora" anima posição a cada minuto (sem motion se `reduced-motion`).

**Acessibilidade:** navegação por teclado entre slots; `aria-live="polite"` anuncia mudanças de status; cor nunca é o único sinal.

### 16.3 Login (Magic Link)
Tela única: e-mail + "Enviar link". Após envio → estado "Confira seu e-mail" (não revela se o e-mail existe — privacidade). Sem campo de senha.

---

## 17. ESTADOS + UX WRITING (PT-BR)

Voz: **clara, ativa, sem jargão técnico, sem se desculpar**. Ações nomeiam o que fazem; o nome se mantém pelo fluxo (botão "Confirmar" → toast "Agendamento confirmado").

| Situação | Microcopy |
|---|---|
| Vazio — agenda do dia | "Nada na agenda hoje. Aproveite — ou crie um agendamento." |
| Vazio — sem serviços (dono) | "Cadastre seu primeiro serviço para começar a receber agendamentos." |
| Sucesso — booking | "Agendamento confirmado! Você receberá um lembrete antes." |
| Erro — slot tomado | "Esse horário acabou de ser ocupado. Escolha outro:" |
| Erro — conflito (overbooking) | "Conflito com outro agendamento desse profissional." |
| Limite (rate limit) | "Muitas tentativas em pouco tempo. Tente novamente em alguns minutos." |
| Consentimento LGPD | "Autorizo o uso dos meus dados para gerenciar este agendamento e receber lembretes." (checkbox não pré-marcado) |

Regras: **nunca placeholder como label**; erros dizem **o que houve e como resolver**; datas/horas no formato BR (`dd/mm`, `HH:mm`, 24h).

---

## 18. ACESSIBILIDADE (WCAG 2.1 AA — piso obrigatório)
- Contraste texto ≥ 4.5:1; verificar que `--accent` escolhido pelo tenant atinge contraste sobre branco (validar no salvamento da cor; se falhar, escurecer automaticamente o tom usado em texto/CTA).
- **Foco visível** em todo elemento interativo; ordem de foco lógica.
- Status por **cor + ícone/texto** (nunca só cor).
- Alvos de toque ≥ 44px; labels associadas a inputs; `aria-live` para toasts e mudanças de agenda.
- Suporte a `prefers-reduced-motion` e zoom até 200% sem quebra.

---

## 19. RESPONSIVIDADE & PERFORMANCE PERCEBIDA
- **Breakpoints:** mobile <640 · tablet 640–1024 · desktop >1024.
- Público e agenda do profissional desenhados **mobile-first**; painel do dono otimizado para desktop, utilizável no tablet.
- **Performance da página pública** (impacta conversão e SEO): SSR/pré-render da capa, fontes com `display=swap` e subset, **skeletons** em vez de spinners brancos, lazy-load de imagens. Meta: interativo rápido em 3G.

---

## 20. LGPD & CONFIANÇA COMO UX
- Consentimento explícito e granular no booking; link para política sempre visível.
- **Minimização:** pedir só nome, telefone, e-mail. Nada além.
- Tela de "Meus dados" / RPC de exclledusão–anonimização exposta de forma localizável (alinhada ao backend).
- Nunca mostrar PII de um cliente para outro; a UI do público jamais lista clientes/agenda de terceiros.

---

## 21. CHECKLIST DE ACEITE — DESIGN (não conclua sem passar em todos)
- [ ] Fluxo público concluível em **≤ 5 toques** após escolher serviço, no mobile, sem conta.
- [ ] Nenhum hex solto: 100% via tokens; `--accent` do tenant aplicado via SSR com fallback.
- [ ] Todo componente documentado com estados default/hover/focus/disabled/loading/error/empty.
- [ ] Status de agendamento legível por **cor + ícone/texto** (passa em simulação de daltonismo).
- [ ] Contraste AA inclusive com o `--accent` do tenant (validação automática ao salvar a cor).
- [ ] Foco de teclado visível e ordem lógica em todas as telas; alvos ≥ 44px.
- [ ] Estados de vazio/erro/loading existem em agenda, listas e SlotPicker (sem tela branca).
- [ ] Profissional só vê a própria agenda na UI; dono vê o tenant inteiro (espelha a RLS).
- [ ] Microcopy em PT-BR, voz ativa, datas/horas no formato BR.
- [ ] `prefers-reduced-motion` respeitado; público interativo rápido em conexão lenta.

---

**Ordem de execução sugerida (design):** (1) tokens + tema por tenant + componentes base com estados → (2) página pública (fluxo de conversão) → (3) agenda (dono/profissional) → (4) CRUD + configurações + telas LGPD. **Comece pelos tokens e pelo fluxo público — é onde mora o valor.**
