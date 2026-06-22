# Deploy na Vercel

O frontend (Vite SPA) vai para a Vercel. O **backend continua no Supabase** —
banco, Auth e a Edge Function de lembretes **não** são deployados pela Vercel.

## 1. Banco de produção (Supabase) — fazer ANTES do primeiro deploy

```bash
# Vincula o repo a um projeto Supabase de produção (cria um se precisar no painel).
supabase link --project-ref SEU_PROJECT_REF

# Aplica TODAS as migrations versionadas no projeto remoto.
supabase db push
```

- **Nunca** rode `scripts/dev_seed_owner.sql` em produção — é seed de demonstração
  (cria `dono@studio.com` e agendamentos fake). Em produção o dono real se cadastra
  pelo fluxo de magic link.
- `supabase/seed.sql` (tenant de exemplo) também é opcional/demo — decida se quer
  dados de exemplo em produção.

## 2. Variáveis de ambiente na Vercel

Em **Project → Settings → Environment Variables**, defina para *Production* e *Preview*:

| Variável | Valor |
|---|---|
| `VITE_SUPABASE_URL` | `https://SEU-PROJ.supabase.co` (projeto de **produção**, não localhost) |
| `VITE_SUPABASE_ANON_KEY` | a **anon key** pública do projeto (`Settings → API`) |

> Só a `anon key` vai ao frontend. A `service_role` **jamais** entra aqui — ela
> só existe nas Edge Functions (`supabase secrets set ...`).
> As `VITE_*` são embutidas no bundle em build-time, então um redeploy é
> necessário após alterá-las.

## 3. Auth — liberar o domínio da Vercel (senão o magic link quebra)

No painel Supabase → **Authentication → URL Configuration**:

- **Site URL:** `https://SEU-APP.vercel.app`
- **Redirect URLs:** adicione `https://SEU-APP.vercel.app/**` (e o domínio custom,
  se houver). Sem isso, o link de acesso redireciona para um host não autorizado.

### 3.1. Login Google (provedor OAuth)

O botão "Entrar com Google" usa `signInWithOAuth({ provider: 'google' })`. Sem o
provedor habilitado, o Supabase responde `Unsupported provider: provider is not
enabled`. As credenciais OAuth são geradas no **Google Cloud Console**.

**No Google Cloud Console** ([APIs & Serviços → Credenciais](https://console.cloud.google.com/apis/credentials)):

1. *Criar credenciais → ID do cliente OAuth → Aplicativo da Web*.
2. **URIs de redirecionamento autorizados** — adicione os dois:
   - `https://SEU-PROJ.supabase.co/auth/v1/callback` (produção)
   - `http://127.0.0.1:54321/auth/v1/callback` (dev local)
3. **Origens JavaScript autorizadas** — `https://agenda-facil-murex.vercel.app`
   (e `http://localhost:5173` para dev).
4. Copie o **Client ID** e o **Client Secret**.

**Em produção** (painel Supabase → *Authentication → Providers → Google*):

- Habilite, cole Client ID/Secret e salve.
- Confirme que `https://agenda-facil-murex.vercel.app/**` está nas Redirect URLs
  (passo 3) — o app redireciona para `/app` após o login.

**Em dev local:** preencha `supabase/.env` (ver `supabase/.env.example`) com
`SUPABASE_AUTH_GOOGLE_CLIENT_ID` e `SUPABASE_AUTH_GOOGLE_SECRET` e rode
`supabase stop && supabase start` para recarregar o `config.toml`.

## 4. Deploy

A config já está em [`vercel.json`](vercel.json): framework `vite`, build
`npm run build`, saída `dist/`, e o **rewrite de SPA** (toda rota → `index.html`,
exceto `/assets/*`) — necessário porque o router usa history mode (`/:slug`,
`/app/...`); sem ele, dar refresh numa rota interna daria 404.

```bash
# Opção A: conectar o repo Git no painel da Vercel (deploy automático em cada push).
# Opção B: CLI
npm i -g vercel
vercel            # preview
vercel --prod     # produção
```

O build roda `vue-tsc --noEmit && vite build`, então **erros de tipo barram o
deploy** — rode `npm run build` localmente antes de subir.

## 5. Lembretes (Edge Function) — fora da Vercel

```bash
supabase secrets set RESEND_API_KEY=re_xxx
supabase secrets set REMINDER_FROM_EMAIL="lembretes@seu-dominio.com"
supabase secrets set CRON_SECRET="$(openssl rand -hex 32)"
supabase functions deploy send-reminders
```

E agende via `pg_cron` + `pg_net` (ver `README.md`).

## 6. Pagamento recorrente (Asaas) — Edge Function `payments`

Esqueleto plugável (interface única; Asaas no MVP). A API key é **server-only**.

```bash
# Segredos (NUNCA no frontend)
supabase secrets set PAYMENT_PROVIDER=asaas
supabase secrets set ASAAS_API_KEY="$aact_xxx"      # painel Asaas → Integrações → API
supabase secrets set ASAAS_ENV=sandbox              # troque p/ production quando for valer
supabase secrets set ASAAS_WEBHOOK_TOKEN="$(openssl rand -hex 24)"

supabase functions deploy payments
```

No painel Asaas → **Webhooks**, aponte para
`https://SEU-PROJ.supabase.co/functions/v1/payments/webhook` e configure o header
`asaas-access-token` com o mesmo valor de `ASAAS_WEBHOOK_TOKEN`.

- **Assinar (frontend):** `POST .../functions/v1/payments/subscribe` com o JWT do
  dono no `Authorization` e body `{ tenant_id, plano, valor, ciclo, billingType, cpfCnpj }`.
  A função valida que o chamador é **owner** do tenant antes de cobrar.
- O estado fica em `tenant_billing` (o dono só LÊ via RLS; escrita só pela função).
- Trocar de provedor (ex.: Mercado Pago) = implementar a mesma interface em
  `functions/payments/providers.ts`. Nada no resto do app muda.

## 7. Paywall do trial — trava também no banco (RLS)

Além do bloqueio no frontend (router guard → `/assinatura`), a migration
`20260622120003_billing_enforcement.sql` reforça o paywall na **RLS**: sem
assinatura ativa e com o trial vencido, o painel **não consegue escrever**
(INSERT/UPDATE/DELETE) nas tabelas operacionais — nem chamando a API REST direto
com o token. A leitura continua liberada; o fluxo público de agendamento (RPCs
`SECURITY DEFINER`) **não** é afetado. Aplica junto no `supabase db push`.

> Validado localmente: dono com trial vencido recebe
> `new row violates row-level security policy`; com `status='ativo'` o INSERT passa.

## Checklist rápido

- [ ] `supabase db push` aplicado no projeto de produção (inclui o reforço de billing na RLS)
- [ ] `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` definidas na Vercel
- [ ] Site URL + Redirect URLs configurados no Auth do Supabase
- [ ] Provedor Google habilitado (painel) + redirect `.../auth/v1/callback` no Google Console
- [ ] `npm run build` passa localmente
- [ ] Edge Function `send-reminders` deployada + cron agendado
