<script setup lang="ts">
import { STATUS } from '@/lib/appointmentStatus'
import type { AppointmentStatus } from '@/types/database.types'

const props = defineProps<{ status: AppointmentStatus }>()
const cfg = STATUS[props.status]
</script>

<template>
  <span
    class="inline-flex items-center gap-1 rounded-pill px-2 py-0.5 text-caption font-medium"
    :class="[cfg.bg, cfg.text]"
  >
    <span aria-hidden="true">{{ cfg.icon }}</span>
    {{ cfg.label }}
  </span>
</template>
