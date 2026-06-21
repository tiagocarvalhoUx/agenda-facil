import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    // ----- Auto-gerenciamento por token (sem login) -----
    {
      path: '/b/:token',
      name: 'manage-booking',
      component: () => import('@/views/public/ManageBooking.vue'),
      meta: { public: true },
    },

    // ----- Público (cliente final): funil linear sem navegação global -----
    {
      path: '/:slug',
      name: 'public-booking',
      component: () => import('@/views/public/PublicBooking.vue'),
      meta: { public: true },
    },

    // ----- Autenticação -----
    {
      path: '/login',
      name: 'login',
      component: () => import('@/views/auth/LoginView.vue'),
      meta: { public: true },
    },

    // ----- Painel autenticado -----
    {
      path: '/app',
      component: () => import('@/views/app/AppLayout.vue'),
      meta: { requiresAuth: true },
      children: [
        { path: '', redirect: { name: 'agenda' } },
        { path: 'agenda', name: 'agenda', component: () => import('@/views/app/AgendaView.vue') },
        {
          path: 'dashboard',
          name: 'dashboard',
          component: () => import('@/views/app/DashboardView.vue'),
          meta: { ownerOnly: true },
        },
        { path: 'clientes', name: 'clientes', component: () => import('@/views/app/ClientesView.vue') },
        { path: 'bloqueios', name: 'bloqueios', component: () => import('@/views/app/BloqueiosView.vue') },
        {
          path: 'servicos',
          name: 'servicos',
          component: () => import('@/views/app/ServicosView.vue'),
          meta: { ownerOnly: true },
        },
        {
          path: 'profissionais',
          name: 'profissionais',
          component: () => import('@/views/app/ProfissionaisView.vue'),
          meta: { ownerOnly: true },
        },
        {
          path: 'configuracoes',
          name: 'configuracoes',
          component: () => import('@/views/app/ConfiguracoesView.vue'),
          meta: { ownerOnly: true },
        },
        {
          path: 'onboarding',
          name: 'onboarding',
          component: () => import('@/views/app/OnboardingView.vue'),
          meta: { ownerOnly: true },
        },
      ],
    },

    { path: '/', redirect: '/login' },
  ],
})

// Guard: protege rotas no cliente (a barreira real é a RLS no servidor).
router.beforeEach(async (to) => {
  const auth = useAuthStore()
  if (auth.loading) await auth.init()

  if (to.meta.requiresAuth && !auth.isAuthenticated) {
    return { name: 'login' }
  }
  if (to.meta.ownerOnly && !auth.isOwner) {
    return { name: 'agenda' }
  }
  if (to.name === 'login' && auth.isAuthenticated) {
    return { name: 'agenda' }
  }
  // Primeiro acesso do dono sem setup → wizard de onboarding (§8.4).
  if (to.meta.requiresAuth && auth.needsOnboarding && to.name !== 'onboarding') {
    return { name: 'onboarding' }
  }
  return true
})

export default router
