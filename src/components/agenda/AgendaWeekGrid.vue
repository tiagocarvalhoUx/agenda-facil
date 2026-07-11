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
  customer: { nome: string; telefone: string } | null
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

const HOUR_PX = 64 // altura de 1 hora na régua
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
// "Seg", "Ter"… (capitalizado, sem ponto) — cabeçalho no formato "Seg 2".
function weekdayLabel(d: Date): string {
  const s = wdFmt.format(d).replace('.', '')
  return s.charAt(0).toUpperCase() + s.slice(1)
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
      'id, inicio_at, fim_at, status, professional_id, service_id, service:services(nome), customer:customers(nome, telefone), professional:professionals(nome)',
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
// Linhas de meia hora (mais sutis que as de hora cheia) — melhora a leitura de
// posição/duração sem poluir, como nas agendas de referência.
const halfHourTops = computed(() => {
  const out: number[] = []
  for (let h = bounds.value.startHour; h < bounds.value.endHour; h++) {
    out.push((h - bounds.value.startHour) * HOUR_PX + HOUR_PX / 2)
  }
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
        <!-- Cabeçalho: "Seg 2 · Ter 3…" (sticky no topo ao rolar verticalmente).
             O dia de hoje ganha cor de destaque — referência: agendas clínicas. -->
        <div class="sticky top-0 z-20 flex border-b border-border bg-surface/95 backdrop-blur-sm">
          <div class="w-14 shrink-0" aria-hidden="true" />
          <div class="flex flex-1">
            <div
              v-for="(d, i) in weekDays"
              :key="i"
              class="flex flex-1 items-center justify-center border-l border-border py-3"
              :class="isSameDay(d, todayRef) ? 'day-head-today' : ''"
            >
              <span
                class="text-small font-semibold"
                :class="isSameDay(d, todayRef) ? 'text-accent' : 'text-text'"
                :aria-current="isSameDay(d, todayRef) ? 'date' : undefined"
              >{{ weekdayLabel(d) }} <span class="tabular">{{ d.getDate() }}</span></span>
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
              class="absolute right-2 text-caption tabular text-text-muted"
              :class="h === bounds.startHour ? 'translate-y-1' : '-translate-y-1/2'"
              :style="{ top: `${(h - bounds.startHour) * HOUR_PX}px` }"
            >{{ pad(h) }}:00</div>
          </div>

          <!-- Área das colunas -->
          <div class="relative flex-1" :style="{ height: `${bodyHeight}px` }">
            <!-- Linhas de hora cheia -->
            <div
              v-for="h in hourLabels"
              :key="`line-${h}`"
              class="pointer-events-none absolute inset-x-0 border-t border-border/70"
              :style="{ top: `${(h - bounds.startHour) * HOUR_PX}px` }"
            />
            <!-- Linhas de meia hora (mais sutis) -->
            <div
              v-for="t in halfHourTops"
              :key="`half-${t}`"
              class="pointer-events-none absolute inset-x-0 border-t border-dashed border-border/40"
              :style="{ top: `${t}px` }"
            />

            <!-- Colunas dos dias -->
            <div class="absolute inset-0 grid grid-cols-7">
              <div
                v-for="(col, i) in columns"
                :key="i"
                class="relative cursor-pointer border-l border-border"
                :class="isSameDay(weekDays[i], todayRef) ? 'col-today' : ''"
                @click="onColumnClick($event, i)"
              >
                <!-- Blocos de agendamento: cartões sólidos coloridos por status
                     (nome + horário), como na referência. O ícone do status
                     garante que a cor nunca é a única pista (§18). -->
                <button
                  v-for="b in col"
                  :key="b.id"
                  class="evt absolute flex flex-col overflow-hidden rounded-md px-2 py-1.5 text-left leading-tight transition-all duration-fast hover:z-10 hover:shadow-md hover:brightness-105"
                  :class="[`evt-${b.status}`, b.status === 'cancelado' ? 'opacity-55' : '']"
                  :style="blockStyle(b)"
                  :title="`${b.customer?.nome ?? '—'} · ${svcName(b)} · ${formatHora(b.inicio_at)}–${formatHora(b.fim_at)} · ${STATUS[b.status].label}`"
                  :aria-label="`${b.customer?.nome ?? 'Cliente'}, ${svcName(b)}, ${formatHora(b.inicio_at)} até ${formatHora(b.fim_at)}, ${STATUS[b.status].label}`"
                  @click.stop="emit('select', b)"
                >
                  <span
                    class="pointer-events-none absolute right-1.5 top-1 text-caption"
                    :class="STATUS[b.status].text"
                    aria-hidden="true"
                  >{{ STATUS[b.status].icon }}</span>
                  <p class="truncate pr-3 text-caption font-semibold text-text" :class="b.status === 'cancelado' ? 'line-through' : ''">
                    {{ b.customer?.nome ?? '—' }}
                  </p>
                  <p v-if="b.height >= 44" class="tabular truncate text-caption text-text-muted">
                    {{ formatHora(b.inicio_at) }} – {{ formatHora(b.fim_at) }}
                  </p>
                  <p v-if="b.height >= 68" class="truncate text-caption text-text-muted">
                    {{ svcName(b) }}<template v-if="isOwner && b.professional"> · {{ b.professional.nome }}</template>
                  </p>
                </button>
              </div>
            </div>

            <!-- Linha do agora: atravessa a grade inteira (vermelha, como na
                 referência) quando a semana em exibição contém o dia de hoje. -->
            <div
              v-if="todayIndex !== -1 && nowTop >= 0 && nowTop <= bodyHeight"
              class="now-line pointer-events-none absolute inset-x-0 z-10"
              :style="{ top: `${nowTop}px` }"
              aria-hidden="true"
            >
              <span class="now-dot" />
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Cartões de agendamento: fundo sólido (mistura do token de status com a
   superfície — funciona nos temas claro e escuro) + borda na mesma família.
   Sem hex cru: tudo deriva dos tokens semânticos (ADENDO §13). */
.evt {
  background: var(--evt-bg, var(--surface-2));
  border: 1px solid var(--evt-border, var(--border));
}
.evt-agendado {
  --evt-bg: color-mix(in srgb, var(--info) 22%, var(--surface));
  --evt-border: color-mix(in srgb, var(--info) 45%, transparent);
}
.evt-confirmado {
  --evt-bg: color-mix(in srgb, var(--success) 22%, var(--surface));
  --evt-border: color-mix(in srgb, var(--success) 45%, transparent);
}
.evt-no_show {
  --evt-bg: color-mix(in srgb, var(--warning) 22%, var(--surface));
  --evt-border: color-mix(in srgb, var(--warning) 45%, transparent);
}
.evt-concluido {
  --evt-bg: var(--surface-2);
  --evt-border: var(--border);
}
.evt-cancelado {
  --evt-bg: color-mix(in srgb, var(--danger) 12%, var(--surface));
  --evt-border: color-mix(in srgb, var(--danger) 30%, transparent);
}

/* Hoje: cabeçalho e coluna com um véu sutil do accent, guiando o olho sem
   competir com os cartões. */
.day-head-today {
  background: color-mix(in srgb, var(--accent) 8%, transparent);
}
.col-today {
  background: color-mix(in srgb, var(--accent) 4%, transparent);
}

/* Linha do "agora": vermelha, atravessando todos os dias (referência Codental). */
.now-line {
  height: 2px;
  background: var(--danger);
}
.now-dot {
  position: absolute;
  left: 0;
  top: 50%;
  width: 8px;
  height: 8px;
  transform: translate(-50%, -50%);
  border-radius: 999px;
  background: var(--danger);
}
</style>
