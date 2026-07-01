// Utilidades dos Lembretes via WhatsApp (envio MANUAL por link wa.me).
// Envio manual = abre o WhatsApp do dono já com a mensagem pronta pro cliente;
// sem API oficial e sem custo. A personalização da mensagem e o rastreio de
// quais lembretes já foram enviados ficam NO DISPOSITIVO (localStorage por
// tenant) — a tabela `reminders` é de escrita exclusiva do servidor (§5.2),
// então o painel não grava nela; ela alimenta apenas a aba de automáticos.

export const VARIAVEIS = ['nome', 'periodo', 'quando', 'data', 'hora', 'profissional', 'servico'] as const
export type Variavel = (typeof VARIAVEIS)[number]

export const MENSAGEM_PADRAO =
  'Olá {nome}! Lembrando do seu agendamento em {data} às {hora} com {profissional}. Por favor, confirme sua presença respondendo SIM.'

export interface TemplateVars {
  nome: string
  periodo: string
  quando: string
  data: string
  hora: string
  profissional: string
  servico: string
}

// Troca {chave} pelos valores; deixa intacta qualquer chave desconhecida.
export function renderTemplate(tpl: string, vars: TemplateVars): string {
  return tpl.replace(/\{(\w+)\}/g, (m, k: string) => (k in vars ? String(vars[k as keyof TemplateVars]) : m))
}

// Monta o link wa.me. Normaliza o telefone BR: só dígitos e com DDI 55.
// Números nacionais (10 ou 11 dígitos, com DDD) recebem o 55; quem já vem
// com DDI (12/13 dígitos) é mantido como está.
export function waLink(telefone: string, texto: string): string {
  let d = (telefone || '').replace(/\D/g, '')
  if (d.length === 10 || d.length === 11) d = '55' + d
  return `https://wa.me/${d}?text=${encodeURIComponent(texto)}`
}

export function temTelefone(telefone: string | null | undefined): boolean {
  return (telefone || '').replace(/\D/g, '').length >= 10
}

// --------- Persistência local por tenant ---------

const tplKey = (t: string) => `lembrete_msg_${t}`

export function loadTemplate(tenantId: string): string {
  return localStorage.getItem(tplKey(tenantId)) || MENSAGEM_PADRAO
}

export function saveTemplate(tenantId: string, tpl: string): void {
  localStorage.setItem(tplKey(tenantId), tpl)
}

// Rastreio de envios manuais: { [appointmentId]: { enviadoAt } }.
const logKey = (t: string) => `lembrete_log_${t}`
export type SentLog = Record<string, { enviadoAt: string }>

export function loadSentLog(tenantId: string): SentLog {
  try {
    return JSON.parse(localStorage.getItem(logKey(tenantId)) || '{}') as SentLog
  } catch {
    return {}
  }
}

export function markSent(tenantId: string, appointmentId: string): SentLog {
  const log = loadSentLog(tenantId)
  log[appointmentId] = { enviadoAt: new Date().toISOString() }
  localStorage.setItem(logKey(tenantId), JSON.stringify(log))
  return log
}

export function clearSent(tenantId: string, appointmentId: string): SentLog {
  const log = loadSentLog(tenantId)
  delete log[appointmentId]
  localStorage.setItem(logKey(tenantId), JSON.stringify(log))
  return log
}
