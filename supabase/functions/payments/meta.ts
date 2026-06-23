// Meta Conversions API (CAPI) — eventos server-side, à prova de bloqueador de
// anúncio e de o cliente fechar o site (caso típico do Pix). Usado no webhook
// do provedor para disparar o Subscribe REAL, só quando o pagamento confirma.
//
// Config (secrets, NUNCA no frontend):
//   supabase secrets set META_PIXEL_ID=...        # mesmo id do Pixel do site
//   supabase secrets set META_CAPI_TOKEN=...       # Gerenciador de Eventos →
//                                                  # Configurações → Gerar token
// Sem os secrets, vira no-op (não quebra o pagamento).

const GRAPH_VERSION = 'v21.0'

// SHA-256 hex (lowercase, trim) — formato exigido pela Meta para PII.
async function sha256(input: string): Promise<string> {
  const data = new TextEncoder().encode(input.trim().toLowerCase())
  const digest = await crypto.subtle.digest('SHA-256', data)
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

export async function trackSubscribeCAPI(opts: {
  email?: string
  value: number
  currency?: string
  eventId?: string // dedupe com o Pixel, se um dia disparar nos dois lados
}): Promise<void> {
  const pixelId = Deno.env.get('META_PIXEL_ID')
  const token = Deno.env.get('META_CAPI_TOKEN')
  if (!pixelId || !token) return // CAPI não configurada → no-op

  const user_data: Record<string, unknown> = {}
  if (opts.email) user_data.em = [await sha256(opts.email)]

  const payload = {
    data: [
      {
        event_name: 'Subscribe',
        event_time: Math.floor(Date.now() / 1000),
        action_source: 'system_generated', // originado no webhook do provedor
        event_id: opts.eventId, // idempotência/dedupe do lado da Meta
        user_data,
        custom_data: {
          value: opts.value,
          currency: opts.currency ?? 'BRL',
          predicted_ltv: opts.value * 12,
        },
      },
    ],
  }

  const res = await fetch(
    `https://graph.facebook.com/${GRAPH_VERSION}/${pixelId}/events?access_token=${encodeURIComponent(token)}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    },
  )
  if (!res.ok) {
    // Não lança: telemetria não pode derrubar o webhook (o billing já foi gravado).
    console.error('Meta CAPI Subscribe falhou:', res.status, await res.text().catch(() => ''))
  }
}

declare const Deno: { env: { get(k: string): string | undefined } }
