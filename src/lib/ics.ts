// Gera um arquivo .ics para "Adicionar ao calendário" (ADENDO §15.1).

function toICSDate(iso: string): string {
  // YYYYMMDDTHHMMSSZ (UTC)
  return new Date(iso).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '')
}

export function buildICS(opts: {
  title: string
  inicio: string
  fim: string
  local?: string
  descricao?: string
}): string {
  const uid = `${Date.now()}@agenda-saas`
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Agenda SaaS//PT-BR//',
    'BEGIN:VEVENT',
    `UID:${uid}`,
    `DTSTAMP:${toICSDate(new Date().toISOString())}`,
    `DTSTART:${toICSDate(opts.inicio)}`,
    `DTEND:${toICSDate(opts.fim)}`,
    `SUMMARY:${opts.title}`,
    opts.local ? `LOCATION:${opts.local}` : '',
    opts.descricao ? `DESCRIPTION:${opts.descricao}` : '',
    'END:VEVENT',
    'END:VCALENDAR',
  ]
    .filter(Boolean)
    .join('\r\n')
}

export function downloadICS(filename: string, content: string): void {
  const blob = new Blob([content], { type: 'text/calendar;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}
