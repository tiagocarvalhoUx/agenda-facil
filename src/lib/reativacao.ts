import { supabase } from '@/lib/supabase'
import type { Campaign } from '@/types/database.types'

// Camada de dados da Reativação por IA (Fase 1). Segmentação e stats vêm
// de RPCs SECURITY DEFINER; a geração de mensagem passa pela Edge Function
// `ai-campaign` (a API key da IA fica só no servidor, §5.2). O disparo é
// manual via wa.me, reaproveitando @/lib/whatsapp.

const FN_BASE = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/ai-campaign`

export const DIAS_OPCOES = [30, 60, 90, 180] as const

export interface ClienteInativo {
  customer_id: string
  nome: string
  telefone: string
  ultima_visita: string
  total_visitas: number
  consentiu: boolean
}

export interface CampaignStats {
  campaign_id: string
  total: number
  enviados: number
  convertidos: number
}

export interface RecipientRow {
  id: string
  customer_id: string
  enviado_at: string | null
  customer: { nome: string; telefone: string } | null
}

export async function fetchInativos(tenantId: string, dias: number): Promise<ClienteInativo[]> {
  const { data, error } = await supabase.rpc('reativacao_inactive_customers', {
    p_tenant: tenantId,
    p_dias: dias,
  })
  if (error) throw error
  return (data as ClienteInativo[]) ?? []
}

export async function fetchCampanhas(tenantId: string): Promise<Campaign[]> {
  const { data, error } = await supabase
    .from('campaigns')
    .select('*')
    .eq('tenant_id', tenantId)
    .order('created_at', { ascending: false })
  if (error) throw error
  return (data as Campaign[]) ?? []
}

export async function fetchStats(tenantId: string): Promise<Record<string, CampaignStats>> {
  const { data, error } = await supabase.rpc('reativacao_campaign_stats', { p_tenant: tenantId })
  if (error) throw error
  const map: Record<string, CampaignStats> = {}
  for (const s of (data as CampaignStats[]) ?? []) map[s.campaign_id] = s
  return map
}

export async function fetchRecipients(campaignId: string): Promise<RecipientRow[]> {
  const { data, error } = await supabase
    .from('campaign_recipients')
    .select('id, customer_id, enviado_at, customer:customers(nome, telefone)')
    .eq('campaign_id', campaignId)
    .order('created_at')
  if (error) throw error
  return (data as unknown as RecipientRow[]) ?? []
}

export async function criarCampanha(params: {
  tenantId: string
  nome: string
  objetivo: string
  mensagem: string
  diasInatividade: number
  customerIds: string[]
}): Promise<Campaign> {
  const { data: userData } = await supabase.auth.getUser()
  const { data, error } = await supabase
    .from('campaigns')
    .insert({
      tenant_id: params.tenantId,
      nome: params.nome,
      objetivo: params.objetivo,
      mensagem: params.mensagem,
      dias_inatividade: params.diasInatividade,
      created_by: userData.user?.id ?? null,
    })
    .select('*')
    .single()
  if (error) throw error
  const campaign = data as Campaign

  const rows = params.customerIds.map((cid) => ({
    campaign_id: campaign.id,
    tenant_id: params.tenantId,
    customer_id: cid,
  }))
  const { error: recErr } = await supabase.from('campaign_recipients').insert(rows)
  if (recErr) throw recErr
  return campaign
}

export async function marcarEnviado(recipientId: string): Promise<void> {
  const { error } = await supabase
    .from('campaign_recipients')
    .update({ enviado_at: new Date().toISOString() })
    .eq('id', recipientId)
  if (error) throw error
}

// Chama a Edge Function que fala com a IA. Devolve 3 variações de mensagem
// (com a variável {nome}) para o dono escolher/editar.
export async function gerarMensagensIA(params: {
  tenantId: string
  objetivo: string
  tom: string
  oferta: string
  diasInatividade: number
}): Promise<string[]> {
  const { data } = await supabase.auth.getSession()
  const token = data.session?.access_token
  const res = await fetch(FN_BASE, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
      apikey: import.meta.env.VITE_SUPABASE_ANON_KEY,
    },
    body: JSON.stringify({
      tenant_id: params.tenantId,
      objetivo: params.objetivo,
      tom: params.tom,
      oferta: params.oferta,
      dias_inatividade: params.diasInatividade,
    }),
  })
  const json = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(json.error || 'ai_failed')
  return (json.mensagens as string[]) ?? []
}
