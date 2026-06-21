// Camada de provedor de lembretes (§6/§87): interface única.
// MVP implementa e-mail (Resend); WhatsApp/SMS ficam plugáveis.

export interface ReminderPayload {
  destino: string // e-mail ou telefone
  estabelecimento: string
  servico: string
  quando: string // texto já formatado pt-BR
  profissional?: string
}

export interface ReminderProvider {
  canal: 'email' | 'whatsapp' | 'sms'
  send(payload: ReminderPayload): Promise<void>
}

// ---- Resend (e-mail) — MVP ----
export class ResendProvider implements ReminderProvider {
  canal = 'email' as const
  constructor(
    private apiKey: string,
    private from: string,
  ) {}

  async send(p: ReminderPayload): Promise<void> {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: this.from,
        to: p.destino,
        subject: `Lembrete: ${p.servico} em ${p.estabelecimento}`,
        html: `
          <p>Olá! Este é um lembrete do seu agendamento.</p>
          <p><strong>${p.servico}</strong> em <strong>${p.estabelecimento}</strong></p>
          <p>Quando: <strong>${p.quando}</strong></p>
          ${p.profissional ? `<p>Com: ${p.profissional}</p>` : ''}
          <p>Até logo!</p>
        `,
      }),
    })
    if (!res.ok) {
      throw new Error(`Resend falhou: ${res.status} ${await res.text()}`)
    }
  }
}

// ---- WhatsApp (placeholder plugável) ----
export class WhatsAppProvider implements ReminderProvider {
  canal = 'whatsapp' as const
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  async send(_p: ReminderPayload): Promise<void> {
    throw new Error('WhatsApp provider ainda não implementado (plugável no roadmap).')
  }
}

export function getProvider(canal: string): ReminderProvider {
  if (canal === 'email') {
    const key = Deno.env.get('RESEND_API_KEY')
    const from = Deno.env.get('REMINDER_FROM_EMAIL')
    if (!key || !from) throw new Error('RESEND_API_KEY/REMINDER_FROM_EMAIL ausentes.')
    return new ResendProvider(key, from)
  }
  if (canal === 'whatsapp') return new WhatsAppProvider()
  throw new Error(`Canal não suportado: ${canal}`)
}
