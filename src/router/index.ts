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
    // Landing de aquisição (anúncios): mesma tela, copy de cadastro/teste grátis.
    {
      path: '/comecar',
      name: 'comecar',
      alias: ['/cadastro', '/signup'],
      component: () => import('@/views/auth/LoginView.vue'),
      meta: { public: true },
    },
    {
      path: '/criar-estabelecimento',
      name: 'criar-estabelecimento',
      component: () => import('@/views/auth/CriarEstabelecimentoView.vue'),
      meta: { requiresAuth: true },
    },
    {
      path: '/assinatura',
      name: 'assinatura',
      component: () => import('@/views/auth/AssinaturaView.vue'),
      meta: { requiresAuth: true },
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
        {
          path: 'financeiro',
          name: 'financeiro',
          component: () => import('@/views/app/FinanceiroView.vue'),
          meta: { ownerOnly: true },
        },
        { path: 'clientes', name: 'clientes', component: () => import('@/views/app/ClientesView.vue') },
        {
          path: 'lembretes',
          name: 'lembretes',
          component: () => import('@/views/app/LembretesView.vue'),
          meta: { ownerOnly: true },
        },
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
        { path: 'suporte', name: 'suporte', component: () => import('@/views/app/SuporteView.vue') },
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
  if ((to.name === 'login' || to.name === 'comecar') && auth.isAuthenticated) {
    return { name: 'agenda' }
  }
  if (to.meta.requiresAuth) {
    // 1) Autenticado mas sem estabelecimento → criar (self-serve).
    if (!auth.hasTenant && to.name !== 'criar-estabelecimento') {
      return { name: 'criar-estabelecimento' }
    }
    // 2) Trial expirado / sem assinatura ativa → paywall (interrompe o SaaS).
    if (auth.hasTenant && auth.accessBlocked && to.name !== 'assinatura') {
      return { name: 'assinatura' }
    }
    // 3) Tenant ativo mas sem setup → wizard de onboarding (§8.4).
    if (
      auth.hasTenant &&
      !auth.accessBlocked &&
      auth.needsOnboarding &&
      !['onboarding', 'assinatura'].includes(String(to.name))
    ) {
      return { name: 'onboarding' }
    }
  }
  // Rotas só de dono.
  if (to.meta.ownerOnly && !auth.isOwner) {
    return { name: 'agenda' }
  }
  return true
})

export default router
