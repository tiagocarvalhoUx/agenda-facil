<script setup lang="ts">
import { computed, watch, ref, onUnmounted, provide, type Component } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useNewBookings } from '@/composables/useNewBookings'
import { applyAccent } from '@/lib/accent'
import BaseButton from '@/components/ui/BaseButton.vue'
import {
  Calendar,
  LayoutDashboard,
  Users,
  Palmtree,
  Scissors,
  UserCog,
  Settings,
  MessageCircle,
  Menu,
  X,
  LogOut,
} from '@lucide/vue'

// Navegação role-aware (§12): itens que a role não acessa não aparecem
// (e a rota é protegida no guard, não só escondida).
const auth = useAuthStore()
const router = useRouter()

// Notificações em tempo real (app aberto): liga o canal do tenant e expõe o
// contador de novos agendamentos para o badge do menu "Agenda".
const { unreadCount, start, stop, resetUnread } = useNewBookings()
watch(
  () => auth.tenant?.id,
  (id) => {
    if (id) start(id)
  },
  { immediate: true },
)
onUnmounted(stop)

// Zera o badge ao entrar na Agenda (o dono "viu" os novos).
watch(
  () => router.currentRoute.value.name,
  (name) => {
    if (name === 'agenda') resetUnread()
  },
)

// Accent do tenant aplicado em TODO o painel (§13.1), não só na página pública.
watch(
  () => auth.tenant,
  (t) => {
    if (t) applyAccent(t.accent_color, t.vertical)
  },
  { immediate: true },
)

interface NavItem {
  name: string
  label: string
  short: string
  icon: Component
  ownerOnly?: boolean
}
// short = rótulo enxuto p/ a bottom bar mobile (evita aperto com 5 itens).
const allItems: NavItem[] = [
  { name: 'agenda', label: 'Agenda', short: 'Agenda', icon: Calendar },
  { name: 'dashboard', label: 'Dashboard', short: 'Painel', icon: LayoutDashboard, ownerOnly: true },
  { name: 'clientes', label: 'Clientes', short: 'Clientes', icon: Users },
  { name: 'bloqueios', label: 'Bloqueios', short: 'Folgas', icon: Palmtree },
  { name: 'servicos', label: 'Serviços', short: 'Serviços', icon: Scissors, ownerOnly: true },
  { name: 'profissionais', label: 'Profissionais', short: 'Equipe', icon: UserCog, ownerOnly: true },
  { name: 'configuracoes', label: 'Configurações', short: 'Ajustes', icon: Settings, ownerOnly: true },
  { name: 'suporte', label: 'Suporte', short: 'Suporte', icon: MessageCircle },
]
const items = computed(() => allItems.filter((i) => !i.ownerOnly || auth.isOwner))
// Bottom bar enxuta: 4 primeiros + botão "Menu" (abre o drawer com o resto).
const primaryItems = computed(() => items.value.slice(0, 4))

async function logout() {
  await auth.signOut()
  router.push({ name: 'login' })
}

// ---- Drawer lateral (mobile) ----
// Aberto pelo botão "Menu" da bottom bar e pelo hambúrguer dos cabeçalhos das
// telas (via provide/inject). Fecha ao navegar, no Esc e ao tocar no backdrop.
const drawerOpen = ref(false)
function openDrawer() {
  drawerOpen.value = true
}
function closeDrawer() {
  drawerOpen.value = false
}
// Telas-filhas (AgendaView etc.) chamam isto pelo seu hambúrguer.
provide('openDrawer', openDrawer)
watch(
  () => router.currentRoute.value.fullPath,
  () => closeDrawer(),
)
function go(name: string) {
  closeDrawer()
  router.push({ name })
}

// Modal de boas-vindas do trial: mostra UMA vez por estabelecimento, quando o
// dono entra no app durante o teste grátis. Persistência por localStorage para
// não reaparecer a cada login.
const showWelcome = ref(false)
watch(
  () => [auth.tenant?.id, auth.trialDaysLeft] as const,
  ([tid, dias]) => {
    if (!tid || dias == null) return // só durante o trial e com tenant carregado
    if (!localStorage.getItem(`welcome_trial_seen_${tid}`)) showWelcome.value = true
  },
  { immediate: true },
)
function fecharWelcome() {
  if (auth.tenant) localStorage.setItem(`welcome_trial_seen_${auth.tenant.id}`, '1')
  showWelcome.value = false
}
</script>

<template>
  <div class="theme-admin relative min-h-screen bg-bg text-text">
    <!-- Fundo de marca esfumaçado (§8.3): logo grande, borrado e com vinheta
         radial que o funde no escuro. Decorativo, não captura cliques, fica
         atrás de tudo (z-0); o conteúdo sobe para z-10. -->
    <div class="pointer-events-none fixed inset-0 z-0 overflow-hidden" aria-hidden="true">
      <img
        src="/bg-logo.png"
        alt=""
        class="absolute left-1/2 top-1/2 w-[min(82vw,580px)] max-w-none -translate-x-1/2 -translate-y-1/2 opacity-[0.40] blur-[8px]"
      />
      <!-- halo do accent + vinheta que funde no fundo -->
      <div class="absolute -left-32 -top-32 h-80 w-80 rounded-full bg-accent opacity-[0.10] blur-[120px]"></div>
      <div class="absolute inset-0 bg-[radial-gradient(circle_at_50%_40%,transparent_0%,var(--bg)_82%)]"></div>
    </div>

    <!-- Sidebar desktop (vidro sutil — §8.3) -->
    <aside class="fixed inset-y-0 left-0 z-10 hidden w-64 flex-col border-r border-border bg-[var(--glass)] p-3 backdrop-blur-xl lg:flex">
      <div class="mb-5 flex items-center gap-3 px-3 pt-3">
        <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-accent text-on-accent shadow-glow">
          <Calendar class="h-5 w-5" :stroke-width="2.25" />
        </span>
        <div class="min-w-0">
          <p class="eyebrow">Agenda Fácil</p>
          <p class="truncate text-h3 font-display text-text">{{ auth.tenant?.nome ?? '—' }}</p>
        </div>
      </div>
      <nav class="flex flex-1 flex-col gap-1">
        <RouterLink
          v-for="item in items"
          :key="item.name"
          :to="{ name: item.name }"
          class="group flex min-h-touch items-center gap-3 rounded-lg px-3 text-body text-text-muted transition-colors duration-fast hover:bg-surface-2 hover:text-text"
          active-class="!bg-accent-soft !text-text font-semibold ring-1 ring-inset ring-[color-mix(in_srgb,var(--accent)_35%,transparent)]"
        >
          <component :is="item.icon" class="h-5 w-5 shrink-0" :stroke-width="2" />
          <span class="truncate">{{ item.label }}</span>
          <span
            v-if="item.name === 'agenda' && unreadCount > 0"
            class="ml-auto inline-flex min-w-5 items-center justify-center rounded-full bg-accent px-1.5 text-[11px] font-bold leading-5 text-on-accent"
            aria-label="novos agendamentos"
          >{{ unreadCount > 99 ? '99+' : unreadCount }}</span>
        </RouterLink>
      </nav>
      <button class="mt-1 flex min-h-touch items-center gap-3 rounded-lg px-3 text-body text-text-muted transition-colors duration-fast hover:bg-surface-2 hover:text-text" @click="logout">
        <LogOut class="h-5 w-5 shrink-0" :stroke-width="2" /> Sair
      </button>
    </aside>

    <!-- Conteúdo -->
    <main class="relative z-10 pb-28 lg:ml-64 lg:pb-0">
      <!-- Banner de teste grátis (durante o trial) -->
      <RouterLink
        v-if="auth.trialDaysLeft != null"
        :to="{ name: 'assinatura' }"
        class="flex items-center justify-center gap-2 bg-accent-soft px-4 py-2 text-small text-text"
      >
        <span aria-hidden="true">⏳</span>
        Teste grátis: <strong>{{ auth.trialDaysLeft }} dia(s)</strong> restante(s).
        <span class="font-semibold text-accent underline">Assinar agora</span>
      </RouterLink>

      <RouterView />
    </main>

    <!-- ===================== Drawer lateral (mobile) ===================== -->
    <Teleport to="body">
      <div v-if="drawerOpen" class="theme-admin fixed inset-0 z-50 lg:hidden">
        <!-- backdrop -->
        <div class="anim-fade absolute inset-0 bg-black/55 backdrop-blur-sm" @click="closeDrawer" />
        <!-- painel -->
        <aside class="anim-slide-in-left absolute inset-y-0 left-0 flex w-[82%] max-w-xs flex-col border-r border-border bg-[var(--glass-strong)] p-3 backdrop-blur-2xl">
          <div class="mb-4 flex items-center gap-3 px-2 pt-2">
            <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-accent text-on-accent shadow-glow">
              <Calendar class="h-5 w-5" :stroke-width="2.25" />
            </span>
            <div class="min-w-0 flex-1">
              <p class="eyebrow">Agenda Fácil</p>
              <p class="truncate text-h3 font-display text-text">{{ auth.tenant?.nome ?? '—' }}</p>
            </div>
            <button
              class="flex h-10 w-10 items-center justify-center rounded-lg text-text-muted transition-colors hover:bg-surface-2 hover:text-text"
              aria-label="Fechar menu"
              @click="closeDrawer"
            >
              <X class="h-5 w-5" :stroke-width="2.25" />
            </button>
          </div>
          <nav class="flex flex-1 flex-col gap-1 overflow-y-auto">
            <button
              v-for="item in items"
              :key="item.name"
              class="flex min-h-touch items-center gap-3 rounded-lg px-3 text-body transition-colors duration-fast"
              :class="router.currentRoute.value.name === item.name
                ? 'bg-accent-soft text-text font-semibold ring-1 ring-inset ring-[color-mix(in_srgb,var(--accent)_35%,transparent)]'
                : 'text-text-muted hover:bg-surface-2 hover:text-text'"
              @click="go(item.name)"
            >
              <component :is="item.icon" class="h-5 w-5 shrink-0" :stroke-width="2" />
              <span class="truncate">{{ item.label }}</span>
              <span
                v-if="item.name === 'agenda' && unreadCount > 0"
                class="ml-auto inline-flex min-w-5 items-center justify-center rounded-full bg-accent px-1.5 text-[11px] font-bold leading-5 text-on-accent"
              >{{ unreadCount > 99 ? '99+' : unreadCount }}</span>
            </button>
          </nav>
          <button class="mt-1 flex min-h-touch items-center gap-3 rounded-lg px-3 text-body text-text-muted transition-colors hover:bg-surface-2 hover:text-text" @click="logout">
            <LogOut class="h-5 w-5 shrink-0" :stroke-width="2" /> Sair
          </button>
        </aside>
      </div>
    </Teleport>

    <!-- ============= Bottom nav flutuante (mobile) — pill + blur ============= -->
    <nav class="fixed inset-x-0 bottom-0 z-40 flex justify-center px-4 pb-[max(12px,env(safe-area-inset-bottom))] lg:hidden">
      <div class="anim-fade-up flex w-full max-w-md items-center justify-around gap-1 rounded-pill border border-border bg-[var(--glass-strong)] p-1.5 shadow-float backdrop-blur-2xl">
        <RouterLink
          v-for="item in primaryItems"
          :key="item.name"
          :to="{ name: item.name }"
          class="group relative flex h-12 flex-1 flex-col items-center justify-center rounded-pill text-text-muted transition-colors duration-base"
          :aria-label="item.label"
        >
          <span
            class="absolute inset-0 scale-90 rounded-pill bg-accent opacity-0 shadow-glow transition-all duration-base ease-standard group-[.router-link-active]:scale-100 group-[.router-link-active]:opacity-100"
            aria-hidden="true"
          />
          <component
            :is="item.icon"
            class="relative h-5 w-5 transition-colors duration-base group-[.router-link-active]:text-on-accent"
            :stroke-width="2.1"
          />
          <span
            v-if="item.name === 'agenda' && unreadCount > 0"
            class="absolute right-3 top-1.5 inline-flex min-w-4 items-center justify-center rounded-full bg-danger px-1 text-[10px] font-bold leading-4 text-white"
          >{{ unreadCount > 9 ? '9+' : unreadCount }}</span>
        </RouterLink>
        <button
          class="flex h-12 flex-1 flex-col items-center justify-center rounded-pill text-text-muted transition-colors duration-base hover:text-text"
          aria-label="Abrir menu"
          @click="openDrawer"
        >
          <Menu class="h-5 w-5" :stroke-width="2.1" />
        </button>
      </div>
    </nav>

    <!-- Modal de boas-vindas (trial) — aparece 1x ao entrar no app durante o teste -->
    <Teleport to="body">
      <div
        v-if="showWelcome"
        class="theme-admin fixed inset-0 z-50 flex items-end justify-center bg-black/50 p-4 backdrop-blur-sm sm:items-center"
        @click.self="fecharWelcome"
      >
        <div class="anim-sheet-up w-full max-w-sm rounded-t-2xl border border-border bg-surface p-6 shadow-pop sm:rounded-2xl">
          <p class="eyebrow">Bem-vindo</p>
          <h2 class="mb-2 text-h2 font-display text-text">Seu teste grátis começou! 🎉</h2>
          <p class="mb-4 text-small text-text-muted">
            Você tem <strong class="text-text">{{ auth.trialDaysLeft }} dia(s) grátis</strong> para usar a
            <strong class="text-text">{{ auth.tenant?.nome }}</strong> por completo — sem precisar de cartão agora.
          </p>
          <ul class="mb-5 flex flex-col gap-2 text-small text-text">
            <li class="flex gap-2"><span aria-hidden="true">🗓️</span> Agenda completa e organização da equipe</li>
            <li class="flex gap-2"><span aria-hidden="true">🔗</span> Link público pro cliente marcar sozinho</li>
            <li class="flex gap-2"><span aria-hidden="true">🔔</span> Lembretes automáticos pra reduzir faltas</li>
          </ul>
          <BaseButton block @click="fecharWelcome">Começar a usar</BaseButton>
          <RouterLink
            :to="{ name: 'assinatura' }"
            class="mt-3 block text-center text-small text-text-muted underline"
            @click="fecharWelcome"
          >Ver o plano e assinar</RouterLink>
        </div>
      </div>
    </Teleport>
  </div>
</template>
