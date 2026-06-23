import { supabase } from '@/lib/supabase'

// Camada de assinatura do SaaS. O dono LÊ o próprio billing via RLS; a criação
// passa pela Edge Function `payments` (que valida posse e fala com o Asaas —
// a API key fica só no servidor, §5.2).

const FN_BASE = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/payments`

export interface TenantBilling {
  status: 'inativo' | 'trial' | 'ativo' | 'atrasado' | 'cancelado'
  plano: string | null
  valor: number | null
  ciclo: string | null
  billing_type: string | null
  proximo_vencimento: string | null
}

export async function fetchBilling(tenantId: string): Promise<TenantBilling | null> {
  const { data } = await supabase
    .from('tenant_billing')
    .select('status, plano, valor, ciclo, billing_type, proximo_vencimento')
    .eq('tenant_id', tenantId)
    .maybeSingle()
  return (data as TenantBilling | null) ?? null
}

export async function subscribe(params: {
  tenantId: string
  cpfCnpj: string
  billingType: 'PIX' | 'CREDIT_CARD'
}): Promise<{ subscriptionId: string; status: string }> {
  const { data } = await supabase.auth.getSession()
  const token = data.session?.access_token
  const res = await fetch(`${FN_BASE}/subscribe`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
      apikey: import.meta.env.VITE_SUPABASE_ANON_KEY,
    },
    body: JSON.stringify({
      tenant_id: params.tenantId,
      plano: 'Mensal',
      valor: 1.0, // TESTE TEMPORÁRIO — voltar para 49.90 após validar o Pix

      ciclo: 'MONTHLY',
      billingType: params.billingType,
      cpfCnpj: params.cpfCnpj,
    }),
  })
  const json = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(json.error || 'subscribe_failed')
  return json
}
