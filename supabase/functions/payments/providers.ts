// Camada de provedor de PAGAMENTO — interface única e plugável (§3/§6.3).
// MVP implementa Asaas (recorrência via Pix Automático/cartão + cobrança Pix
// avulsa do depósito anti no-show). Outros provedores (Mercado Pago, Stripe)
// entram implementando a mesma interface, sem mexer no resto.
//
// SEGURANÇA: a API key vive APENAS aqui (Edge Function), via env secret.
// JAMAIS no frontend (§5.2).

export interface CustomerInput {
  name: string
  email?: string
  phone?: string
  cpfCnpj?: string
  externalRef?: string // ex.: tenant_id
}

export interface SubscriptionInput {
  customerId: string
  value: number
  cycle: 'WEEKLY' | 'BIWEEKLY' | 'MONTHLY' | 'QUARTERLY' | 'SEMIANNUALLY' | 'YEARLY'
  billingType: 'PIX' | 'CREDIT_CARD' | 'BOLETO'
  description: string
  nextDueDate: string // yyyy-mm-dd
}

export interface SubscriptionResult {
  subscriptionId: string
  status: string
}

export interface PixChargeInput {
  customerId: string
  value: number
  description: string
  dueDate: string // yyyy-mm-dd
  externalRef?: string // ex.: appointment_id (depósito)
}

export interface PixChargeResult {
  chargeId: string
  status: string
  pixCopiaECola?: string
  pixQrCodeBase64?: string
}

export interface WebhookEvent {
  event: string // ex.: PAYMENT_CONFIRMED, PAYMENT_OVERDUE, SUBSCRIPTION_DELETED
  paymentStatus?: string
  subscriptionId?: string
  chargeId?: string
  externalRef?: string
  raw: unknown
}

export interface PaymentProvider {
  name: string
  ensureCustomer(c: CustomerInput): Promise<string>
  createSubscription(i: SubscriptionInput): Promise<SubscriptionResult>
  getSubscription(id: string): Promise<SubscriptionResult>
  cancelSubscription(id: string): Promise<void>
  createPixCharge(i: PixChargeInput): Promise<PixChargeResult>
  // valida a autenticidade do webhook e normaliza o evento.
  parseWebhook(headers: Headers, body: unknown): WebhookEvent
}

// ---------------------------------------------------------------------
// Asaas — https://docs.asaas.com
// ---------------------------------------------------------------------
export class AsaasProvider implements PaymentProvider {
  name = 'asaas'
  private base: string
  constructor(
    private apiKey: string,
    sandbox: boolean,
    private webhookToken: string,
  ) {
    this.base = sandbox
      ? 'https://sandbox.asaas.com/api/v3'
      : 'https://api.asaas.com/v3'
  }

  private async call(path: string, init?: RequestInit): Promise<Record<string, unknown>> {
    const res = await fetch(`${this.base}${path}`, {
      ...init,
      headers: {
        'Content-Type': 'application/json',
        access_token: this.apiKey,
        ...(init?.headers ?? {}),
      },
    })
    const text = await res.text()
    const json = text ? JSON.parse(text) : {}
    if (!res.ok) {
      throw new Error(`Asaas ${path} falhou: ${res.status} ${text}`)
    }
    return json
  }

  async ensureCustomer(c: CustomerInput): Promise<string> {
    // Reaproveita por externalReference (tenant_id) para não duplicar.
    if (c.externalRef) {
      const found = await this.call(
        `/customers?externalReference=${encodeURIComponent(c.externalRef)}`,
      )
      const data = (found.data as Array<{ id: string }>) ?? []
      if (data.length > 0) return data[0].id
    }
    const created = await this.call('/customers', {
      method: 'POST',
      body: JSON.stringify({
        name: c.name,
        email: c.email,
        phone: c.phone,
        cpfCnpj: c.cpfCnpj,
        externalReference: c.externalRef,
      }),
    })
    return created.id as string
  }

  async createSubscription(i: SubscriptionInput): Promise<SubscriptionResult> {
    const sub = await this.call('/subscriptions', {
      method: 'POST',
      body: JSON.stringify({
        customer: i.customerId,
        billingType: i.billingType,
        value: i.value,
        nextDueDate: i.nextDueDate,
        cycle: i.cycle,
        description: i.description,
      }),
    })
    return { subscriptionId: sub.id as string, status: (sub.status as string) ?? 'ACTIVE' }
  }

  async getSubscription(id: string): Promise<SubscriptionResult> {
    const sub = await this.call(`/subscriptions/${id}`)
    return { subscriptionId: sub.id as string, status: sub.status as string }
  }

  async cancelSubscription(id: string): Promise<void> {
    await this.call(`/subscriptions/${id}`, { method: 'DELETE' })
  }

  async createPixCharge(i: PixChargeInput): Promise<PixChargeResult> {
    const pay = await this.call('/payments', {
      method: 'POST',
      body: JSON.stringify({
        customer: i.customerId,
        billingType: 'PIX',
        value: i.value,
        dueDate: i.dueDate,
        description: i.description,
        externalReference: i.externalRef,
      }),
    })
    const id = pay.id as string
    // QR Code/copia-e-cola do Pix
    const qr = await this.call(`/payments/${id}/pixQrCode`)
    return {
      chargeId: id,
      status: pay.status as string,
      pixCopiaECola: qr.payload as string | undefined,
      pixQrCodeBase64: qr.encodedImage as string | undefined,
    }
  }

  parseWebhook(headers: Headers, body: unknown): WebhookEvent {
    // Asaas envia o token configurado no header 'asaas-access-token'.
    const token = headers.get('asaas-access-token')
    if (!this.webhookToken || token !== this.webhookToken) {
      throw new Error('webhook_unauthorized')
    }
    const b = (body ?? {}) as Record<string, unknown>
    const payment = (b.payment ?? {}) as Record<string, unknown>
    return {
      event: b.event as string,
      paymentStatus: payment.status as string | undefined,
      subscriptionId: payment.subscription as string | undefined,
      chargeId: payment.id as string | undefined,
      externalRef: payment.externalReference as string | undefined,
      raw: b,
    }
  }
}

// Fábrica: escolhe o provedor por env (default asaas). Outros entram aqui.
export function getProvider(): PaymentProvider {
  const which = Deno.env.get('PAYMENT_PROVIDER') ?? 'asaas'
  if (which === 'asaas') {
    const key = Deno.env.get('ASAAS_API_KEY')
    if (!key) throw new Error('ASAAS_API_KEY ausente.')
    const sandbox = (Deno.env.get('ASAAS_ENV') ?? 'sandbox') !== 'production'
    const webhookToken = Deno.env.get('ASAAS_WEBHOOK_TOKEN') ?? ''
    return new AsaasProvider(key, sandbox, webhookToken)
  }
  throw new Error(`Provedor de pagamento não suportado: ${which}`)
}

// Tipos do Deno global (ambiente Edge Function).
declare const Deno: { env: { get(k: string): string | undefined } }
