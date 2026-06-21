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

## Checklist rápido

- [ ] `supabase db push` aplicado no projeto de produção
- [ ] `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` definidas na Vercel
- [ ] Site URL + Redirect URLs configurados no Auth do Supabase
- [ ] `npm run build` passa localmente
- [ ] Edge Function `send-reminders` deployada + cron agendado
