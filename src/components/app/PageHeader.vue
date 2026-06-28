<script setup lang="ts">
import { inject } from 'vue'
import { Menu } from '@lucide/vue'

// Cabeçalho padrão das telas do painel: hambúrguer (mobile) + eyebrow + título +
// subtítulo opcional, e um slot `actions` para a ação principal (ex.: "Novo").
// No desktop o hambúrguer some — a navegação é a sidebar. Mantém a identidade
// visual consistente entre todas as telas internas.
defineProps<{ eyebrow?: string; title: string; subtitle?: string }>()
const openDrawer = inject<() => void>('openDrawer', () => {})
</script>

<template>
  <header class="anim-fade-up mb-5">
    <div class="flex items-center justify-between gap-3">
      <div class="flex min-w-0 items-center gap-2">
        <button
          class="-ml-1 flex h-11 w-11 shrink-0 items-center justify-center rounded-lg text-text-muted transition-colors hover:bg-surface-2 hover:text-text lg:hidden"
          aria-label="Abrir menu"
          @click="openDrawer"
        >
          <Menu class="h-6 w-6" :stroke-width="2.1" />
        </button>
        <div class="min-w-0">
          <p v-if="eyebrow" class="eyebrow">{{ eyebrow }}</p>
          <h1 class="truncate text-h1 font-display text-text">{{ title }}</h1>
        </div>
      </div>
      <div v-if="$slots.actions" class="shrink-0">
        <slot name="actions" />
      </div>
    </div>
    <p v-if="subtitle" class="mt-2 max-w-2xl text-small text-text-muted">{{ subtitle }}</p>
  </header>
</template>
