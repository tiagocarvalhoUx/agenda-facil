<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { ChevronLeft, ChevronRight } from '@lucide/vue'

// Mini calendário mensal (referência: sidebar de agendas clínicas). Navega o
// mês com ‹ › e emite a data clicada — a AgendaView pula para o dia/semana.
// Semana começa na segunda (mesma convenção da grade). Sem dados próprios:
// é um controle de navegação puro.

const props = defineProps<{
  modelValue: Date
  // Datas antes deste dia ficam desabilitadas (a agenda não navega ao passado).
  minDate?: Date
  // Destaca a semana inteira da data selecionada (modo grade).
  highlightWeek?: boolean
}>()

const emit = defineEmits<{ 'update:modelValue': [d: Date] }>()

function startOfDay(d: Date): Date {
  const x = new Date(d)
  x.setHours(0, 0, 0, 0)
  return x
}
function mondayOf(d: Date): Date {
  const x = startOfDay(d)
  const dow = x.getDay() // 0=dom .. 6=sáb
  x.setDate(x.getDate() + (dow === 0 ? -6 : 1 - dow))
  return x
}
function isSameDay(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}

// Mês em exibição — acompanha a data selecionada quando ela muda por fora
// (ex.: navegação ‹ Hoje › do hero).
const viewMonth = ref(new Date(props.modelValue.getFullYear(), props.modelValue.getMonth(), 1))
watch(
  () => props.modelValue.getTime(),
  () => {
    viewMonth.value = new Date(props.modelValue.getFullYear(), props.modelValue.getMonth(), 1)
  },
)

const monthFmt = new Intl.DateTimeFormat('pt-BR', { month: 'long', year: 'numeric' })
const monthLabel = computed(() => {
  const s = monthFmt.format(viewMonth.value)
  return s.charAt(0).toUpperCase() + s.slice(1)
})
const dayFmt = new Intl.DateTimeFormat('pt-BR', { dateStyle: 'full' })

// Iniciais seg→dom, como na referência (S T Q Q S S D).
const WEEKDAYS = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D']

interface Cell {
  date: Date
  inMonth: boolean
  disabled: boolean
  today: boolean
  selected: boolean
  inSelWeek: boolean
  weekStart: boolean
  weekEnd: boolean
}

// Sempre 6 semanas (42 células): altura estável ao trocar de mês.
const cells = computed<Cell[]>(() => {
  const start = mondayOf(viewMonth.value)
  const today = startOfDay(new Date())
  const min = props.minDate ? startOfDay(props.minDate) : null
  const selWeek = props.highlightWeek ? mondayOf(props.modelValue).getTime() : NaN
  return Array.from({ length: 42 }, (_, i) => {
    const d = new Date(start)
    d.setDate(start.getDate() + i)
    return {
      date: d,
      inMonth: d.getMonth() === viewMonth.value.getMonth(),
      disabled: min !== null && d < min,
      today: isSameDay(d, today),
      selected: isSameDay(d, props.modelValue),
      inSelWeek: mondayOf(d).getTime() === selWeek,
      weekStart: i % 7 === 0,
      weekEnd: i % 7 === 6,
    }
  })
})

function prev() {
  viewMonth.value = new Date(viewMonth.value.getFullYear(), viewMonth.value.getMonth() - 1, 1)
}
function next() {
  viewMonth.value = new Date(viewMonth.value.getFullYear(), viewMonth.value.getMonth() + 1, 1)
}
</script>

<template>
  <div class="rounded-2xl border border-border bg-surface p-3 shadow-card">
    <!-- Mês + navegação -->
    <div class="mb-2 flex items-center justify-between gap-1 px-1">
      <p class="text-small font-semibold text-text">{{ monthLabel }}</p>
      <div class="flex items-center">
        <button
          class="flex h-8 w-8 items-center justify-center rounded-full text-text-muted transition-colors duration-fast hover:bg-surface-2 hover:text-text"
          aria-label="Mês anterior"
          @click="prev"
        >
          <ChevronLeft class="h-4 w-4" :stroke-width="2.25" />
        </button>
        <button
          class="flex h-8 w-8 items-center justify-center rounded-full text-text-muted transition-colors duration-fast hover:bg-surface-2 hover:text-text"
          aria-label="Próximo mês"
          @click="next"
        >
          <ChevronRight class="h-4 w-4" :stroke-width="2.25" />
        </button>
      </div>
    </div>

    <!-- Cabeçalho S T Q Q S S D -->
    <div class="grid grid-cols-7" aria-hidden="true">
      <span v-for="(w, i) in WEEKDAYS" :key="i" class="py-1 text-center text-caption text-text-muted">{{ w }}</span>
    </div>

    <!-- Dias (6 semanas fixas) -->
    <div class="grid grid-cols-7">
      <div
        v-for="c in cells"
        :key="c.date.getTime()"
        class="flex justify-center py-0.5"
        :class="[
          c.inSelWeek ? 'sel-week' : '',
          c.inSelWeek && c.weekStart ? 'sel-week-start' : '',
          c.inSelWeek && c.weekEnd ? 'sel-week-end' : '',
        ]"
      >
        <button
          class="tabular flex h-8 w-8 items-center justify-center rounded-full text-small transition-colors duration-fast"
          :class="[
            c.selected
              ? 'bg-accent font-semibold text-on-accent shadow-glow'
              : c.today
                ? 'day-today font-semibold text-accent'
                : c.inMonth
                  ? 'text-text hover:bg-surface-2'
                  : 'text-text-muted opacity-50 hover:bg-surface-2',
            c.disabled ? 'pointer-events-none opacity-25' : '',
          ]"
          :disabled="c.disabled"
          :aria-label="dayFmt.format(c.date)"
          :aria-current="c.today ? 'date' : undefined"
          :aria-pressed="c.selected"
          @click="emit('update:modelValue', c.date)"
        >{{ c.date.getDate() }}</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Semana selecionada (modo grade): faixa contínua sutil no accent. color-mix
   direto — modificador de opacidade do Tailwind não funciona em tokens var(). */
.sel-week {
  background: color-mix(in srgb, var(--accent) 10%, transparent);
}
.sel-week-start {
  border-radius: 999px 0 0 999px;
}
.sel-week-end {
  border-radius: 0 999px 999px 0;
}
/* Hoje (quando não selecionado): anel fino no accent. */
.day-today {
  box-shadow: inset 0 0 0 1.5px var(--accent);
}
</style>
