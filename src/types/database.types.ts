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

export interface Tenant {
  id: string
  nome: string
  slug: string
  plano: string
  status: 'ativo' | 'suspenso' | 'cancelado'
  accent_color: string | null
  vertical: 'clinica' | 'salao' | 'outro' | null
  timezone: string
  created_at: string
}

export interface Professional {
  id: string
  tenant_id: string
  user_id: string | null
  nome: string
  ativo: boolean
  deleted_at: string | null
  created_at: string
}

export interface Service {
  id: string
  tenant_id: string
  nome: string
  duracao_min: number
  preco: number
  ativo: boolean
  deleted_at: string | null
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
  created_by: string | null
  deleted_at: string | null
  created_at: string
}

// Estrutura pública retornada por get_public_establishment
export interface PublicEstablishment {
  nome: string
  slug: string
  accent_color: string | null
  vertical: 'clinica' | 'salao' | 'outro' | null
  timezone: string
  servicos: { id: string; nome: string; duracao_min: number; preco: number }[]
  profissionais: { id: string; nome: string }[]
}

export interface AvailableSlot {
  inicio_at: string
  fim_at: string
  professional_id: string
}

// Tipagem mínima do Database para o supabase-js. As RPCs são tipadas
// pontualmente nos call-sites; tabelas com shape suficiente para o painel.
export interface Database {
  public: {
    Tables: {
      tenants: { Row: Tenant; Insert: Partial<Tenant>; Update: Partial<Tenant> }
      professionals: { Row: Professional; Insert: Partial<Professional>; Update: Partial<Professional> }
      services: { Row: Service; Insert: Partial<Service>; Update: Partial<Service> }
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
