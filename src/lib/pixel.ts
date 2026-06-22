// Wrapper fino sobre o Meta Pixel (fbq), carregado no index.html. Centraliza os
// eventos de conversão para não espalhar `window.fbq` com cast pelo código e
// para virar no-op quando o pixel não está configurado (dev, ID em branco).

type Fbq = (action: 'track' | 'trackCustom', event: string, params?: Record<string, unknown>) => void

function fbq(): Fbq | null {
  const fn = (window as unknown as { fbq?: Fbq }).fbq
  return typeof fn === 'function' ? fn : null
}

/** Evento padrão da Meta. Silencioso se o pixel não estiver carregado. */
export function trackPixel(event: string, params?: Record<string, unknown>): void {
  fbq()?.('track', event, params)
}

/** Novo estabelecimento criado (fim do cadastro self-serve). */
export function trackCompleteRegistration(): void {
  trackPixel('CompleteRegistration')
}

/** Assinatura paga confirmada. `value` em BRL. */
export function trackSubscribe(value: number): void {
  trackPixel('Subscribe', { value, currency: 'BRL', predicted_ltv: value * 12 })
}
