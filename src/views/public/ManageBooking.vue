<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { applyAccent } from '@/lib/accent'
import {
  fetchBookingByToken,
  cancelBooking,
  rescheduleBooking,
  fetchSlots,
} from '@/lib/publicApi'
import { mapBookingError } from '@/lib/errors'
import { useToast } from '@/composables/useToast'
import { formatHora, formatDataLonga, toDateParam } from '@/lib/format'
import type { ManagedBooking, AvailableSlot } from '@/types/database.types'

import DateNavigator from '@/components/public/DateNavigator.vue'
import SlotPicker from '@/components/public/SlotPicker.vue'
import BaseButton from '@/components/ui/BaseButton.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import BaseSkeleton from '@/components/ui/BaseSkeleton.vue'
import StatusBadge from '@/components/ui/StatusBadge.vue'

// Tela pública de auto-gerenciamento (§6.4). Só o próprio agendamento e as
// ações permitidas pela política — nenhum dado de terceiros.
const route = useRoute()
const token = route.params.token as string
const toast = useToast()

const loading = ref(true)
const loadError = ref(false)
const booking = ref<ManagedBooking | null>(null)

const mode = ref<'view' | 'reschedule'>('view')
const date = ref(new Date())
const slots = ref<AvailableSlot[]>([])
const loadingSlots = ref(false)
const slotIso = ref<string | null>(null)
const working = ref(false)

const podeGerenciar = computed(() => booking.value?.pode_gerenciar ?? false)

async function load() {
  loading.value = true
  loadError.value = false
  try {
    booking.value = await fetchBookingByToken(token)
    if (booking.value) {
      applyAccent(booking.value.accent_color, null)
      document.title = `Seu agendamento — ${booking.value.estabelecimento}`
    }
  } catch {
    loadError.value = true
  } finally {
    loading.value = false
  }
}

onMounted(load)

async function loadSlots() {
  if (!booking.value) return
  loadingSlots.value = true
  slotIso.value = null
  try {
    slots.value = await fetchSlots({
      slug: booking.value.slug,
      serviceId: booking.value.service_id,
      data: toDateParam(date.value),
      professionalId: booking.value.professional_id,
    })
  } catch {
    toast.error('Não foi possível carregar os horários.')
  } finally {
    loadingSlots.value = false
  }
}

function startReschedule() {
  mode.value = 'reschedule'
  void loadSlots()
}

async function onDateChange(d: Date) {
  date.value = d
  await loadSlots()
}

async function confirmReschedule() {
  if (!slotIso.value) return
  working.value = true
  try {
    await rescheduleBooking(token, slotIso.value)
    toast.success('Agendamento remarcado!')
    mode.value = 'view'
    await load()
  } catch (e: unknown) {
    toast.error(mapBookingError((e as { message?: string }).message))
  } finally {
    working.value = false
  }
}

async function confirmCancel() {
  if (!window.confirm('Tem certeza que deseja cancelar este agendamento?')) return
  working.value = true
  try {
    await cancelBooking(token)
    toast.success('Agendamento cancelado.')
    await load()
  } catch (e: unknown) {
    toast.error(mapBookingError((e as { message?: string }).message))
  } finally {
    working.value = false
  }
}
</script>

<template>
  <div class="mx-auto flex min-h-screen max-w-lg flex-col bg-bg px-4 py-6">
    <div v-if="loading" class="flex flex-col gap-4">
      <BaseSkeleton height="2rem" />
      <BaseSkeleton height="8rem" rounded="lg" />
    </div>

    <EmptyState
      v-else-if="loadError"
      icon="📡"
      title="Não foi possível carregar"
      description="Verifique sua conexão e tente novamente."
      cta-label="Tentar de novo"
      @cta="load"
    />

    <EmptyState
      v-else-if="!booking"
      icon="🔍"
      title="Agendamento não encontrado"
      description="O link pode estar incorreto ou expirado."
    />

    <template v-else>
      <header class="mb-5 flex items-center gap-3">
        <img
          :src="booking.brand_logo_url || '/logo-agenda.png'"
          :alt="booking.estabelecimento"
          class="h-12 w-12 shrink-0 rounded-lg object-contain"
        />
        <div>
          <p class="eyebrow">Seu agendamento</p>
          <h1 class="text-h1 font-display text-text">{{ booking.estabelecimento }}</h1>
        </div>
      </header>

      <!-- Resumo -->
      <dl class="rounded-lg border border-border bg-surface p-4">
        <div class="flex items-center justify-between border-b border-border py-2">
          <dt class="text-small text-text-muted">Status</dt>
          <dd><StatusBadge :status="booking.status" /></dd>
        </div>
        <div class="flex justify-between border-b border-border py-2">
          <dt class="text-small text-text-muted">Serviço</dt>
          <dd class="text-small font-medium text-text">{{ booking.servico }}</dd>
        </div>
        <div class="flex justify-between border-b border-border py-2">
          <dt class="text-small text-text-muted">Profissional</dt>
          <dd class="text-small font-medium text-text">{{ booking.profissional }}</dd>
        </div>
        <div class="flex justify-between border-b border-border py-2">
          <dt class="text-small text-text-muted">Data</dt>
          <dd class="text-small font-medium capitalize text-text">{{ formatDataLonga(booking.inicio_at) }}</dd>
        </div>
        <div class="flex justify-between py-2">
          <dt class="text-small text-text-muted">Horário</dt>
          <dd class="tabular text-small font-medium text-text">{{ formatHora(booking.inicio_at) }}</dd>
        </div>
      </dl>

      <!-- Ações -->
      <section v-if="mode === 'view'" class="mt-5 flex flex-col gap-3">
        <template v-if="podeGerenciar">
          <BaseButton block :loading="working" @click="startReschedule">Remarcar</BaseButton>
          <BaseButton variant="danger" block :loading="working" @click="confirmCancel">
            Cancelar agendamento
          </BaseButton>
        </template>
        <p v-else class="rounded-md border border-border bg-surface-2 p-3 text-small text-text-muted">
          Este agendamento não pode mais ser alterado online. Entre em contato com o estabelecimento.
        </p>
      </section>

      <!-- Remarcação -->
      <section v-else class="mt-5 flex flex-col gap-5">
        <h2 class="text-h2 font-display text-text">Escolha o novo horário</h2>
        <DateNavigator :model-value="date" @update:model-value="onDateChange" />
        <SlotPicker
          v-if="loadingSlots || slots.length > 0"
          v-model="slotIso"
          :slots="slots"
          :loading="loadingSlots"
        />
        <EmptyState
          v-else
          icon="🗓️"
          title="Sem horários nesse dia"
          description="Tente outra data."
        />
        <div class="flex gap-3">
          <BaseButton variant="secondary" block @click="mode = 'view'">Voltar</BaseButton>
          <BaseButton block :disabled="!slotIso" :loading="working" @click="confirmReschedule">
            Confirmar
          </BaseButton>
        </div>
      </section>
    </template>
  </div>
</template>
