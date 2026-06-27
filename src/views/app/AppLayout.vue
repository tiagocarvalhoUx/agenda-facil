<script setup lang="ts">
import { computed, watch, ref, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useNewBookings } from '@/composables/useNewBookings'
import { applyAccent } from '@/lib/accent'
import BaseButton from '@/components/ui/BaseButton.vue'

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
  icon: string
  ownerOnly?: boolean
}
// short = rótulo enxuto p/ a bottom bar mobile (evita aperto com 5 itens).
const allItems: NavItem[] = [
  { name: 'agenda', label: 'Agenda', short: 'Agenda', icon: '🗓️' },
  { name: 'dashboard', label: 'Dashboard', short: 'Painel', icon: '📊', ownerOnly: true },
  { name: 'clientes', label: 'Clientes', short: 'Clientes', icon: '👥' },
  { name: 'bloqueios', label: 'Bloqueios', short: 'Folgas', icon: '🌴' },
  { name: 'servicos', label: 'Serviços', short: 'Serviços', icon: '✂️', ownerOnly: true },
  { name: 'profissionais', label: 'Profissionais', short: 'Equipe', icon: '🧑‍⚕️', ownerOnly: true },
  { name: 'configuracoes', label: 'Configurações', short: 'Ajustes', icon: '⚙️', ownerOnly: true },
  { name: 'suporte', label: 'Suporte', short: 'Suporte', icon: '💬' },
]
const items = computed(() => allItems.filter((i) => !i.ownerOnly || auth.isOwner))

async function logout() {
  await auth.signOut()
  router.push({ name: 'login' })
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
        class="absolute left-1/2 top-1/2 w-[min(82vw,580px)] max-w-none -translate-x-1/2 -translate-y-1/2 opacity-[0.50] blur-[6px]"
      />
      <div class="absolute inset-0 bg-[radial-gradient(circle_at_50%_45%,transparent_0%,var(--bg)_85%)]"></div>
    </div>

    <!-- Sidebar desktop (vidro sutil — §8.3) -->
    <aside class="fixed inset-y-0 left-0 z-10 hidden w-60 flex-col border-r border-border bg-[var(--glass)] p-4 backdrop-blur-xl lg:flex">
      <div class="mb-6 px-2">
        <p class="eyebrow">Agenda</p>
        <p class="truncate text-h3 font-display text-text">{{ auth.tenant?.nome ?? '—' }}</p>
      </div>
      <nav class="flex flex-1 flex-col gap-1">
        <RouterLink
          v-for="item in items"
          :key="item.name"
          :to="{ name: item.name }"
          class="flex min-h-touch items-center gap-3 rounded-md px-3 text-body text-text transition-colors duration-fast hover:bg-surface-2"
          active-class="bg-accent-soft text-text font-semibold"
        >
          <span aria-hidden="true">{{ item.icon }}</span>
          {{ item.label }}
          <span
            v-if="item.name === 'agenda' && unreadCount > 0"
            class="ml-auto inline-flex min-w-5 items-center justify-center rounded-full bg-accent px-1.5 text-[11px] font-bold leading-5 text-white"
            aria-label="novos agendamentos"
          >{{ unreadCount > 99 ? '99+' : unreadCount }}</span>
        </RouterLink>
      </nav>
      <button class="flex min-h-touch items-center gap-3 rounded-md px-3 text-body text-text-muted hover:bg-surface-2" @click="logout">
        <span aria-hidden="true">↩</span> Sair
      </button>
    </aside>

    <!-- Conteúdo -->
    <main class="relative z-10 pb-20 lg:ml-60 lg:pb-0">
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

    <!-- Bottom bar mobile (rótulos curtos; rolável quando há muitos itens) -->
    <nav class="fixed inset-x-0 bottom-0 z-40 flex overflow-x-auto border-t border-border bg-[var(--glass)] backdrop-blur-xl lg:hidden">
      <RouterLink
        v-for="item in items"
        :key="item.name"
        :to="{ name: item.name }"
        class="flex min-h-touch min-w-[4.5rem] flex-1 flex-col items-center justify-center gap-0.5 px-1 py-2 text-text-muted"
        active-class="text-accent"
      >
        <span class="relative text-lg leading-none" aria-hidden="true">
          {{ item.icon }}
          <span
            v-if="item.name === 'agenda' && unreadCount > 0"
            class="absolute -right-2 -top-1 inline-flex min-w-4 items-center justify-center rounded-full bg-accent px-1 text-[10px] font-bold leading-4 text-white"
          >{{ unreadCount > 9 ? '9+' : unreadCount }}</span>
        </span>
        <span class="w-full truncate text-center text-[11px] leading-tight">{{ item.short }}</span>
      </RouterLink>
      <!-- Sair: a barra é rolável; fica no fim. -->
      <button
        class="flex min-h-touch min-w-[4.5rem] flex-1 flex-col items-center justify-center gap-0.5 px-1 py-2 text-text-muted"
        aria-label="Sair"
        @click="logout"
      >
        <span class="text-lg leading-none" aria-hidden="true">↩</span>
        <span class="w-full truncate text-center text-[11px] leading-tight">Sair</span>
      </button>
    </nav>

    <!-- Modal de boas-vindas (trial) — aparece 1x ao entrar no app durante o teste -->
    <Teleport to="body">
      <div
        v-if="showWelcome"
        class="theme-admin fixed inset-0 z-50 flex items-end justify-center bg-black/40 p-4 sm:items-center"
        @click.self="fecharWelcome"
      >
        <div class="w-full max-w-sm rounded-t-lg bg-surface p-6 shadow-lg sm:rounded-lg">
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
