<script setup lang="ts">
import { useToast } from '@/composables/useToast'

// aria-live="polite" anuncia o feedback a leitores de tela (§18).
const { toasts, dismiss } = useToast()

const styles: Record<string, string> = {
  success: 'border-l-success',
  error: 'border-l-danger',
  info: 'border-l-info',
}
const icons: Record<string, string> = { success: '✓', error: '!', info: 'i' }
</script>

<template>
  <!-- pointer-events-none: o container NÃO intercepta cliques (senão tampa a
       bottom bar no mobile, já que ambos ficam em bottom-0). Os cards reativam
       o ponteiro. pb maior no mobile mantém o toast acima da navegação. -->
  <div
    class="pointer-events-none fixed inset-x-0 bottom-0 z-50 flex flex-col items-center gap-2 p-4 pb-24 sm:items-end lg:pb-4"
    aria-live="polite"
    aria-atomic="true"
  >
    <TransitionGroup name="toast">
      <div
        v-for="t in toasts"
        :key="t.id"
        class="pointer-events-auto flex w-full max-w-sm items-start gap-3 rounded-md border border-border border-l-4 bg-surface p-4 shadow-md"
        :class="styles[t.kind]"
        role="status"
      >
        <span
          class="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-pill text-small font-semibold"
          :class="t.kind === 'error' ? 'bg-danger text-on-accent' : t.kind === 'success' ? 'bg-success text-on-accent' : 'bg-info text-on-accent'"
          aria-hidden="true"
        >{{ icons[t.kind] }}</span>
        <p class="flex-1 text-small text-text">{{ t.message }}</p>
        <button
          class="shrink-0 text-text-muted hover:text-text"
          aria-label="Fechar aviso"
          @click="dismiss(t.id)"
        >×</button>
      </div>
    </TransitionGroup>
  </div>
</template>

<style scoped>
.toast-enter-active,
.toast-leave-active {
  transition: all var(--motion-base) var(--ease-standard);
}
.toast-enter-from,
.toast-leave-to {
  opacity: 0;
  transform: translateY(8px);
}
</style>
