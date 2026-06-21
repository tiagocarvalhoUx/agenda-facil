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
  <div class="flex items-center justify-between gap-2">
    <button
      class="flex h-touch w-touch items-center justify-center rounded-md border border-border text-text disabled:opacity-40"
      :disabled="!canGoBack"
      aria-label="Dia anterior"
      @click="shift(-1)"
    >‹</button>

    <div class="flex flex-col items-center">
      <span class="text-h3 font-display capitalize text-text">{{ formatDataLonga(modelValue) }}</span>
      <button
        v-if="!isToday"
        class="text-small text-accent underline"
        @click="goToday"
      >Voltar para hoje</button>
    </div>

    <button
      class="flex h-touch w-touch items-center justify-center rounded-md border border-border text-text"
      aria-label="Próximo dia"
      @click="shift(1)"
    >›</button>
  </div>
</template>
