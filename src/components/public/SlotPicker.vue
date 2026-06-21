<script setup lang="ts">
import { ref } from 'vue'
import { formatHora } from '@/lib/format'
import type { AvailableSlot } from '@/types/database.types'
import BaseSkeleton from '@/components/ui/BaseSkeleton.vue'

// SlotPicker (ADENDO §14/§16.1): grade de pills tocáveis. Acessível como
// radiogroup — setas navegam, foco visível, aria-label "14:30, disponível".
// Só slots livres chegam aqui (a RPC não devolve ocupados → sem PII).
const props = defineProps<{
  slots: AvailableSlot[]
  modelValue: string | null
  loading?: boolean
}>()
const emit = defineEmits<{ 'update:modelValue': [iso: string] }>()

const refs = ref<HTMLButtonElement[]>([])

function onKey(e: KeyboardEvent, i: number) {
  const cols = 3
  let next = i
  if (e.key === 'ArrowRight') next = Math.min(i + 1, props.slots.length - 1)
  else if (e.key === 'ArrowLeft') next = Math.max(i - 1, 0)
  else if (e.key === 'ArrowDown') next = Math.min(i + cols, props.slots.length - 1)
  else if (e.key === 'ArrowUp') next = Math.max(i - cols, 0)
  else return
  e.preventDefault()
  refs.value[next]?.focus()
  emit('update:modelValue', props.slots[next].inicio_at)
}
</script>

<template>
  <!-- loading: 8 skeletons em grade (§16.1) -->
  <div v-if="loading" class="grid grid-cols-3 gap-2 sm:grid-cols-4">
    <BaseSkeleton v-for="n in 8" :key="n" height="44px" rounded="pill" />
  </div>

  <div
    v-else
    role="radiogroup"
    aria-label="Horários disponíveis"
    class="grid grid-cols-3 gap-2 sm:grid-cols-4"
  >
    <button
      v-for="(slot, i) in slots"
      :key="slot.inicio_at"
      ref="refs"
      role="radio"
      :aria-checked="modelValue === slot.inicio_at"
      :aria-label="`${formatHora(slot.inicio_at)}, disponível`"
      :tabindex="modelValue === slot.inicio_at || (!modelValue && i === 0) ? 0 : -1"
      class="tabular min-h-touch rounded-pill border text-body font-medium transition-colors duration-fast ease-standard"
      :class="
        modelValue === slot.inicio_at
          ? 'border-accent bg-accent text-on-accent'
          : 'border-border bg-surface text-text hover:border-accent hover:bg-accent-soft'
      "
      @click="$emit('update:modelValue', slot.inicio_at)"
      @keydown="onKey($event, i)"
    >
      {{ formatHora(slot.inicio_at) }}
    </button>
  </div>
</template>
