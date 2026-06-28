<script setup lang="ts">
import { Plus } from '@lucide/vue'

// FAB de criação (mobile): botão circular flutuante acima da bottom nav.
// No desktop some — lá a ação fica no botão do cabeçalho. Espelha o FAB da Agenda.
defineProps<{ label: string; disabled?: boolean }>()
defineEmits<{ click: [] }>()
</script>

<template>
  <button
    class="anim-scale-in fixed bottom-24 right-5 z-40 flex h-14 w-14 items-center justify-center rounded-pill bg-accent text-on-accent shadow-glow transition-transform duration-base ease-standard hover:bg-accent-hover active:scale-95 disabled:opacity-50 lg:hidden"
    :aria-label="label"
    :disabled="disabled"
    @click="$emit('click')"
  >
    <Plus class="h-6 w-6" :stroke-width="2.5" />
  </button>
</template>
