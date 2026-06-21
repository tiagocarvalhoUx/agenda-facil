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

  const isAuthenticated = computed(() => !!session.value)
  const isOwner = computed(() => role.value === 'owner')

  async function loadContext() {
    if (!session.value) {
      tenant.value = null
      role.value = null
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
    isAuthenticated,
    isOwner,
    init,
    loadContext,
    signInWithMagicLink,
    signOut,
  }
})
