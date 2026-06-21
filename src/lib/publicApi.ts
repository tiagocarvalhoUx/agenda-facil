import { supabase } from '@/lib/supabase'
import type {
  AvailableSlot,
  BookingResult,
  ManagedBooking,
  PublicEstablishment,
} from '@/types/database.types'

// Camada de acesso ao fluxo público. SÓ chama as RPCs SECURITY DEFINER —
// nunca lê tabelas direto. tenant_id jamais é enviado; só o slug.

export async function fetchEstablishment(slug: string): Promise<PublicEstablishment | null> {
  const { data, error } = await supabase.rpc('get_public_establishment', {
    p_tenant_slug: slug,
  })
  if (error) throw error
  return (data as PublicEstablishment | null) ?? null
}

export async function fetchSlots(params: {
  slug: string
  serviceId: string
  data: string // yyyy-mm-dd
  professionalId?: string | null
}): Promise<AvailableSlot[]> {
  const { data, error } = await supabase.rpc('get_available_slots', {
    p_tenant_slug: params.slug,
    p_service_id: params.serviceId,
    p_data: params.data,
    p_professional_id: params.professionalId ?? null,
  })
  if (error) throw error
  return (data as AvailableSlot[]) ?? []
}

export async function createBooking(params: {
  slug: string
  serviceId: string
  professionalId: string | null
  inicio: string // ISO
  nome: string
  telefone: string
  email: string
  consentimento: boolean
}): Promise<BookingResult> {
  const { data, error } = await supabase.rpc('create_booking', {
    p_tenant_slug: params.slug,
    p_service_id: params.serviceId,
    p_professional_id: params.professionalId,
    p_inicio: params.inicio,
    p_nome: params.nome,
    p_telefone: params.telefone,
    p_email: params.email,
    p_consentimento: params.consentimento,
    p_ip: null, // IP real é resolvido por Edge Function/proxy; null no cliente
  })
  if (error) throw error
  return data as BookingResult
}

// ----- Auto-gerenciamento por token (sem login) -----

export async function fetchBookingByToken(token: string): Promise<ManagedBooking | null> {
  const { data, error } = await supabase.rpc('get_booking_by_token', {
    p_manage_token: token,
  })
  if (error) throw error
  return (data as ManagedBooking | null) ?? null
}

export async function cancelBooking(token: string): Promise<void> {
  const { error } = await supabase.rpc('manage_booking', {
    p_manage_token: token,
    p_acao: 'cancelar',
    p_novo_inicio: null,
  })
  if (error) throw error
}

export async function rescheduleBooking(token: string, novoInicio: string): Promise<void> {
  const { error } = await supabase.rpc('manage_booking', {
    p_manage_token: token,
    p_acao: 'remarcar',
    p_novo_inicio: novoInicio,
  })
  if (error) throw error
}

// ----- Lista de espera -----

export async function joinWaitlist(params: {
  slug: string
  serviceId: string
  professionalId?: string | null
  nome: string
  contato: string
  janela?: Record<string, unknown> | null
}): Promise<string> {
  const { data, error } = await supabase.rpc('join_waitlist', {
    p_tenant_slug: params.slug,
    p_service_id: params.serviceId,
    p_nome: params.nome,
    p_contato: params.contato,
    p_professional_id: params.professionalId ?? null,
    p_janela: params.janela ?? null,
  })
  if (error) throw error
  return data as string
}
