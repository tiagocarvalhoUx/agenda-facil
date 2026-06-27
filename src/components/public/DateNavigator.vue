<script setup lang="ts">
import { computed } from 'vue'
import { formatDataLonga } from '@/lib/format'

// DateNavigator (ADENDO §14/§16.1): hoje / setas. Não navega para o passado.
const props = defineProps<{ modelValue: Date }>()
const emit = defineEmits<{ 'update:modelValue': [value: Date] }>()

const today = new Date()
today.setHours(0, 0, 0, 0)

const isToday = computed(() => props.modelValue.toDateString() === today.toDateString())
const canGoBack = computed(() => props.modelValue > today)

function shift(days: number) {
  const next = new Date(props.modelValue)
  next.setDate(next.getDate() + days)
  if (next < today) return
  emit('update:modelValue', next)
}
function goToday() {
  emit('update:modelValue', new Date(today))
}
</script>

<template>
  <div class="flex items-center justify-between gap-3">
    <button
      class="flex h-touch w-touch shrink-0 items-center justify-center rounded-full border border-border text-text-muted transition-colors duration-fast hover:bg-surface-2 hover:text-text focus-visible:bg-surface-2 focus-visible:outline-none disabled:pointer-events-none disabled:opacity-30"
      :disabled="!canGoBack"
      aria-label="Dia anterior"
      @click="shift(-1)"
    >
      <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.25" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m15 18-6-6 6-6" /></svg>
    </button>

    <div class="flex min-w-0 flex-col items-center text-center">
      <span class="truncate text-h3 font-display capitalize text-text">{{ formatDataLonga(modelValue) }}</span>
      <button
        v-if="!isToday"
        class="text-small font-medium text-accent underline-offset-2 hover:underline"
        @click="goToday"
      >Voltar para hoje</button>
    </div>

    <button
      class="flex h-touch w-touch shrink-0 items-center justify-center rounded-full border border-border text-text-muted transition-colors duration-fast hover:bg-surface-2 hover:text-text focus-visible:bg-surface-2 focus-visible:outline-none"
      aria-label="Próximo dia"
      @click="shift(1)"
    >
      <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.25" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 18 6-6-6-6" /></svg>
    </button>
  </div>
</template>
