<script setup lang="ts">
import type { Component } from 'vue'
import { STATUS } from '@/lib/appointmentStatus'
import type { AppointmentStatus } from '@/types/database.types'
import { Circle, CircleCheck, CircleX, Check, TriangleAlert } from '@lucide/vue'

const props = defineProps<{ status: AppointmentStatus }>()
const cfg = STATUS[props.status]

// Ícone Lucide por status (consistência visual — nunca só cor, §18).
const ICON: Record<AppointmentStatus, Component> = {
  agendado: Circle,
  confirmado: CircleCheck,
  cancelado: CircleX,
  concluido: Check,
  no_show: TriangleAlert,
}
</script>

<template>
  <span
    class="inline-flex items-center gap-1 rounded-pill px-2 py-0.5 text-caption font-medium"
    :class="[cfg.bg, cfg.text]"
  >
    <component :is="ICON[status]" class="h-3 w-3" :stroke-width="2.5" aria-hidden="true" />
    {{ cfg.label }}
  </span>
</template>
