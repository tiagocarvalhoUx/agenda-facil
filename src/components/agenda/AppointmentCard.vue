<script setup lang="ts">
import { formatHora } from '@/lib/format'
import { STATUS } from '@/lib/appointmentStatus'
import StatusBadge from '@/components/ui/StatusBadge.vue'
import type { AppointmentStatus } from '@/types/database.types'

// AppointmentCard (ADENDO §14/§13.2): barra lateral por status, hora, serviço,
// cliente, profissional. Aparece em 180ms (§16.2).
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
</script>

<template>
  <button
    class="flex w-full items-stretch gap-3 overflow-hidden rounded-md border border-border bg-surface text-left shadow-sm transition-transform duration-base ease-standard hover:shadow-md"
    :class="status === 'cancelado' ? 'opacity-60' : ''"
    @click="$emit('click')"
  >
    <span class="w-1 shrink-0" :class="cfg.bar" aria-hidden="true" />
    <div class="flex flex-1 flex-col gap-1 py-3 pr-3">
      <div class="flex items-center justify-between gap-2">
        <span class="tabular text-h3 font-semibold text-text" :class="status === 'cancelado' ? 'line-through' : ''">
          {{ formatHora(inicio) }}–{{ formatHora(fim) }}
        </span>
        <StatusBadge :status="status" />
      </div>
      <p class="text-body text-text">{{ servico }}</p>
      <p class="text-small text-text-muted">
        {{ cliente }}<template v-if="profissional"> · {{ profissional }}</template>
      </p>
    </div>
  </button>
</template>
