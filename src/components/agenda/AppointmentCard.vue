<script setup lang="ts">
import { computed } from 'vue'
import { formatHora, formatDuracao } from '@/lib/format'
import { STATUS } from '@/lib/appointmentStatus'
import StatusBadge from '@/components/ui/StatusBadge.vue'
import type { AppointmentStatus } from '@/types/database.types'

// AppointmentCard (ADENDO §14/§13.2): avatar + cliente + serviço, hora e
// duração, barra lateral colorida por status e badge. Aparece em cascata (§16.2).
const props = defineProps<{
  inicio: string
  fim: string
  status: AppointmentStatus
  servico: string
  cliente: string
  profissional?: string
}>()
defineEmits<{ click: [] }>()

const cfg = STATUS[props.status]

// Iniciais do cliente para o avatar (até 2 letras, maiúsculas).
const iniciais = computed(() => {
  const partes = props.cliente.trim().split(/\s+/).filter(Boolean)
  if (partes.length === 0) return '—'
  const first = partes[0][0]
  const last = partes.length > 1 ? partes[partes.length - 1][0] : ''
  return (first + last).toUpperCase()
})

const duracao = computed(() => {
  const min = Math.round((new Date(props.fim).getTime() - new Date(props.inicio).getTime()) / 60000)
  return min > 0 ? formatDuracao(min) : ''
})
</script>

<template>
  <button
    class="group relative flex w-full items-center gap-3 overflow-hidden rounded-xl border border-border bg-surface p-3 pl-4 text-left shadow-card transition-all duration-base ease-standard hover:-translate-y-0.5 hover:border-[color-mix(in_srgb,var(--accent)_30%,var(--border))] hover:shadow-float focus-visible:outline-none"
    :class="status === 'cancelado' ? 'opacity-60' : ''"
    @click="$emit('click')"
  >
    <!-- barra lateral por status -->
    <span class="absolute inset-y-2 left-0 w-1 rounded-pill" :class="cfg.bar" aria-hidden="true" />

    <!-- avatar com iniciais -->
    <span
      class="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-accent-soft text-small font-semibold text-text ring-1 ring-inset ring-[color-mix(in_srgb,var(--accent)_35%,transparent)]"
      aria-hidden="true"
    >{{ iniciais }}</span>

    <!-- conteúdo -->
    <div class="flex min-w-0 flex-1 flex-col gap-0.5">
      <div class="flex items-center justify-between gap-2">
        <p class="truncate text-h3 font-semibold text-text" :class="status === 'cancelado' ? 'line-through' : ''">
          {{ cliente }}
        </p>
        <StatusBadge :status="status" />
      </div>
      <p class="truncate text-small text-text-muted">
        {{ servico }}<template v-if="profissional"> · {{ profissional }}</template>
      </p>
      <p class="tabular mt-0.5 text-small font-medium text-text">
        {{ formatHora(inicio) }}–{{ formatHora(fim) }}
        <span v-if="duracao" class="font-normal text-text-muted">· {{ duracao }}</span>
      </p>
    </div>
  </button>
</template>
