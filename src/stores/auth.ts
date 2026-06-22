import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase'
import type { MembershipRole, Tenant } from '@/types/database.types'

// Estado de autenticação + contexto de tenant/role.
// A role é a fonte para a navegação role-aware (§12), MAS a barreira real é
// a RLS no banco — a UI só reflete o que a policy já permite.
export const useAuthStore = defineStore('auth', () => {
  const session = ref<Session | null>(null)
  const tenant = ref<Tenant | null>(null)
  const role = ref<MembershipRole | null>(null)
  const loading = ref(true)
  // true quando o tenant ainda não tem serviços/profissionais (setup wizard §8.4)
  const needsOnboarding = ref(false)
  // estado de assinatura/trial do tenant
  const billing = ref<{ status: string; trial_ends_at: string | null } | null>(null)

  const isAuthenticated = computed(() => !!session.value)
  const isOwner = computed(() => role.value === 'owner')
  const hasTenant = computed(() => !!tenant.value)

  const trialEndsAt = computed(() =>
    billing.value?.trial_ends_at ? new Date(billing.value.trial_ends_at) : null,
  )
  const trialDaysLeft = computed(() => {
    if (billing.value?.status !== 'trial' || !trialEndsAt.value) return null
    const ms = trialEndsAt.value.getTime() - Date.now()
    return Math.max(0, Math.ceil(ms / 86_400_000))
  })
  // Acesso liberado se assinatura ativa OU trial ainda válido. Sem billing
  // (caso raro) não bloqueia, para evitar trancar o usuário por engano.
  const accessBlocked = computed(() => {
    if (!hasTenant.value || !billing.value) return false
    const s = billing.value.status
    if (s === 'ativo') return false
    if (s === 'trial' && trialEndsAt.value && trialEndsAt.value.getTime() > Date.now()) return false
    return true
  })

  async function loadContext() {
    if (!session.value) {
      tenant.value = null
      role.value = null
      needsOnboarding.value = false
      billing.value = null
      return
    }
    // memberships + tenant via RLS (só retorna o que pertence ao usuário).
    const { data, error } = await supabase
      .from('memberships')
      .select('role, tenant:tenants(*)')
      .limit(1)
      .maybeSingle()

    if (!error && data) {
      role.value = data.role as MembershipRole
      tenant.value = (data as unknown as { tenant: Tenant }).tenant ?? null
    } else {
      role.value = null
      tenant.value = null
    }
    await refreshSetupState()
    await refreshBilling()
  }

  // Estado de assinatura/trial do tenant (o dono lê via RLS).
  async function refreshBilling() {
    if (!tenant.value) {
      billing.value = null
      return
    }
    const { data } = await supabase
      .from('tenant_billing')
      .select('status, trial_ends_at')
      .eq('tenant_id', tenant.value.id)
      .maybeSingle()
    billing.value = (data as { status: string; trial_ends_at: string | null } | null) ?? null
  }

  // Ativação do tenant: precisa de onboarding se for owner e ainda não houver
  // profissional ou serviço cadastrado. Contagem barata (head + count).
  async function refreshSetupState() {
    if (!tenant.value || role.value !== 'owner') {
      needsOnboarding.value = false
      return
    }
    const [{ count: profs }, { count: svcs }] = await Promise.all([
      supabase.from('professionals').select('id', { count: 'exact', head: true }).is('deleted_at', null),
      supabase.from('services').select('id', { count: 'exact', head: true }).is('deleted_at', null),
    ])
    needsOnboarding.value = (profs ?? 0) === 0 || (svcs ?? 0) === 0
  }

  async function init() {
    loading.value = true
    const { data } = await supabase.auth.getSession()
    session.value = data.session
    await loadContext()
    supabase.auth.onAuthStateChange((_event, s) => {
      session.value = s
      void loadContext()
    })
    loading.value = false
  }

  async function signInWithMagicLink(email: string) {
    return supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: `${window.location.origin}/app` },
    })
  }

  // Login Google (sem e-mail → sem rate limit do magic link). Redireciona de volta.
  async function signInWithGoogle() {
    return supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: `${window.location.origin}/app` },
    })
  }

  // Auto-criação do estabelecimento (novo cliente). Trial de 7 dias é iniciado
  // pelo trigger no banco. Recarrega o contexto após criar.
  async function createTenant(nome: string, slug: string, vertical: string) {
    const { error } = await supabase.rpc('create_tenant', {
      p_nome: nome,
      p_slug: slug,
      p_vertical: vertical,
    })
    if (error) throw error
    await loadContext()
  }

  async function signOut() {
    await supabase.auth.signOut()
    session.value = null
    tenant.value = null
    role.value = null
  }

  return {
    session,
    tenant,
    role,
    loading,
    needsOnboarding,
    billing,
    hasTenant,
    trialDaysLeft,
    accessBlocked,
    isAuthenticated,
    isOwner,
    init,
    loadContext,
    refreshSetupState,
    refreshBilling,
    signInWithMagicLink,
    signInWithGoogle,
    createTenant,
    signOut,
  }
})
