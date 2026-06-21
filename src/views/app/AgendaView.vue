<script setup lang="ts">
import { ref, reactive, computed, onMounted, onUnmounted, watch } from 'vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { useToast } from '@/composables/useToast'
import { formatHora, formatDataLonga, toDateParam } from '@/lib/format'
import type { AppointmentStatus, Service, Professional } from '@/types/database.types'
import AppointmentCard from '@/components/agenda/AppointmentCard.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import BaseSkeleton from '@/components/ui/BaseSkeleton.vue'
import BaseButton from '@/components/ui/BaseButton.vue'
import BaseInput from '@/components/ui/BaseInput.vue'

// Agenda (ADENDO §15.2/§15.3/§16.2). É a home do painel. Abre no dia de hoje.
// "Trilho de horário vivo" (§13.5) marca o agora e desliza durante o dia.
// O recorte (owner vê tudo / staff só a própria agenda) é garantido pela RLS.
const auth = useAuthStore()
const toast = useToast()

interface Row {
  id: string
  inicio_at: string
  fim_at: string
  status: AppointmentStatus
  professional_id: string
  service: { nome: string } | null
  customer: { nome: string } | null
  professional: { nome: string } | null
}

const date = ref(new Date())
const rows = ref<Row[]>([])
const loading = ref(true)
const errored = ref(false)
const selected = ref<Row | null>(null)

const today = new Date()
today.setHours(0, 0, 0, 0)
const canGoBack = computed(() => {
  const d = new Date(date.value)
  d.setHours(0, 0, 0, 0)
  return d > today
})
const isToday = computed(() => date.value.toDateString() === new Date().toDateString())

async function load() {
  loading.value = true
  errored.value = false
  const start = new Date(date.value)
  start.setHours(0, 0, 0, 0)
  const end = new Date(start)
  end.setDate(end.getDate() + 1)
  // RLS aplica o recorte por role automaticamente — não filtramos por
  // profissional no cliente para staff; o banco já barra o resto.
  const { data, error } = await supabase
    .from('appointments')
    .select('id, inicio_at, fim_at, status, professional_id, service:services(nome), customer:customers(nome), professional:professionals(nome)')
    .gte('inicio_at', start.toISOString())
    .lt('inicio_at', end.toISOString())
    .is('deleted_at', null)
    .order('inicio_at')
  if (error) {
    errored.value = true
  } else {
    rows.value = (data as unknown as Row[]) ?? []
  }
  loading.value = false
}

function shift(days: number) {
  const next = new Date(date.value)
  next.setDate(next.getDate() + days)
  date.value = next
}

watch(date, load)
onMounted(load)

// ---- Trilho de horário vivo (§13.5) ----
// Em uma lista vertical, o "agora" é inserido na posição cronológica certa:
// antes do primeiro agendamento que ainda vai começar. Atualiza a cada minuto.
const nowTs = ref(Date.now())
let timer: number | undefined
onMounted(() => {
  timer = window.setInterval(() => (nowTs.value = Date.now()), 60_000)
})
onUnmounted(() => window.clearInterval(timer))

const railVisible = computed(() => isToday.value)
// índice onde a linha "agora" deve aparecer (0..rows.length)
const nowIndex = computed(() => {
  const idx = rows.value.findIndex((r) => new Date(r.inicio_at).getTime() > nowTs.value)
  return idx === -1 ? rows.value.length : idx
})
const nowLabel = computed(() => formatHora(new Date(nowTs.value).toISOString()))

// ---- Ações de status (§15.3) ----
const ACTIONS: { label: string; status: AppointmentStatus }[] = [
  { label: 'Confirmar', status: 'confirmado' },
  { label: 'Concluir', status: 'concluido' },
  { label: 'Não compareceu', status: 'no_show' },
  { label: 'Cancelar', status: 'cancelado' },
]
async function setStatus(status: AppointmentStatus) {
  if (!selected.value) return
  const { error } = await supabase.from('appointments').update({ status }).eq('id', selected.value.id)
  if (error) {
    toast.error('Não foi possível atualizar. Tente novamente.')
  } else {
    toast.success('Agendamento atualizado.')
    selected.value = null
    await load()
  }
}

// ---- Quick-create pelo painel (§8.1) ----
// Recepcionista cria com cliente na frente. O EXCLUDE do banco é a barreira
// final contra overbooking; aqui só montamos um insert válido.
const showCreate = ref(false)
const services = ref<Service[]>([])
const professionals = ref<Professional[]>([])
const creating = ref(false)
const novo = reactive({
  service_id: '',
  professional_id: '',
  data: toDateParam(new Date()),
  hora: '09:00',
  cliente_nome: '',
  cliente_telefone: '',
})

async function abrirCriar() {
  if (services.value.length === 0 || professionals.value.length === 0) {
    const [{ data: svc }, { data: pr }] = await Promise.all([
      supabase.from('services').select('*').eq('ativo', true).is('deleted_at', null).order('nome'),
      supabase.from('professionals').select('*').eq('ativo', true).is('deleted_at', null).order('nome'),
    ])
    services.value = (svc as Service[]) ?? []
    professionals.value = (pr as Professional[]) ?? []
  }
  novo.service_id = services.value[0]?.id ?? ''
  novo.professional_id = professionals.value[0]?.id ?? ''
  novo.data = toDateParam(date.value)
  novo.hora = '09:00'
  novo.cliente_nome = ''
  novo.cliente_telefone = ''
  showCreate.value = true
}

async function criar() {
  const svc = services.value.find((s) => s.id === novo.service_id)
  if (!svc || !novo.professional_id) {
    toast.error('Escolha serviço e profissional.')
    return
  }
  if (!novo.cliente_nome.trim() || !/^\+?[0-9]{10,15}$/.test(novo.cliente_telefone)) {
    toast.error('Informe nome e telefone válidos do cliente.')
    return
  }
  const inicio = new Date(`${novo.data}T${novo.hora}:00`)
  if (Number.isNaN(inicio.getTime())) {
    toast.error('Data/hora inválida.')
    return
  }
  const fim = new Date(inicio.getTime() + (svc.duracao_min + (svc.buffer_min ?? 0)) * 60000)
  creating.value = true
  // cliente: reaproveita por telefone no tenant ou cria
  const { data: existing } = await supabase
    .from('customers')
    .select('id')
    .eq('telefone', novo.cliente_telefone)
    .maybeSingle()
  let customerId = (existing as { id: string } | null)?.id
  if (!customerId) {
    const { data: c, error: ce } = await supabase
      .from('customers')
      .insert({ tenant_id: auth.tenant!.id, nome: novo.cliente_nome.trim(), telefone: novo.cliente_telefone })
      .select('id')
      .single()
    if (ce || !c) {
      creating.value = false
      toast.error('Não foi possível salvar o cliente.')
      return
    }
    customerId = (c as { id: string }).id
  }
  const { error } = await supabase.from('appointments').insert({
    tenant_id: auth.tenant!.id,
    professional_id: novo.professional_id,
    service_id: novo.service_id,
    customer_id: customerId,
    inicio_at: inicio.toISOString(),
    fim_at: fim.toISOString(),
    status: 'agendado',
    origem: 'painel',
  })
  creating.value = false
  if (error) {
    // exclusion_violation (overbooking) vem como erro 23P01
    toast.error(error.message.includes('23P01') || error.message.toLowerCase().includes('exclud')
      ? 'Esse horário conflita com outro agendamento.'
      : 'Não foi possível criar o agendamento.')
    return
  }
  toast.success('Agendamento criado.')
  showCreate.value = false
  await load()
}
</script>

<template>
  <div class="mx-auto max-w-3xl p-4 sm:p-5">
    <header class="mb-5 flex items-center justify-between gap-3">
      <div>
        <p class="eyebrow">Agenda</p>
        <h1 class="text-h1 font-display capitalize text-text">{{ formatDataLonga(date) }}</h1>
      </div>
      <div class="flex items-center gap-1">
        <button class="flex h-touch w-touch items-center justify-center rounded-md border border-border disabled:opacity-40" :disabled="!canGoBack" aria-label="Dia anterior" @click="shift(-1)">‹</button>
        <button v-if="!isToday" class="min-h-touch rounded-md border border-border px-3 text-small" @click="date = new Date()">Hoje</button>
        <button class="flex h-touch w-touch items-center justify-center rounded-md border border-border" aria-label="Próximo dia" @click="shift(1)">›</button>
        <BaseButton class="ml-2" @click="abrirCriar">Novo</BaseButton>
      </div>
    </header>

    <!-- loading -->
    <div v-if="loading" class="flex flex-col gap-2">
      <BaseSkeleton v-for="n in 4" :key="n" height="84px" rounded="md" />
    </div>

    <!-- erro -->
    <EmptyState
      v-else-if="errored"
      icon="📡"
      title="Não foi possível carregar a agenda"
      description="Verifique sua conexão."
      cta-label="Tentar de novo"
      @cta="load"
    />

    <!-- vazio (§17) -->
    <EmptyState
      v-else-if="rows.length === 0"
      title="Nada na agenda hoje"
      description="Aproveite — ou crie um agendamento."
      cta-label="Novo agendamento"
      @cta="abrirCriar"
    />

    <!-- lista do dia com trilho do agora (inserido na posição cronológica) -->
    <div v-else class="flex flex-col gap-2">
      <template v-for="(r, i) in rows" :key="r.id">
        <div
          v-if="railVisible && i === nowIndex"
          class="my-1 flex items-center gap-2"
          aria-label="Agora"
        >
          <span class="tabular rounded-pill bg-accent px-1.5 py-0.5 text-caption text-on-accent">{{ nowLabel }}</span>
          <span class="h-0.5 flex-1 rounded-pill bg-accent" />
        </div>

        <AppointmentCard
          :inicio="r.inicio_at"
          :fim="r.fim_at"
          :status="r.status"
          :servico="r.service?.nome ?? '—'"
          :cliente="r.customer?.nome ?? '—'"
          :profissional="auth.isOwner ? r.professional?.nome : undefined"
          @click="selected = r"
        />
      </template>

      <!-- "agora" depois do último, se todos os horários já passaram -->
      <div
        v-if="railVisible && nowIndex === rows.length"
        class="my-1 flex items-center gap-2"
        aria-label="Agora"
      >
        <span class="tabular rounded-pill bg-accent px-1.5 py-0.5 text-caption text-on-accent">{{ nowLabel }}</span>
        <span class="h-0.5 flex-1 rounded-pill bg-accent" />
      </div>
    </div>

    <!-- bottom sheet de ações -->
    <Teleport to="body">
      <div v-if="selected" class="fixed inset-0 z-50 flex items-end justify-center bg-black/30 sm:items-center" @click.self="selected = null">
        <div class="w-full max-w-sm rounded-t-lg bg-surface p-5 shadow-lg sm:rounded-lg">
          <div class="mb-4">
            <p class="tabular text-h3 font-semibold text-text">{{ formatHora(selected.inicio_at) }}–{{ formatHora(selected.fim_at) }}</p>
            <p class="text-small text-text-muted">{{ selected.service?.nome }} · {{ selected.customer?.nome }}</p>
          </div>
          <div class="flex flex-col gap-2">
            <BaseButton
              v-for="a in ACTIONS"
              :key="a.status"
              :variant="a.status === 'cancelado' ? 'danger' : 'secondary'"
              block
              @click="setStatus(a.status)"
            >{{ a.label }}</BaseButton>
            <BaseButton variant="ghost" block @click="selected = null">Fechar</BaseButton>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Quick-create -->
    <Teleport to="body">
      <div v-if="showCreate" class="fixed inset-0 z-50 flex items-end justify-center overflow-y-auto bg-black/30 sm:items-center" @click.self="showCreate = false">
        <div class="my-4 w-full max-w-sm rounded-t-lg bg-surface p-5 shadow-lg sm:rounded-lg">
          <h2 class="mb-4 text-h2 font-display text-text">Novo agendamento</h2>
          <div v-if="services.length === 0 || professionals.length === 0" class="text-small text-text-muted">
            Cadastre ao menos um serviço e um profissional primeiro.
          </div>
          <div v-else class="flex flex-col gap-3">
            <div class="flex flex-col gap-1">
              <label class="text-small font-medium text-text">Serviço</label>
              <select v-model="novo.service_id" class="min-h-touch rounded-md border border-border bg-surface px-3 text-body text-text focus:border-accent focus:outline-none">
                <option v-for="s in services" :key="s.id" :value="s.id">{{ s.nome }}</option>
              </select>
            </div>
            <div class="flex flex-col gap-1">
              <label class="text-small font-medium text-text">Profissional</label>
              <select v-model="novo.professional_id" class="min-h-touch rounded-md border border-border bg-surface px-3 text-body text-text focus:border-accent focus:outline-none">
                <option v-for="p in professionals" :key="p.id" :value="p.id">{{ p.nome }}</option>
              </select>
            </div>
            <div class="grid grid-cols-2 gap-3">
              <BaseInput v-model="novo.data" label="Data" type="date" />
              <BaseInput v-model="novo.hora" label="Hora" type="time" />
            </div>
            <BaseInput v-model="novo.cliente_nome" label="Cliente" required />
            <BaseInput v-model="novo.cliente_telefone" label="Telefone" inputmode="tel" required />
            <BaseButton :loading="creating" block @click="criar">Criar agendamento</BaseButton>
            <BaseButton variant="ghost" block @click="showCreate = false">Cancelar</BaseButton>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
