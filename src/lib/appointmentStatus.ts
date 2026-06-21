import type { AppointmentStatus } from '@/types/database.types'

// Config de status do agendamento (ADENDO §13.2). Cor + ícone + rótulo —
// nunca só cor (daltonismo, §18). Reutilizado por StatusBadge e AppointmentCard.
export interface StatusConfig {
  label: string
  icon: string
  // classes utilitárias (mapeadas a tokens via tailwind.config)
  text: string
  bg: string
  bar: string // barra lateral do card na agenda
}

export const STATUS: Record<AppointmentStatus, StatusConfig> = {
  agendado: { label: 'Agendado', icon: '•', text: 'text-info', bg: 'bg-info/10', bar: 'bg-info' },
  confirmado: { label: 'Confirmado', icon: '✓', text: 'text-success', bg: 'bg-success/10', bar: 'bg-success' },
  cancelado: { label: 'Cancelado', icon: '✕', text: 'text-danger', bg: 'bg-danger/10', bar: 'bg-danger' },
  concluido: { label: 'Concluído', icon: '✓', text: 'text-text-muted', bg: 'bg-surface-2', bar: 'bg-text-muted' },
  no_show: { label: 'Não compareceu', icon: '⚠', text: 'text-warning', bg: 'bg-warning/10', bar: 'bg-warning' },
}
