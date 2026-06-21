// Formatação BR (ADENDO §17): datas dd/mm, horas HH:mm (24h), preço em BRL.

const TZ = 'America/Sao_Paulo'

export function formatHora(iso: string): string {
  return new Intl.DateTimeFormat('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
    timeZone: TZ,
  }).format(new Date(iso))
}

export function formatData(iso: string): string {
  return new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    timeZone: TZ,
  }).format(new Date(iso))
}

export function formatDataLonga(iso: string | Date): string {
  return new Intl.DateTimeFormat('pt-BR', {
    weekday: 'long',
    day: '2-digit',
    month: 'long',
    timeZone: TZ,
  }).format(typeof iso === 'string' ? new Date(iso) : iso)
}

export function formatPreco(valor: number): string {
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(valor)
}

export function formatDuracao(min: number): string {
  if (min < 60) return `${min} min`
  const h = Math.floor(min / 60)
  const m = min % 60
  return m === 0 ? `${h}h` : `${h}h${m.toString().padStart(2, '0')}`
}

// yyyy-mm-dd a partir de um Date (para a RPC get_available_slots).
export function toDateParam(d: Date): string {
  return d.toISOString().slice(0, 10)
}
