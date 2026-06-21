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
  too_soon: 'Esse horário está dentro da antecedência mínima. Escolha um mais distante.',
  too_far: 'Esse horário está além do período permitido para agendamento.',
  booking_not_found: 'Não encontramos esse agendamento. Verifique o link.',
  booking_not_manageable: 'Esse agendamento não pode mais ser alterado.',
  cancel_window_closed: 'O prazo para cancelar ou remarcar já passou.',
  missing_new_time: 'Escolha um novo horário para remarcar.',
  invalid_action: 'Ação inválida.',
  invalid_input: 'Preencha os dados corretamente.',
}

export function mapBookingError(message: string | undefined): string {
  if (!message) return 'Algo deu errado. Tente novamente.'
  for (const key of Object.keys(MESSAGES)) {
    if (message.includes(key)) return MESSAGES[key]
  }
  return 'Algo deu errado. Tente novamente.'
}
