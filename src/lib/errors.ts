// Traduz os códigos estáveis das RPCs (SQLSTATE P0001) para microcopy PT-BR
// (ADENDO §17): voz ativa, diz o que houve e como resolver.

const MESSAGES: Record<string, string> = {
  rate_limited: 'Muitas tentativas em pouco tempo. Tente novamente em alguns minutos.',
  slot_taken: 'Esse horário acabou de ser ocupado. Escolha outro:',
  consent_required: 'É preciso autorizar o uso dos dados para concluir o agendamento.',
  invalid_phone: 'Telefone inválido. Use DDD + número.',
  invalid_email: 'E-mail inválido. Confira o endereço.',
  past_slot: 'Esse horário já passou. Escolha um horário futuro.',
  service_unavailable: 'Esse serviço não está mais disponível.',
  professional_unavailable: 'Profissional indisponível. Escolha outro.',
  outside_hours: 'Esse horário está fora do expediente.',
  tenant_not_found: 'Estabelecimento não encontrado.',
  forbidden: 'Você não tem permissão para esta ação.',
}

export function mapBookingError(message: string | undefined): string {
  if (!message) return 'Algo deu errado. Tente novamente.'
  for (const key of Object.keys(MESSAGES)) {
    if (message.includes(key)) return MESSAGES[key]
  }
  return 'Algo deu errado. Tente novamente.'
}
