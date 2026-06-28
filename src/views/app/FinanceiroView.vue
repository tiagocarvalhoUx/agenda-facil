<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { formatPreco, formatHora } from '@/lib/format'
import { STATUS } from '@/lib/appointmentStatus'
import type { AppointmentStatus } from '@/types/database.types'
import PageHeader from '@/components/app/PageHeader.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import BaseSkeleton from '@/components/ui/BaseSkeleton.vue'
import {
  Wallet,
  Receipt,
  CheckCircle,
  TrendingDown,
  CalendarClock,
  Scissors,
  UserRound,
  Download,
} from '@lucide/vue'

// Financeiro (owner). Visão de caixa derivada dos agendamentos: faturamento
// realizado (concluídos × preço do serviço), ticket médio, pipeline a receber,
// perdas (no-show/cancelado) e quebras por serviço/profissional + tendência
// diária. Sem dados novos no banco — agrega o que a RLS já entrega ao dono.
// O preço usado é o atual do serviço (mesma base do faturamento do Dashboard).

interface Row {
  inicio_at: string
  status: AppointmentStatus
  preco_total: number | null // preço congelado na criação (snapshot)
  service: { nome: string; preco: number } | null
  professional: { nome: string } | null
}

const dias = ref(30)
const loading = ref(true)
const errored = ref(false)
const rows = ref<Row[]>([]) // período (start..agora)
const future = ref<Row[]>([]) // pipeline (agora..+30d)

const SELECT = 'inicio_at, status, preco_total, service:services(nome, preco), professional:professionals(nome)'

async function load() {
  loading.value = true
  errored.value = false
  const now = new Date()
  const start = new Date(now)
  start.setDate(start.getDate() - dias.value)
  const futureEnd = new Date(now)
  futureEnd.setDate(futureEnd.getDate() + 30)

  const [periodo, pipeline] = await Promise.all([
    supabase
      .from('appointments')
      .select(SELECT)
      .gte('inicio_at', start.toISOString())
      .lte('inicio_at', now.toISOString())
      .is('deleted_at', null),
    supabase
      .from('appointments')
      .select(SELECT)
      .gt('inicio_at', now.toISOString())
      .lte('inicio_at', futureEnd.toISOString())
      .in('status', ['agendado', 'confirmado'])
      .is('deleted_at', null),
  ])

  if (periodo.error || pipeline.error) {
    errored.value = true
  } else {
    rows.value = (periodo.data as unknown as Row[]) ?? []
    future.value = (pipeline.data as unknown as Row[]) ?? []
  }
  loading.value = false
}
onMounted(load)

function setDias(n: number) {
  dias.value = n
  void load()
}

// Preço congelado (snapshot) quando existir; senão, preço atual do serviço.
const preco = (r: Row) => r.preco_total ?? r.service?.preco ?? 0

// ---- Métricas principais ----
const concluidos = computed(() => rows.value.filter((r) => r.status === 'concluido'))
const realizado = computed(() => concluidos.value.reduce((s, r) => s + preco(r), 0))
const ticketMedio = computed(() => (concluidos.value.length ? realizado.value / concluidos.value.length : 0))
const perdas = computed(() =>
  rows.value.filter((r) => r.status === 'no_show' || r.status === 'cancelado').reduce((s, r) => s + preco(r), 0),
)
const aReceber = computed(() => future.value.reduce((s, r) => s + preco(r), 0))

// ---- Quebras (ranking com barra proporcional) ----
function agrupar(getKey: (r: Row) => string) {
  const map = new Map<string, number>()
  for (const r of concluidos.value) {
    const k = getKey(r)
    map.set(k, (map.get(k) ?? 0) + preco(r))
  }
  return [...map.entries()]
    .map(([nome, valor]) => ({ nome, valor }))
    .sort((a, b) => b.valor - a.valor)
}
const porServico = computed(() => agrupar((r) => r.service?.nome ?? '—'))
const porProfissional = computed(() => agrupar((r) => r.professional?.nome ?? '—'))
const maxServico = computed(() => Math.max(1, ...porServico.value.map((x) => x.valor)))
const maxProf = computed(() => Math.max(1, ...porProfissional.value.map((x) => x.valor)))

// ---- Série diária (tendência do faturamento realizado) ----
const diaKey = (iso: string) =>
  new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Sao_Paulo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date(iso))

const serie = computed(() => {
  const porDia = new Map<string, number>()
  for (const r of concluidos.value) porDia.set(diaKey(r.inicio_at), (porDia.get(diaKey(r.inicio_at)) ?? 0) + preco(r))
  // gera um bucket por dia do período (inclui dias zerados p/ a linha do tempo)
  const buckets: { key: string; valor: number }[] = []
  const d = new Date()
  d.setDate(d.getDate() - dias.value + 1)
  for (let i = 0; i < dias.value; i++) {
    const k = diaKey(d.toISOString())
    buckets.push({ key: k, valor: porDia.get(k) ?? 0 })
    d.setDate(d.getDate() + 1)
  }
  return buckets
})
const maxSerie = computed(() => Math.max(1, ...serie.value.map((b) => b.valor)))
const serieLabel = (k: string) => {
  const [, m, dd] = k.split('-')
  return `${dd}/${m}`
}

const semMovimento = computed(
  () => !loading.value && !errored.value && realizado.value === 0 && perdas.value === 0 && aReceber.value === 0,
)

// ---- Exportar CSV do período (compatível com Excel/Sheets pt-BR) ----
// Separador ';' e decimal com vírgula; BOM UTF-8 preserva acentos.
function exportarCsv() {
  const dataBR = (iso: string) =>
    new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric', timeZone: 'America/Sao_Paulo' }).format(new Date(iso))
  const head = ['Data', 'Hora', 'Serviço', 'Profissional', 'Status', 'Valor (R$)']
  const linhas = [...rows.value]
    .sort((a, b) => a.inicio_at.localeCompare(b.inicio_at))
    .map((r) => [
      dataBR(r.inicio_at),
      formatHora(r.inicio_at),
      r.service?.nome ?? '—',
      r.professional?.nome ?? '—',
      STATUS[r.status].label,
      preco(r).toFixed(2).replace('.', ','),
    ])
  const esc = (c: string | number) => `"${String(c).replace(/"/g, '""')}"`
  const csv = [head, ...linhas].map((cols) => cols.map(esc).join(';')).join('\r\n')
  const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `financeiro-${dias.value}d-${new Date().toISOString().slice(0, 10)}.csv`
  a.click()
  URL.revokeObjectURL(url)
}
</script>

<template>
  <div class="mx-auto max-w-5xl p-4 sm:p-5">
    <PageHeader eyebrow="Financeiro" title="Financeiro">
      <template #actions>
        <div class="flex items-center gap-2">
          <div class="inline-flex items-center gap-1 rounded-pill border border-border bg-surface/70 p-1 shadow-card backdrop-blur-sm">
            <button
              v-for="n in [7, 30, 90]"
              :key="n"
              class="h-9 rounded-pill px-3.5 text-small font-semibold transition-colors duration-fast"
              :class="dias === n ? 'bg-accent text-on-accent shadow-glow' : 'text-text-muted hover:text-text'"
              @click="setDias(n)"
            >{{ n }}d</button>
          </div>
          <button
            class="flex h-11 items-center gap-2 rounded-lg border border-border bg-surface px-3.5 text-small font-semibold text-text shadow-card transition-colors hover:bg-surface-2 disabled:opacity-50"
            :disabled="loading || rows.length === 0"
            aria-label="Exportar CSV"
            @click="exportarCsv"
          >
            <Download class="h-4 w-4" :stroke-width="2" />
            <span class="hidden sm:inline">CSV</span>
          </button>
        </div>
      </template>
    </PageHeader>

    <!-- loading -->
    <div v-if="loading" class="flex flex-col gap-3">
      <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <BaseSkeleton v-for="n in 4" :key="n" height="128px" rounded="xl" />
      </div>
      <BaseSkeleton height="220px" rounded="2xl" />
    </div>

    <EmptyState
      v-else-if="errored"
      icon="📡"
      title="Não foi possível carregar"
      description="Verifique sua conexão e tente novamente."
      cta-label="Tentar de novo"
      @cta="load"
    />

    <EmptyState
      v-else-if="semMovimento"
      icon="💸"
      title="Sem movimento financeiro no período"
      description="Conclua agendamentos para acompanhar o faturamento aqui."
    />

    <template v-else>
      <!-- KPIs -->
      <div class="stagger grid grid-cols-2 gap-3 lg:grid-cols-4">
        <div class="rounded-xl border border-border bg-surface p-5 shadow-card">
          <span class="flex h-9 w-9 items-center justify-center rounded-lg bg-success/15 text-success"><Wallet class="h-5 w-5" :stroke-width="2" /></span>
          <p class="tabular mt-3 text-h1 font-display leading-tight text-text">{{ formatPreco(realizado) }}</p>
          <p class="mt-1.5 text-caption text-text-muted">faturamento realizado*</p>
        </div>
        <div class="rounded-xl border border-border bg-surface p-5 shadow-card">
          <span class="flex h-9 w-9 items-center justify-center rounded-lg bg-accent-soft text-accent ring-1 ring-inset ring-[color-mix(in_srgb,var(--accent)_30%,transparent)]"><Receipt class="h-5 w-5" :stroke-width="2" /></span>
          <p class="tabular mt-3 text-h1 font-display leading-tight text-text">{{ formatPreco(ticketMedio) }}</p>
          <p class="mt-1.5 text-caption text-text-muted">ticket médio</p>
        </div>
        <div class="rounded-xl border border-border bg-surface p-5 shadow-card">
          <span class="flex h-9 w-9 items-center justify-center rounded-lg bg-info/15 text-info"><CalendarClock class="h-5 w-5" :stroke-width="2" /></span>
          <p class="tabular mt-3 text-h1 font-display leading-tight text-text">{{ formatPreco(aReceber) }}</p>
          <p class="mt-1.5 text-caption text-text-muted">a receber · próx. 30 dias</p>
        </div>
        <div class="rounded-xl border border-border bg-surface p-5 shadow-card">
          <span class="flex h-9 w-9 items-center justify-center rounded-lg" :class="perdas > 0 ? 'bg-warning/15 text-warning' : 'bg-surface-2 text-text-muted'"><TrendingDown class="h-5 w-5" :stroke-width="2" /></span>
          <p class="tabular mt-3 text-h1 font-display leading-tight" :class="perdas > 0 ? 'text-warning' : 'text-text'">{{ formatPreco(perdas) }}</p>
          <p class="mt-1.5 text-caption text-text-muted">perdas · no-show + cancelados</p>
        </div>
      </div>

      <!-- Tendência diária + resumo de concluídos -->
      <section class="mt-3 rounded-2xl border border-border bg-surface p-5 shadow-card sm:p-6">
        <div class="mb-4 flex items-center justify-between gap-3">
          <h2 class="text-h2 font-display text-text">Faturamento por dia</h2>
          <span class="inline-flex items-center gap-1.5 rounded-pill bg-success/15 px-2.5 py-1 text-caption font-medium text-success">
            <CheckCircle class="h-3.5 w-3.5" :stroke-width="2.5" /> {{ concluidos.length }} concluído(s)
          </span>
        </div>
        <div class="flex h-36 items-end gap-px sm:gap-0.5" role="img" aria-label="Gráfico de faturamento diário">
          <div
            v-for="b in serie"
            :key="b.key"
            class="group relative flex-1 rounded-t-sm transition-colors"
            :class="b.valor > 0 ? 'bg-accent hover:bg-accent-hover' : 'bg-surface-2'"
            :style="{ height: b.valor > 0 ? Math.max(6, (b.valor / maxSerie) * 100) + '%' : '4px' }"
            :title="`${serieLabel(b.key)} · ${formatPreco(b.valor)}`"
          />
        </div>
        <div class="mt-2 flex justify-between text-caption text-text-muted">
          <span>{{ serie.length ? serieLabel(serie[0].key) : '' }}</span>
          <span>{{ serie.length ? serieLabel(serie[serie.length - 1].key) : '' }}</span>
        </div>
      </section>

      <!-- Quebras por serviço e profissional -->
      <div class="mt-3 grid gap-3 lg:grid-cols-2">
        <section class="rounded-2xl border border-border bg-surface p-5 shadow-card sm:p-6">
          <h2 class="mb-4 flex items-center gap-2.5 text-h2 font-display text-text">
            <span class="flex h-9 w-9 items-center justify-center rounded-lg bg-accent-soft text-accent"><Scissors class="h-5 w-5" :stroke-width="2" /></span>
            Por serviço
          </h2>
          <p v-if="porServico.length === 0" class="text-small text-text-muted">Nenhum concluído no período.</p>
          <ul v-else class="flex flex-col gap-3">
            <li v-for="s in porServico" :key="s.nome" class="flex flex-col gap-1.5">
              <div class="flex items-center justify-between gap-3">
                <span class="truncate text-small text-text">{{ s.nome }}</span>
                <span class="tabular shrink-0 text-small font-semibold text-text">{{ formatPreco(s.valor) }}</span>
              </div>
              <div class="h-2 overflow-hidden rounded-pill bg-surface-2">
                <div class="h-full rounded-pill bg-accent" :style="{ width: (s.valor / maxServico) * 100 + '%' }" />
              </div>
            </li>
          </ul>
        </section>

        <section class="rounded-2xl border border-border bg-surface p-5 shadow-card sm:p-6">
          <h2 class="mb-4 flex items-center gap-2.5 text-h2 font-display text-text">
            <span class="flex h-9 w-9 items-center justify-center rounded-lg bg-accent-soft text-accent"><UserRound class="h-5 w-5" :stroke-width="2" /></span>
            Por profissional
          </h2>
          <p v-if="porProfissional.length === 0" class="text-small text-text-muted">Nenhum concluído no período.</p>
          <ul v-else class="flex flex-col gap-3">
            <li v-for="p in porProfissional" :key="p.nome" class="flex flex-col gap-1.5">
              <div class="flex items-center justify-between gap-3">
                <span class="truncate text-small text-text">{{ p.nome }}</span>
                <span class="tabular shrink-0 text-small font-semibold text-text">{{ formatPreco(p.valor) }}</span>
              </div>
              <div class="h-2 overflow-hidden rounded-pill bg-surface-2">
                <div class="h-full rounded-pill bg-info" :style="{ width: (p.valor / maxProf) * 100 + '%' }" />
              </div>
            </li>
          </ul>
        </section>
      </div>

      <p class="mt-3 text-caption text-text-muted">
        * Faturamento estimado pela soma do preço atual dos serviços concluídos. Valores de referência, não substituem o controle fiscal.
      </p>
    </template>
  </div>
</template>
