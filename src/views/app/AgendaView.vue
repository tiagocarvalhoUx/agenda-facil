<script setup lang="ts">
import { ref, reactive, computed, onMounted, onUnmounted, watch, inject } from 'vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { useToast } from '@/composables/useToast'
import { useNewBookings } from '@/composables/useNewBookings'
import { formatHora, formatDataLonga, toDateParam } from '@/lib/format'
import type { AppointmentStatus, Service, Professional } from '@/types/database.types'
import AppointmentCard from '@/components/agenda/AppointmentCard.vue'
import AgendaWeekGrid from '@/components/agenda/AgendaWeekGrid.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import BaseSkeleton from '@/components/ui/BaseSkeleton.vue'
import BaseButton from '@/components/ui/BaseButton.vue'
import BaseInput from '@/components/ui/BaseInput.vue'
import { Menu, ChevronLeft, ChevronRight, Plus, List, CalendarRange } from '@lucide/vue'

// Abre o drawer lateral (provido pelo AppLayout) a partir do hambúrguer do hero.
const openDrawer = inject<() => void>('openDrawer', () => {})

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

// Modo de exibição: 'lista' (cartões do dia) ou 'grade' (calendário semanal).
// Persiste a preferência para reabrir a agenda como o usuário deixou.
type ViewMode = 'lista' | 'grade'
const viewMode = ref<ViewMode>(
  (localStorage.getItem('agenda_view') as ViewMode) === 'grade' ? 'grade' : 'lista',
)
const gridRef = ref<InstanceType<typeof AgendaWeekGrid> | null>(null)
function setView(mode: ViewMode) {
  viewMode.value = mode
  localStorage.setItem('agenda_view', mode)
}

const today = new Date()
today.setHours(0, 0, 0, 0)

// Segunda-feira da semana de uma data (para navegação/label no modo grade).
function mondayOf(d: Date): Date {
  const x = new Date(d)
  x.setHours(0, 0, 0, 0)
  const dow = x.getDay()
  x.setDate(x.getDate() + (dow === 0 ? -6 : 1 - dow))
  return x
}
const thisMonday = mondayOf(new Date())

const canGoBack = computed(() => {
  if (viewMode.value === 'grade') return mondayOf(date.value) > thisMonday
  const d = new Date(date.value)
  d.setHours(0, 0, 0, 0)
  return d > today
})
// "Hoje" ativo: mesmo dia (lista) ou mesma semana (grade).
const isToday = computed(() =>
  viewMode.value === 'grade'
    ? mondayOf(date.value).getTime() === thisMonday.getTime()
    : date.value.toDateString() === new Date().toDateString(),
)
const todayLabel = computed(() => (viewMode.value === 'grade' ? 'Esta semana' : 'Hoje'))

// Rótulo do período no hero: dia por extenso (lista) ou intervalo da semana (grade).
const rangeFmt = new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: 'short' })
const periodoLabel = computed(() => {
  if (viewMode.value === 'lista') return formatDataLonga(date.value)
  const start = mondayOf(date.value)
  const end = new Date(start)
  end.setDate(end.getDate() + 6)
  return `${rangeFmt.format(start)} – ${rangeFmt.format(end)}`.replace(/\./g, '')
})

// Saudação por período do dia (apresentação — sem dados novos). Hora no fuso BR.
const greeting = computed(() => {
  const h = Number(
    new Intl.DateTimeFormat('pt-BR', { hour: 'numeric', hour12: false, timeZone: 'America/Sao_Paulo' }).format(new Date()),
  )
  if (h < 12) return 'Bom dia'
  if (h < 18) return 'Boa tarde'
  return 'Boa noite'
})
// Resumo do dia derivado do que já carregamos (contagem de agendamentos).
const resumo = computed(() => {
  const n = rows.value.length
  const quando = isToday.value ? 'hoje' : 'neste dia'
  if (n === 0) return isToday.value ? 'Nenhum agendamento por enquanto.' : 'Nenhum agendamento neste dia.'
  return `Você tem ${n} agendamento${n > 1 ? 's' : ''} ${quando}.`
})

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

function shift(steps: number) {
  const next = new Date(date.value)
  next.setDate(next.getDate() + steps * (viewMode.value === 'grade' ? 7 : 1))
  date.value = next
}

watch(date, load)
onMounted(load)

// Realtime: quando um novo agendamento público chega e é do dia em exibição,
// recarrega a lista para mostrá-lo sem o dono precisar atualizar a página.
const { onNewBooking } = useNewBookings()
const offNewBooking = onNewBooking((b) => {
  const start = new Date(date.value)
  start.setHours(0, 0, 0, 0)
  const end = new Date(start)
  end.setDate(end.getDate() + 1)
  const t = new Date(b.inicio_at).getTime()
  if (t >= start.getTime() && t < end.getTime()) void load()
})
onUnmounted(() => offNewBooking())

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
    gridRef.value?.reload()
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

async function abrirCriar(prefill?: { data: string; hora: string }) {
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
  novo.data = prefill?.data ?? toDateParam(date.value)
  novo.hora = prefill?.hora ?? '09:00'
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
    preco_total: svc.preco, // congela o preço no momento da criação
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
  gridRef.value?.reload()
}
</script>

<template>
  <div class="mx-auto p-4 sm:p-5" :class="viewMode === 'grade' ? 'max-w-6xl' : 'max-w-3xl'">
    <!-- Top bar: hambúrguer (mobile) + título + Novo (desktop) -->
    <div class="mb-4 flex items-center justify-between gap-3">
      <div class="flex items-center gap-2">
        <button
          class="-ml-1 flex h-11 w-11 items-center justify-center rounded-lg text-text-muted transition-colors hover:bg-surface-2 hover:text-text lg:hidden"
          aria-label="Abrir menu"
          @click="openDrawer"
        >
          <Menu class="h-6 w-6" :stroke-width="2.1" />
        </button>
        <h1 class="text-h2 font-display text-text">Agenda</h1>
      </div>
      <BaseButton class="hidden lg:inline-flex" @click="abrirCriar()">
        <Plus class="h-5 w-5" :stroke-width="2.25" /> Novo
      </BaseButton>
    </div>

    <!-- Hero: saudação + data + resumo do dia (anim de entrada) -->
    <header class="anim-fade-up mb-5">
      <p class="text-small text-text-muted">{{ greeting }} 👋</p>
      <h2 class="mt-0.5 text-display-lg font-display text-text first-letter:uppercase">{{ periodoLabel }}</h2>
      <p v-if="viewMode === 'lista'" class="mt-1 text-small text-text-muted">{{ resumo }}</p>

      <div class="mt-4 flex flex-wrap items-center gap-2">
        <!-- Navegação (‹ Hoje/Esta semana ›). Passo = 1 dia ou 1 semana. -->
        <div class="inline-flex items-center gap-1 rounded-pill border border-border bg-surface/70 p-1 shadow-card backdrop-blur-sm">
          <button
            class="flex h-10 w-10 items-center justify-center rounded-pill text-text-muted transition-colors duration-fast hover:bg-surface-2 hover:text-text focus-visible:outline-none disabled:pointer-events-none disabled:opacity-30"
            :disabled="!canGoBack"
            :aria-label="viewMode === 'grade' ? 'Semana anterior' : 'Dia anterior'"
            @click="shift(-1)"
          >
            <ChevronLeft class="h-5 w-5" :stroke-width="2.25" />
          </button>
          <button
            class="h-10 rounded-pill px-5 text-small font-semibold transition-colors duration-fast focus-visible:outline-none"
            :class="isToday ? 'cursor-default bg-accent text-on-accent shadow-glow' : 'text-text hover:bg-surface-2'"
            :disabled="isToday"
            :aria-current="isToday ? 'date' : undefined"
            @click="date = new Date()"
          >{{ todayLabel }}</button>
          <button
            class="flex h-10 w-10 items-center justify-center rounded-pill text-text-muted transition-colors duration-fast hover:bg-surface-2 hover:text-text focus-visible:outline-none"
            :aria-label="viewMode === 'grade' ? 'Próxima semana' : 'Próximo dia'"
            @click="shift(1)"
          >
            <ChevronRight class="h-5 w-5" :stroke-width="2.25" />
          </button>
        </div>

        <!-- Alternador de visualização: Lista (cartões) · Grade (semana) -->
        <div class="inline-flex items-center gap-1 rounded-pill border border-border bg-surface/70 p-1 shadow-card backdrop-blur-sm">
          <button
            class="flex h-10 items-center gap-1.5 rounded-pill px-3 text-small font-semibold transition-colors duration-fast focus-visible:outline-none"
            :class="viewMode === 'lista' ? 'bg-accent text-on-accent shadow-glow' : 'text-text-muted hover:bg-surface-2 hover:text-text'"
            :aria-pressed="viewMode === 'lista'"
            @click="setView('lista')"
          >
            <List class="h-4 w-4" :stroke-width="2.25" /> Lista
          </button>
          <button
            class="flex h-10 items-center gap-1.5 rounded-pill px-3 text-small font-semibold transition-colors duration-fast focus-visible:outline-none"
            :class="viewMode === 'grade' ? 'bg-accent text-on-accent shadow-glow' : 'text-text-muted hover:bg-surface-2 hover:text-text'"
            :aria-pressed="viewMode === 'grade'"
            @click="setView('grade')"
          >
            <CalendarRange class="h-4 w-4" :stroke-width="2.25" /> Grade
          </button>
        </div>
      </div>
    </header>

    <!-- ============ MODO LISTA (cartões do dia) ============ -->
    <template v-if="viewMode === 'lista'">
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
      @cta="abrirCriar()"
    />

    <!-- lista do dia com trilho do agora (inserido na posição cronológica) -->
    <div v-else class="stagger flex flex-col gap-3">
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
    </template>

    <!-- ============ MODO GRADE (calendário semanal) ============ -->
    <AgendaWeekGrid
      v-else
      ref="gridRef"
      :date="date"
      :is-owner="auth.isOwner"
      @select="selected = $event"
      @create="abrirCriar($event)"
    />

    <!-- FAB flutuante (mobile): cria agendamento. Fica acima da bottom nav. -->
    <button
      class="anim-scale-in fixed bottom-24 right-5 z-40 flex h-14 w-14 items-center justify-center rounded-pill border border-accent-border bg-accent text-on-accent shadow-glow transition-transform duration-base ease-standard hover:bg-accent-hover active:scale-95 lg:hidden"
      aria-label="Novo agendamento"
      @click="abrirCriar()"
    >
      <Plus class="h-6 w-6" :stroke-width="2.5" />
    </button>

    <!-- bottom sheet de ações -->
    <Teleport to="body">
      <div v-if="selected" class="theme-admin fixed inset-0 z-50 flex items-end justify-center bg-black/50 p-0 backdrop-blur-sm sm:items-center sm:p-4" @click.self="selected = null">
        <div class="anim-sheet-up w-full max-w-sm rounded-t-2xl border border-border bg-surface p-5 shadow-pop sm:rounded-2xl">
          <div class="mx-auto mb-4 h-1 w-10 rounded-pill bg-border sm:hidden" aria-hidden="true" />
          <div class="mb-4">
            <p class="tabular text-h2 font-semibold text-text">{{ formatHora(selected.inicio_at) }}–{{ formatHora(selected.fim_at) }}</p>
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
      <div v-if="showCreate" class="theme-admin fixed inset-0 z-50 flex items-end justify-center overflow-y-auto bg-black/50 backdrop-blur-sm sm:items-center sm:p-4" @click.self="showCreate = false">
        <div class="anim-sheet-up w-full max-w-sm rounded-t-2xl border border-border bg-surface p-5 shadow-pop sm:my-4 sm:rounded-2xl">
          <div class="mx-auto mb-4 h-1 w-10 rounded-pill bg-border sm:hidden" aria-hidden="true" />
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
