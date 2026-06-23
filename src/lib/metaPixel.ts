// Eventos do Meta Pixel (navegador). O funil real do Agenda Fácil:
//   StartTrial       → estabelecimento criado + trial de 7 dias (aqui)
//   InitiateCheckout → clicou em "Assinar" e foi pro checkout (aqui)
//   Subscribe        → pagamento CONFIRMADO pelo Asaas → CAPI no webhook (servidor)
//
// Subscribe NÃO sai daqui de propósito: no Pix o cliente paga no app do banco,
// pode nem estar com o site aberto quando confirma. Disparar no clique otimizaria
// a campanha para "clicador", não "pagante". A conversão real sai do servidor
// (Conversions API), em supabase/functions/payments.

declare global {
  interface Window {
    fbq?: (...args: unknown[]) => void
  }
}

const track = (event: string, params?: Record<string, unknown>) => {
  window.fbq?.('track', event, params)
}

export const trackPageView = () => track('PageView')

// Estabelecimento criado + trial de 7 dias iniciado.
export const trackStartTrial = () =>
  track('StartTrial', { value: 49, currency: 'BRL', predicted_ltv: 49 * 12 })

// Clicou em "Assinar" e seguiu para o checkout.
export const trackInitiateCheckout = (metodo: 'pix' | 'cartao') =>
  track('InitiateCheckout', { value: 49, currency: 'BRL', content_name: `plano_${metodo}` })

export {}
