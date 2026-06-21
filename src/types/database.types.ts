// Tipos do banco. Em projeto conectado, regenerar com:
//   npm run gen:types   (supabase gen types typescript --local)
// Mantidos à mão aqui para o MVP refletir o schema das migrations.

export type AppointmentStatus =
  | 'agendado'
  | 'confirmado'
  | 'cancelado'
  | 'concluido'
  | 'no_show'

export type MembershipRole = 'owner' | 'staff'
export type ReminderChannel = 'email' | 'whatsapp' | 'sms'
export type DepositoStatus = 'nao_exigido' | 'pendente' | 'pago' | 'estornado'

// Política de agendamento por tenant (booking_policy jsonb).
export interface BookingPolicy {
  auto_confirmar: boolean
  antecedencia_min_horas: number
  antecedencia_max_dias: number
  cancelamento_ate_horas: number
}

export interface Tenant {
  id: string
  nome: string
  slug: string
  plano: string
  status: 'ativo' | 'suspenso' | 'cancelado'
  accent_color: string | null
  brand_logo_url: string | null
  vertical: 'clinica' | 'salao' | 'outro' | null
  timezone: string
  booking_policy: BookingPolicy
  created_at: string
}

export interface Professional {
  id: string
  tenant_id: string
  user_id: string | null
  nome: string
  avatar_url: string | null
  bio: string | null
  ativo: boolean
  deleted_at: string | null
  created_at: string
}

export interface Service {
  id: string
  tenant_id: string
  nome: string
  categoria: string | null
  duracao_min: number
  buffer_min: number
  preco: number
  exige_deposito: boolean
  deposito_valor: number
  ativo: boolean
  deleted_at: string | null
  created_at: string
}

export interface ProfessionalService {
  tenant_id: string
  professional_id: string
  service_id: string
  created_at: string
}

export interface TimeBlock {
  id: string
  tenant_id: string
  professional_id: string
  inicio_at: string
  fim_at: string
  motivo: string | null
  created_at: string
}

export interface WaitlistEntry {
  id: string
  tenant_id: string
  service_id: string
  professional_id: string | null
  customer_nome: string
  customer_contato: string
  janela_desejada: Record<string, unknown> | null
  status: 'aguardando' | 'notificado' | 'convertido' | 'cancelado'
  notificado_at: string | null
  created_at: string
}

export interface WorkingHour {
  id: string
  tenant_id: string
  professional_id: string
  weekday: number
  hora_inicio: string
  hora_fim: string
}

export interface Customer {
  id: string
  tenant_id: string
  nome: string
  telefone: string
  email: string | null
  notas: string | null
  tags: string[]
  no_show_count: number
  consentimento_lgpd_at: string | null
  anonimizado_at: string | null
  deleted_at: string | null
  created_at: string
}

export interface Appointment {
  id: string
  tenant_id: string
  professional_id: string
  service_id: string
  customer_id: string
  inicio_at: string
  fim_at: string
  status: AppointmentStatus
  origem: 'painel' | 'publico'
  observacao: string | null
  manage_token: string
  deposito_status: DepositoStatus
  created_by: string | null
  deleted_at: string | null
  created_at: string
}

// Serviço como exposto na página pública (inclui mapa de profissionais).
export interface PublicService {
  id: string
  nome: string
  categoria: string | null
  duracao_min: number
  buffer_min: number
  preco: number
  exige_deposito: boolean
  deposito_valor: number
  profissionais: string[] // ids; vazio = todos realizam
}

export interface PublicProfessional {
  id: string
  nome: string
  avatar_url: string | null
  bio: string | null
}

// Estrutura pública retornada por get_public_establishment
export interface PublicEstablishment {
  nome: string
  slug: string
  accent_color: string | null
  brand_logo_url: string | null
  vertical: 'clinica' | 'salao' | 'outro' | null
  timezone: string
  booking_policy: {
    antecedencia_min_horas: number
    antecedencia_max_dias: number
    cancelamento_ate_horas: number
  }
  servicos: PublicService[]
  profissionais: PublicProfessional[]
}

export interface AvailableSlot {
  inicio_at: string
  fim_at: string
  professional_id: string
}

// Retorno de create_booking (v2): id + token de gestão + estado.
export interface BookingResult {
  appointment_id: string
  manage_token: string
  status: AppointmentStatus
  deposito_status: DepositoStatus
  inicio_at: string
  fim_at: string
}

// Retorno de get_booking_by_token — tela pública de gestão do agendamento.
export interface ManagedBooking {
  appointment_id: string
  status: AppointmentStatus
  inicio_at: string
  fim_at: string
  deposito_status: DepositoStatus
  service_id: string
  professional_id: string
  estabelecimento: string
  slug: string
  accent_color: string | null
  brand_logo_url: string | null
  servico: string
  duracao_min: number
  profissional: string
  cliente_nome: string
  cancelamento_ate_horas: number
  pode_gerenciar: boolean
}

// Tipagem mínima do Database para o supabase-js. As RPCs são tipadas
// pontualmente nos call-sites; tabelas com shape suficiente para o painel.
export interface Database {
  public: {
    Tables: {
      tenants: { Row: Tenant; Insert: Partial<Tenant>; Update: Partial<Tenant> }
      professionals: { Row: Professional; Insert: Partial<Professional>; Update: Partial<Professional> }
      services: { Row: Service; Insert: Partial<Service>; Update: Partial<Service> }
      professional_services: { Row: ProfessionalService; Insert: Partial<ProfessionalService>; Update: Partial<ProfessionalService> }
      time_blocks: { Row: TimeBlock; Insert: Partial<TimeBlock>; Update: Partial<TimeBlock> }
      waitlist: { Row: WaitlistEntry; Insert: Partial<WaitlistEntry>; Update: Partial<WaitlistEntry> }
      working_hours: { Row: WorkingHour; Insert: Partial<WorkingHour>; Update: Partial<WorkingHour> }
      customers: { Row: Customer; Insert: Partial<Customer>; Update: Partial<Customer> }
      appointments: { Row: Appointment; Insert: Partial<Appointment>; Update: Partial<Appointment> }
    }
    Views: Record<string, never>
    Functions: Record<string, never>
    Enums: {
      appointment_status: AppointmentStatus
      membership_role: MembershipRole
      reminder_channel: ReminderChannel
    }
  }
}
