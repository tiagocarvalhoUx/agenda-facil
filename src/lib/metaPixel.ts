// Eventos do Meta Pixel (navegador). O funil real do Agenda Fácil:
//   ViewContent      → abriu a landing de aquisição (topo do funil, aqui)
//   Lead             → clicou num CTA "Começar grátis" da landing (aqui)
//   StartTrial       → estabelecimento criado + trial de 7 dias (aqui)
//   InitiateCheckout → clicou em "Assinar" e foi pro checkout (aqui)
//   Subscribe        → pagamento CONFIRMADO pelo Asaas → CAPI no webhook (servidor)
//
// ViewContent/Lead existem para dar VOLUME de sinal ao algoritmo: StartTrial e
// Subscribe são raros demais para tirar a campanha da fase de aprendizado. Com
// verba pequena, otimize a campanha por Lead (evento mais frequente).
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

// Abriu a landing de aquisição (topo do funil). Sinal de alto volume.
export const trackViewContent = () =>
  track('ViewContent', { content_name: 'landing', content_category: 'aquisicao' })

// Clicou num CTA "Começar grátis" na landing (intenção). `origem` identifica
// qual CTA converteu melhor (hero, preço, rodapé…).
export const trackLead = (origem: string) =>
  track('Lead', { content_name: `cta_${origem}`, value: 79.9, currency: 'BRL' })

// Estabelecimento criado + trial de 7 dias iniciado.
export const trackStartTrial = () =>
  track('StartTrial', { value: 79.9, currency: 'BRL', predicted_ltv: 79.9 * 12 })

// Clicou em "Assinar" e seguiu para o checkout.
export const trackInitiateCheckout = (metodo: 'pix' | 'cartao') =>
  track('InitiateCheckout', { value: 79.9, currency: 'BRL', content_name: `plano_${metodo}` })

export {}
