<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { supabase } from '@/lib/supabase'
import { useNewBookings } from '@/composables/useNewBookings'
import { formatHora } from '@/lib/format'
import { STATUS } from '@/lib/appointmentStatus'
import BaseSkeleton from '@/components/ui/BaseSkeleton.vue'
import type { AppointmentStatus } from '@/types/database.types'

// Grade semanal (visão calendário, inspirada em agendas tipo Google Calendar):
// colunas por dia (SEG→DOM), régua de horários na lateral e cada agendamento
// como um bloco posicionado no horário/duração reais, colorido por status.
// Reutiliza a mesma lógica de dados/RLS da agenda em lista — só muda a pintura.
// Convenção de fuso: seguimos o resto do painel (hora local ≈ America/Sao_Paulo).

export interface Row {
  id: string
  inicio_at: string
  fim_at: string
  status: AppointmentStatus
  professional_id: string
  service_id: string
  service: { nome: string } | null
  customer: { nome: string } | null
  professional: { nome: string } | null
}

const props = defineProps<{
  date: Date
  isOwner: boolean
  // Nomes de serviço por id — fallback quando o embed volta vazio (mesma lógica
  // da lista). Passado pela AgendaView, que já carrega o mapa uma vez.
  serviceNames?: Record<string, string>
}>()

// Nome do serviço: embed se veio, senão o mapa por id.
function svcName(r: Pick<Row, 'service' | 'service_id'>): string {
  return r.service?.nome ?? props.serviceNames?.[r.service_id] ?? '—'
}

const emit = defineEmits<{
  select: [row: Row]
  create: [slot: { data: string; hora: string }]
}>()

const HOUR_PX = 56 // altura de 1 hora na régua
const rows = ref<Row[]>([])
const loading = ref(true)
const errored = ref(false)

// ---- Semana em exibição (segunda a domingo) a partir da data âncora ----
function mondayOf(d: Date): Date {
  const x = new Date(d)
  x.setHours(0, 0, 0, 0)
  const dow = x.getDay() // 0=dom .. 6=sáb
  const diff = dow === 0 ? -6 : 1 - dow
  x.setDate(x.getDate() + diff)
  return x
}

const weekStart = computed(() => mondayOf(props.date))
const weekDays = computed(() => {
  const start = weekStart.value
  return Array.from({ length: 7 }, (_, i) => {
    const d = new Date(start)
    d.setDate(d.getDate() + i)
    return d
  })
})

const wdFmt = new Intl.DateTimeFormat('pt-BR', { weekday: 'short' })
function weekdayLabel(d: Date): string {
  return wdFmt.format(d).replace('.', '').toUpperCase()
}
function isSameDay(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}
const todayRef = new Date()

// ---- Carregamento da semana ----
async function load() {
  loading.value = true
  errored.value = false
  const start = weekStart.value
  const end = new Date(start)
  end.setDate(end.getDate() + 7)
  // A RLS aplica o recorte por role (owner vê tudo / staff só a própria agenda).
  const { data, error } = await supabase
    .from('appointments')
    .select(
      'id, inicio_at, fim_at, status, professional_id, service_id, service:services(nome), customer:customers(nome), professional:professionals(nome)',
    )
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

watch(() => weekStart.value.getTime(), load)
onMounted(load)
defineExpose({ reload: load })

// Realtime: novo agendamento público dentro da semana em exibição → recarrega.
const { onNewBooking } = useNewBookings()
const offNewBooking = onNewBooking((b) => {
  const start = weekStart.value.getTime()
  const end = start + 7 * 86_400_000
  const t = new Date(b.inicio_at).getTime()
  if (t >= start && t < end) void load()
})
onUnmounted(() => offNewBooking())

// ---- "Agora" (atualiza a cada minuto) ----
const nowTs = ref(Date.now())
let timer: number | undefined
onMounted(() => {
  timer = window.setInterval(() => (nowTs.value = Date.now()), 60_000)
})
onUnmounted(() => window.clearInterval(timer))

// ---- Faixa de horas visível: 8h–20h por padrão, expande p/ caber tudo ----
interface Positioned extends Row {
  startMin: number
  endMin: number
  top: number
  height: number
  lane: number
  lanes: number
}

const bounds = computed(() => {
  let min = 8 * 60
  let max = 20 * 60
  for (const r of rows.value) {
    const s = new Date(r.inicio_at)
    const e = new Date(r.fim_at)
    const sm = s.getHours() * 60 + s.getMinutes()
    const em = e.getHours() * 60 + e.getMinutes()
    if (sm < min) min = sm
    if (em > max) max = em
  }
  const startHour = Math.max(0, Math.floor(min / 60))
  const endHour = Math.min(24, Math.ceil(max / 60))
  return { startHour, endHour }
})

const hourLabels = computed(() => {
  const out: number[] = []
  for (let h = bounds.value.startHour; h <= bounds.value.endHour; h++) out.push(h)
  return out
})
const bodyHeight = computed(() => (bounds.value.endHour - bounds.value.startHour) * HOUR_PX)

// Blocos por coluna (dia), com resolução de sobreposição em "faixas" (lanes).
const columns = computed<Positioned[][]>(() => {
  const startHour = bounds.value.startHour
  const days = weekDays.value
  const buckets: Positioned[][] = days.map(() => [])
  for (const r of rows.value) {
    const s = new Date(r.inicio_at)
    const e = new Date(r.fim_at)
    const day = new Date(s)
    day.setHours(0, 0, 0, 0)
    const idx = days.findIndex((d) => isSameDay(d, day))
    if (idx === -1) continue
    const startMin = s.getHours() * 60 + s.getMinutes()
    const endMin = Math.max(startMin + 15, e.getHours() * 60 + e.getMinutes())
    const top = ((startMin - startHour * 60) / 60) * HOUR_PX
    const height = Math.max(((endMin - startMin) / 60) * HOUR_PX, 38)
    buckets[idx].push({ ...r, startMin, endMin, top, height, lane: 0, lanes: 1 })
  }
  // Atribui faixas dentro de cada cluster de eventos que se sobrepõem.
  for (const items of buckets) {
    items.sort((a, b) => a.startMin - b.startMin || a.endMin - b.endMin)
    let cluster: Positioned[] = []
    let clusterEnd = -1
    const flush = () => {
      const laneEnds: number[] = []
      for (const it of cluster) {
        let placed = false
        for (let l = 0; l < laneEnds.length; l++) {
          if (it.startMin >= laneEnds[l]) {
            it.lane = l
            laneEnds[l] = it.endMin
            placed = true
            break
          }
        }
        if (!placed) {
          it.lane = laneEnds.length
          laneEnds.push(it.endMin)
        }
      }
      for (const it of cluster) it.lanes = laneEnds.length
      cluster = []
    }
    for (const it of items) {
      if (cluster.length && it.startMin >= clusterEnd) {
        flush()
        clusterEnd = -1
      }
      cluster.push(it)
      clusterEnd = Math.max(clusterEnd, it.endMin)
    }
    if (cluster.length) flush()
  }
  return buckets
})

// Posição da linha "agora" (só na coluna do dia de hoje, se estiver na semana).
const nowMin = computed(() => {
  const d = new Date(nowTs.value)
  return d.getHours() * 60 + d.getMinutes()
})
const nowTop = computed(() => ((nowMin.value - bounds.value.startHour * 60) / 60) * HOUR_PX)
const todayIndex = computed(() => weekDays.value.findIndex((d) => isSameDay(d, new Date(nowTs.value))))

function blockStyle(b: Positioned) {
  const gap = 2
  const widthPct = 100 / b.lanes
  return {
    top: `${b.top}px`,
    height: `${b.height}px`,
    left: `calc(${b.lane * widthPct}% + ${gap}px)`,
    width: `calc(${widthPct}% - ${gap * 2}px)`,
  }
}

function pad(n: number): string {
  return n.toString().padStart(2, '0')
}

// Clique em espaço vazio da coluna → cria agendamento naquele dia/hora.
function onColumnClick(ev: MouseEvent, dayIdx: number) {
  const el = ev.currentTarget as HTMLElement
  const rect = el.getBoundingClientRect()
  const y = ev.clientY - rect.top
  const totalMin = bounds.value.startHour * 60 + (y / HOUR_PX) * 60
  const snapped = Math.round(totalMin / 30) * 30
  const hh = Math.floor(snapped / 60)
  const mm = snapped % 60
  const d = weekDays.value[dayIdx]
  const data = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
  emit('create', { data, hora: `${pad(hh)}:${pad(mm)}` })
}
</script>

<template>
  <div class="anim-fade">
    <div v-if="errored" class="rounded-xl border border-border bg-surface p-6 text-center">
      <p class="text-small text-text-muted">Não foi possível carregar a semana.</p>
      <button class="mt-2 text-small font-semibold text-accent" @click="load">Tentar de novo</button>
    </div>

    <div v-else class="overflow-x-auto rounded-2xl border border-border bg-surface shadow-card">
      <div class="min-w-[860px]">
        <!-- Cabeçalho: dias da semana (sticky no topo ao rolar verticalmente) -->
        <div class="sticky top-0 z-20 flex border-b border-border bg-surface/95 backdrop-blur-sm">
          <div class="w-14 shrink-0" aria-hidden="true" />
          <div class="flex flex-1">
            <div
              v-for="(d, i) in weekDays"
              :key="i"
              class="flex flex-1 flex-col items-center gap-0.5 border-l border-border py-2"
            >
              <span class="text-caption text-text-muted">{{ weekdayLabel(d) }}</span>
              <span
                class="tabular flex h-8 w-8 items-center justify-center rounded-full text-small font-semibold"
                :class="isSameDay(d, todayRef) ? 'bg-accent text-on-accent shadow-glow' : 'text-text'"
              >{{ d.getDate() }}</span>
            </div>
          </div>
        </div>

        <!-- Corpo: régua de horas + colunas com os blocos -->
        <div v-if="loading" class="flex flex-col gap-2 p-4">
          <BaseSkeleton v-for="n in 6" :key="n" height="48px" rounded="md" />
        </div>

        <div v-else class="flex">
          <!-- Régua de horários -->
          <div class="relative w-14 shrink-0" :style="{ height: `${bodyHeight}px` }">
            <div
              v-for="h in hourLabels"
              :key="h"
              class="absolute right-2 -translate-y-1/2 text-caption tabular text-text-muted"
              :style="{ top: `${(h - bounds.startHour) * HOUR_PX}px` }"
            >{{ pad(h) }}:00</div>
          </div>

          <!-- Área das colunas -->
          <div class="relative flex-1" :style="{ height: `${bodyHeight}px` }">
            <!-- Linhas de hora -->
            <div
              v-for="h in hourLabels"
              :key="`line-${h}`"
              class="pointer-events-none absolute inset-x-0 border-t border-border/70"
              :style="{ top: `${(h - bounds.startHour) * HOUR_PX}px` }"
            />

            <!-- Colunas dos dias -->
            <div class="absolute inset-0 grid grid-cols-7">
              <div
                v-for="(col, i) in columns"
                :key="i"
                class="relative border-l border-border"
                @click="onColumnClick($event, i)"
              >
                <!-- Linha do agora -->
                <div
                  v-if="i === todayIndex && nowTop >= 0 && nowTop <= bodyHeight"
                  class="pointer-events-none absolute inset-x-0 z-10 flex items-center"
                  :style="{ top: `${nowTop}px` }"
                >
                  <span class="h-2 w-2 -translate-x-1/2 rounded-full bg-accent" />
                  <span class="h-0.5 flex-1 bg-accent" />
                </div>

                <!-- Blocos de agendamento -->
                <button
                  v-for="b in col"
                  :key="b.id"
                  class="absolute flex flex-col overflow-hidden rounded-md border border-border pl-2 pr-1 py-1 text-left leading-tight shadow-card transition-transform duration-fast hover:z-10 hover:-translate-y-0.5"
                  :class="[STATUS[b.status].bg, b.status === 'cancelado' ? 'opacity-60' : '']"
                  :style="blockStyle(b)"
                  @click.stop="emit('select', b)"
                >
                  <span class="absolute inset-y-1 left-0 w-1 rounded-pill" :class="STATUS[b.status].bar" aria-hidden="true" />
                  <!-- Cliente + serviço sempre visíveis (o horário vem da posição/régua) -->
                  <p class="truncate text-caption font-semibold text-text" :class="b.status === 'cancelado' ? 'line-through' : ''">
                    {{ b.customer?.nome ?? '—' }}
                  </p>
                  <p class="truncate text-caption text-text-muted">
                    {{ svcName(b) }}
                  </p>
                  <p v-if="b.height > 64" class="tabular truncate text-caption text-text-muted">
                    {{ formatHora(b.inicio_at) }}<template v-if="isOwner && b.professional"> · {{ b.professional.nome }}</template>
                  </p>
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
