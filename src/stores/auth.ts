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

  const isAuthenticated = computed(() => !!session.value)
  const isOwner = computed(() => role.value === 'owner')

  async function loadContext() {
    if (!session.value) {
      tenant.value = null
      role.value = null
      needsOnboarding.value = false
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
    }
    await refreshSetupState()
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
    isAuthenticated,
    isOwner,
    init,
    loadContext,
    refreshSetupState,
    signInWithMagicLink,
    signOut,
  }
})
