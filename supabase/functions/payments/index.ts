// Edge Function de PAGAMENTO (assinatura recorrente do SaaS + webhook).
// Roda no SERVIDOR com service_role; a API key do provedor é env secret e
// NUNCA vai ao frontend (§5.2). O frontend só chama /subscribe com o JWT do
// dono; a função valida a identidade e a posse do tenant antes de cobrar.
//
// Rotas (pelo final do path):
//   POST .../payments/subscribe  → cria/atualiza a assinatura do tenant
//   POST .../payments/webhook    → recebe eventos do provedor (Asaas)
//
// Deploy:
//   supabase functions deploy payments
//   supabase secrets set ASAAS_API_KEY=... ASAAS_ENV=sandbox ASAAS_WEBHOOK_TOKEN=...
// Webhook no painel Asaas → URL .../functions/v1/payments/webhook com o mesmo
// ASAAS_WEBHOOK_TOKEN no header 'asaas-access-token'.

import { createClient } from 'jsr:@supabase/supabase-js@2'
import { getProvider } from './providers.ts'
import { trackSubscribeCAPI } from './meta.ts'

const TZ = 'America/Sao_Paulo'
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function today(): string {
  // yyyy-mm-dd no fuso do Brasil
  return new Intl.DateTimeFormat('en-CA', { timeZone: TZ }).format(new Date())
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS },
  })
}

function service() {
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, // server-only
  )
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  const url = new URL(req.url)
  const route = url.pathname.split('/').pop()

  try {
    if (route === 'subscribe') return await handleSubscribe(req)
    if (route === 'webhook') return await handleWebhook(req)
    return json({ error: 'not_found' }, 404)
  } catch (e) {
    const msg = String((e as Error).message ?? e)
    const status = msg === 'webhook_unauthorized' ? 401 : 500
    return json({ error: msg }, status)
  }
})

// ---------------------------------------------------------------------
// /subscribe — dono autenticado cria a assinatura do próprio tenant.
// Body: { tenant_id, plano, valor, ciclo, billingType, cpfCnpj }
// ---------------------------------------------------------------------
async function handleSubscribe(req: Request): Promise<Response> {
  const jwt = req.headers.get('Authorization')?.replace('Bearer ', '')
  if (!jwt) return json({ error: 'unauthorized' }, 401)

  const db = service()

  // Identidade do chamador a partir do JWT.
  const { data: userData, error: userErr } = await db.auth.getUser(jwt)
  if (userErr || !userData.user) return json({ error: 'unauthorized' }, 401)
  const user = userData.user

  const body = await req.json().catch(() => ({}))
  const tenantId = body.tenant_id as string
  if (!tenantId) return json({ error: 'tenant_id_required' }, 400)

  // Posse: o chamador é OWNER do tenant?
  const { data: mem } = await db
    .from('memberships')
    .select('id')
    .eq('user_id', user.id)
    .eq('tenant_id', tenantId)
    .eq('role', 'owner')
    .maybeSingle()
  if (!mem) return json({ error: 'forbidden' }, 403)

  const { data: tenant } = await db.from('tenants').select('nome').eq('id', tenantId).single()

  const provider = getProvider()
  const billingType = (body.billingType as string) ?? 'PIX'
  const cycle = (body.ciclo as string) ?? 'MONTHLY'
  const valor = Number(body.valor ?? 0)

  const customerId = await provider.ensureCustomer({
    name: (tenant?.nome as string) ?? user.email ?? 'Cliente',
    email: user.email ?? undefined,
    cpfCnpj: body.cpfCnpj as string | undefined,
    externalRef: tenantId,
  })

  const sub = await provider.createSubscription({
    customerId,
    value: valor,
    cycle: cycle as never,
    billingType: billingType as never,
    description: `Assinatura ${body.plano ?? 'SaaS Agenda'}`,
    nextDueDate: today(),
  })

  await db.from('tenant_billing').upsert(
    {
      tenant_id: tenantId,
      provider: provider.name,
      customer_id: customerId,
      subscription_id: sub.subscriptionId,
      plano: body.plano ?? null,
      valor,
      ciclo: cycle,
      billing_type: billingType,
      status: 'ativo',
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'tenant_id' },
  )

  return json({ subscriptionId: sub.subscriptionId, status: 'ativo' })
}

// ---------------------------------------------------------------------
// /webhook — eventos do provedor. Valida token, registra e atualiza estado.
// ---------------------------------------------------------------------
async function handleWebhook(req: Request): Promise<Response> {
  const body = await req.json().catch(() => ({}))
  const provider = getProvider()
  const ev = provider.parseWebhook(req.headers, body) // lança se token inválido

  const db = service()
  await db.from('billing_events').insert({
    provider: provider.name,
    event: ev.event,
    external_id: ev.chargeId ?? ev.subscriptionId ?? null,
    payload: ev.raw,
  })

  const pago = ev.paymentStatus === 'CONFIRMED' || ev.paymentStatus === 'RECEIVED'

  // Depósito anti no-show: externalReference = appointment_id.
  if (ev.externalRef && ev.externalRef.length === 36) {
    await db
      .from('appointments')
      .update({
        deposito_status: pago ? 'pago' : 'pendente',
        deposito_charge_id: ev.chargeId ?? null,
      })
      .eq('id', ev.externalRef)
  }

  // Assinatura do tenant.
  if (ev.subscriptionId) {
    let status: string | null = null
    if (pago) status = 'ativo'
    else if (ev.paymentStatus === 'OVERDUE' || ev.event === 'PAYMENT_OVERDUE') status = 'atrasado'
    else if (ev.event === 'SUBSCRIPTION_DELETED') status = 'cancelado'
    if (status) {
      await db
        .from('tenant_billing')
        .update({ status, updated_at: new Date().toISOString() })
        .eq('subscription_id', ev.subscriptionId)
    }

    // Subscribe (Meta CAPI) — a conversão que vale dinheiro. Dispara UMA vez,
    // no 1º pagamento confirmado. Como /subscribe já marca 'ativo' na criação,
    // a trava é a coluna subscribe_tracked_at (claim atômico anti-retry).
    if (pago) {
      const { data: claimed } = await db
        .from('tenant_billing')
        .update({ subscribe_tracked_at: new Date().toISOString() })
        .eq('subscription_id', ev.subscriptionId)
        .is('subscribe_tracked_at', null)
        .select('tenant_id, valor')
        .maybeSingle()
      if (claimed?.tenant_id) {
        try {
          await trackSubscribeCAPI({
            email: await ownerEmail(db, claimed.tenant_id as string),
            value: Number(claimed.valor ?? 0),
            eventId: ev.subscriptionId,
          })
        } catch (e) {
          // telemetria nunca derruba o webhook (o billing já foi gravado).
          console.error('Subscribe CAPI:', String((e as Error).message ?? e))
        }
      }
    }
  }

  return json({ received: true })
}

// E-mail do DONO do tenant (para o match da Meta CAPI). O webhook do Asaas não
// traz o e-mail; buscamos via membership 'owner' → auth.users (service_role).
async function ownerEmail(db: ReturnType<typeof service>, tenantId: string): Promise<string | undefined> {
  const { data: mem } = await db
    .from('memberships')
    .select('user_id')
    .eq('tenant_id', tenantId)
    .eq('role', 'owner')
    .maybeSingle()
  if (!mem?.user_id) return undefined
  const { data } = await db.auth.admin.getUserById(mem.user_id as string)
  return data.user?.email ?? undefined
}

declare const Deno: {
  serve(handler: (req: Request) => Response | Promise<Response>): void
  env: { get(k: string): string | undefined }
}
