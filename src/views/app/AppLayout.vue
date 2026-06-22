<script setup lang="ts">
import { computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { applyAccent } from '@/lib/accent'

// Navegação role-aware (§12): itens que a role não acessa não aparecem
// (e a rota é protegida no guard, não só escondida).
const auth = useAuthStore()
const router = useRouter()

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
]
const items = computed(() => allItems.filter((i) => !i.ownerOnly || auth.isOwner))

async function logout() {
  await auth.signOut()
  router.push({ name: 'login' })
}
</script>

<template>
  <div class="theme-admin relative min-h-screen bg-bg text-text">
    <!-- Fundo de marca esfumaçado (§8.3): logo grande, borrado e com vinheta
         radial que o funde no escuro. Decorativo, não captura cliques, fica
         atrás de tudo (z-0); o conteúdo sobe para z-10. -->
    <div class="pointer-events-none fixed inset-0 z-0 overflow-hidden" aria-hidden="true">
      <img
        src="/logo-agenda.png"
        alt=""
        class="absolute left-1/2 top-1/2 w-[min(82vw,560px)] max-w-none -translate-x-1/2 -translate-y-1/2 opacity-[0.30] blur-[14px]"
      />
      <div class="absolute inset-0 bg-[radial-gradient(circle_at_50%_42%,transparent_0%,var(--bg)_82%)]"></div>
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
        </RouterLink>
      </nav>
      <button class="flex min-h-touch items-center gap-3 rounded-md px-3 text-body text-text-muted hover:bg-surface-2" @click="logout">
        <span aria-hidden="true">↩</span> Sair
      </button>
    </aside>

    <!-- Conteúdo -->
    <main class="relative z-10 pb-20 lg:ml-60 lg:pb-0">
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
        <span class="text-lg leading-none" aria-hidden="true">{{ item.icon }}</span>
        <span class="w-full truncate text-center text-[11px] leading-tight">{{ item.short }}</span>
      </RouterLink>
    </nav>
  </div>
</template>
