import { supabase } from '@/lib/supabase'
import type { AvailableSlot, PublicEstablishment } from '@/types/database.types'

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
}): Promise<string> {
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
  return data as string
}
