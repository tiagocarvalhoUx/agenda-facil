<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
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
  FileText,
} from '@lucide/vue'

// Financeiro (owner). Visão de caixa derivada dos agendamentos: faturamento
// realizado (concluídos × preço congelado), ticket médio, pipeline a receber,
// perdas (no-show/cancelado), quebras por serviço/profissional + tendência
// diária — com COMPARATIVO vs. período anterior, FILTRO por profissional e
// FECHAMENTO em PDF. Sem dados novos no banco: agrega o que a RLS entrega ao dono.

const auth = useAuthStore()

interface Row {
  inicio_at: string
  status: AppointmentStatus
  preco_total: number | null
  professional_id: string
  service: { nome: string; preco: number } | null
  professional: { nome: string } | null
}

const dias = ref(30)
const loading = ref(true)
const errored = ref(false)
const rows = ref<Row[]>([]) // período atual (start..agora)
const prev = ref<Row[]>([]) // período anterior (comparativo)
const future = ref<Row[]>([]) // pipeline (agora..+30d)
const professionals = ref<{ id: string; nome: string }[]>([])
const profFiltro = ref<string | null>(null) // null = todos

const SELECT =
  'inicio_at, status, preco_total, professional_id, service:services(nome, preco), professional:professionals(nome)'

async function load() {
  loading.value = true
  errored.value = false
  const now = new Date()
  const start = new Date(now)
  start.setDate(start.getDate() - dias.value)
  const prevStart = new Date(now)
  prevStart.setDate(prevStart.getDate() - dias.value * 2)
  const futureEnd = new Date(now)
  futureEnd.setDate(futureEnd.getDate() + 30)

  const [periodo, anterior, pipeline] = await Promise.all([
    // Sem teto em "agora": um agendamento concluído é faturamento realizado
    // mesmo que o horário seja hoje mais tarde (ou futuro, em testes). Os
    // agendado/confirmado futuros entram aqui, mas não somam em nenhuma métrica
    // (só 'concluido' vira realizado e 'no_show'/'cancelado' viram perdas).
    supabase.from('appointments').select(SELECT).gte('inicio_at', start.toISOString()).is('deleted_at', null),
    supabase.from('appointments').select(SELECT).gte('inicio_at', prevStart.toISOString()).lt('inicio_at', start.toISOString()).is('deleted_at', null),
    supabase.from('appointments').select(SELECT).gt('inicio_at', now.toISOString()).lte('inicio_at', futureEnd.toISOString()).in('status', ['agendado', 'confirmado']).is('deleted_at', null),
  ])

  if (periodo.error || anterior.error || pipeline.error) {
    errored.value = true
  } else {
    rows.value = (periodo.data as unknown as Row[]) ?? []
    prev.value = (anterior.data as unknown as Row[]) ?? []
    future.value = (pipeline.data as unknown as Row[]) ?? []
  }

  if (professionals.value.length === 0) {
    const { data } = await supabase.from('professionals').select('id, nome').is('deleted_at', null).order('nome')
    professionals.value = (data as { id: string; nome: string }[]) ?? []
  }
  loading.value = false
}
onMounted(load)

function setDias(n: number) {
  dias.value = n
  void load()
}

const preco = (r: Row) => r.preco_total ?? r.service?.preco ?? 0

// Aplica o filtro de profissional (client-side) a qualquer recorte.
const aplicaFiltro = (list: Row[]) => (profFiltro.value ? list.filter((r) => r.professional_id === profFiltro.value) : list)
const rowsF = computed(() => aplicaFiltro(rows.value))
const futureF = computed(() => aplicaFiltro(future.value))
const prevF = computed(() => aplicaFiltro(prev.value))

const profNome = computed(() => professionals.value.find((p) => p.id === profFiltro.value)?.nome ?? 'Todos')

// ---- Métricas (período atual) ----
function metricas(list: Row[]) {
  const conc = list.filter((r) => r.status === 'concluido')
  const realizado = conc.reduce((s, r) => s + preco(r), 0)
  return {
    conc,
    realizado,
    ticket: conc.length ? realizado / conc.length : 0,
    perdas: list.filter((r) => r.status === 'no_show' || r.status === 'cancelado').reduce((s, r) => s + preco(r), 0),
  }
}
const cur = computed(() => metricas(rowsF.value))
const ant = computed(() => metricas(prevF.value))
const concluidos = computed(() => cur.value.conc)
const realizado = computed(() => cur.value.realizado)
const ticketMedio = computed(() => cur.value.ticket)
const perdas = computed(() => cur.value.perdas)
const aReceber = computed(() => futureF.value.reduce((s, r) => s + preco(r), 0))

// ---- Comparativo vs. período anterior ----
// Retorna o % de variação e a direção; null quando não há base anterior.
function delta(atual: number, anterior: number) {
  if (anterior <= 0) return null
  const pct = ((atual - anterior) / anterior) * 100
  return { pct, up: pct >= 0 }
}
const dRealizado = computed(() => delta(realizado.value, ant.value.realizado))
const dTicket = computed(() => delta(ticketMedio.value, ant.value.ticket))
const dPerdas = computed(() => delta(perdas.value, ant.value.perdas))

// ---- Quebras (ranking com barra) ----
function agrupar(getKey: (r: Row) => string) {
  const map = new Map<string, { valor: number; qtd: number }>()
  for (const r of concluidos.value) {
    const k = getKey(r)
    const e = map.get(k) ?? { valor: 0, qtd: 0 }
    e.valor += preco(r)
    e.qtd += 1
    map.set(k, e)
  }
  return [...map.entries()].map(([nome, v]) => ({ nome, ...v })).sort((a, b) => b.valor - a.valor)
}
const porServico = computed(() => agrupar((r) => r.service?.nome ?? '—'))
const porProfissional = computed(() => agrupar((r) => r.professional?.nome ?? '—'))
const maxServico = computed(() => Math.max(1, ...porServico.value.map((x) => x.valor)))
const maxProf = computed(() => Math.max(1, ...porProfissional.value.map((x) => x.valor)))

// ---- Série diária ----
const diaKey = (iso: string) =>
  new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(iso))
const serie = computed(() => {
  const porDia = new Map<string, number>()
  for (const r of concluidos.value) porDia.set(diaKey(r.inicio_at), (porDia.get(diaKey(r.inicio_at)) ?? 0) + preco(r))
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

const dataBR = (iso: string) =>
  new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric', timeZone: 'America/Sao_Paulo' }).format(new Date(iso))
const periodoLabel = computed(() => {
  const fim = new Date()
  const ini = new Date(fim)
  ini.setDate(ini.getDate() - dias.value)
  return `${dataBR(ini.toISOString())} a ${dataBR(fim.toISOString())}`
})

// ---- Exportar CSV do período ----
function exportarCsv() {
  const head = ['Data', 'Hora', 'Serviço', 'Profissional', 'Status', 'Valor (R$)']
  const linhas = [...rowsF.value]
    .sort((a, b) => a.inicio_at.localeCompare(b.inicio_at))
    .map((r) => [dataBR(r.inicio_at), formatHora(r.inicio_at), r.service?.nome ?? '—', r.professional?.nome ?? '—', STATUS[r.status].label, preco(r).toFixed(2).replace('.', ',')])
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

// ---- PDF de fechamento (abre uma janela limpa e dispara a impressão) ----
function fecharPdf() {
  const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  const tenant = esc(auth.tenant?.nome ?? 'Estabelecimento')
  const linhaServ = porServico.value
    .map((s) => `<tr><td>${esc(s.nome)}</td><td class="n">${s.qtd}</td><td class="n">${formatPreco(s.valor)}</td></tr>`)
    .join('')
  const linhaProf = porProfissional.value
    .map((p) => `<tr><td>${esc(p.nome)}</td><td class="n">${p.qtd}</td><td class="n">${formatPreco(p.valor)}</td></tr>`)
    .join('')
  const kpi = (label: string, valor: string) => `<div class="kpi"><span>${label}</span><strong>${valor}</strong></div>`
  const html = `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>Fechamento — ${tenant}</title>
<style>
  *{box-sizing:border-box} body{font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;color:#111827;margin:32px;font-size:13px}
  h1{font-size:20px;margin:0} .sub{color:#6b7280;margin:2px 0 0}
  .head{display:flex;justify-content:space-between;align-items:flex-start;border-bottom:2px solid #111827;padding-bottom:12px;margin-bottom:16px}
  .grid{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin:16px 0}
  .kpi{border:1px solid #e5e7eb;border-radius:10px;padding:10px 12px} .kpi span{color:#6b7280;display:block;font-size:11px} .kpi strong{font-size:16px}
  h2{font-size:14px;margin:20px 0 8px;border-bottom:1px solid #e5e7eb;padding-bottom:4px}
  table{width:100%;border-collapse:collapse} td,th{padding:6px 8px;text-align:left;border-bottom:1px solid #f0f0f0} th{color:#6b7280;font-weight:600;font-size:11px;text-transform:uppercase}
  td.n,th.n{text-align:right} tfoot td{font-weight:700;border-top:2px solid #111827}
  .foot{color:#9ca3af;font-size:10px;margin-top:24px}
</style></head><body>
  <div class="head">
    <div><h1>${tenant}</h1><p class="sub">Fechamento financeiro · ${periodoLabel.value}</p><p class="sub">Profissional: ${esc(profNome.value)}</p></div>
    <div class="sub" style="text-align:right">Gerado em<br>${dataBR(new Date().toISOString())} ${formatHora(new Date().toISOString())}</div>
  </div>
  <div class="grid">
    ${kpi('Faturamento realizado', formatPreco(realizado.value))}
    ${kpi('Ticket médio', formatPreco(ticketMedio.value))}
    ${kpi('Atendimentos concluídos', String(concluidos.value.length))}
    ${kpi('Perdas (no-show + canc.)', formatPreco(perdas.value))}
  </div>
  <h2>Por serviço</h2>
  <table><thead><tr><th>Serviço</th><th class="n">Qtd</th><th class="n">Valor</th></tr></thead>
  <tbody>${linhaServ || '<tr><td colspan="3">Sem concluídos no período.</td></tr>'}</tbody>
  <tfoot><tr><td>Total</td><td class="n">${concluidos.value.length}</td><td class="n">${formatPreco(realizado.value)}</td></tr></tfoot></table>
  <h2>Por profissional</h2>
  <table><thead><tr><th>Profissional</th><th class="n">Qtd</th><th class="n">Valor</th></tr></thead>
  <tbody>${linhaProf || '<tr><td colspan="3">Sem concluídos no período.</td></tr>'}</tbody></table>
  <p class="foot">* Faturamento estimado pela soma do preço dos serviços concluídos. Valores de referência, não substituem o controle fiscal.</p>
  <script>window.onload=function(){window.print()}<\/script>
</body></html>`
  const w = window.open('', '_blank')
  if (!w) return
  w.document.write(html)
  w.document.close()
}
</script>

<template>
  <div class="mx-auto max-w-5xl p-4 sm:p-5">
    <PageHeader eyebrow="Financeiro" title="Financeiro">
      <template #actions>
        <div class="flex flex-wrap items-center justify-end gap-2">
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
            <Download class="h-4 w-4" :stroke-width="2" /><span class="hidden sm:inline">CSV</span>
          </button>
          <button
            class="flex h-11 items-center gap-2 rounded-lg border border-border bg-surface px-3.5 text-small font-semibold text-text shadow-card transition-colors hover:bg-surface-2 disabled:opacity-50"
            :disabled="loading || rows.length === 0"
            aria-label="Fechamento em PDF"
            @click="fecharPdf"
          >
            <FileText class="h-4 w-4" :stroke-width="2" /><span class="hidden sm:inline">PDF</span>
          </button>
        </div>
      </template>
    </PageHeader>

    <!-- Filtro por profissional -->
    <div v-if="professionals.length > 1" class="mb-4 flex flex-wrap items-center gap-2">
      <button
        class="rounded-pill border px-3.5 py-1.5 text-small font-medium transition-colors"
        :class="profFiltro === null ? 'border-accent bg-accent-soft text-text' : 'border-border text-text-muted hover:text-text'"
        @click="profFiltro = null"
      >Todos</button>
      <button
        v-for="p in professionals"
        :key="p.id"
        class="rounded-pill border px-3.5 py-1.5 text-small font-medium transition-colors"
        :class="profFiltro === p.id ? 'border-accent bg-accent-soft text-text' : 'border-border text-text-muted hover:text-text'"
        @click="profFiltro = p.id"
      >{{ p.nome }}</button>
    </div>

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
      :description="profFiltro ? 'Sem dados para este profissional. Tente outro período ou ‘Todos’.' : 'Conclua agendamentos para acompanhar o faturamento aqui.'"
    />

    <template v-else>
      <!-- KPIs com comparativo vs. período anterior -->
      <div class="stagger grid grid-cols-2 gap-3 lg:grid-cols-4">
        <div class="rounded-xl border border-border bg-surface p-5 shadow-card">
          <span class="flex h-9 w-9 items-center justify-center rounded-lg bg-success/15 text-success"><Wallet class="h-5 w-5" :stroke-width="2" /></span>
          <p class="tabular mt-3 text-h1 font-display leading-tight text-text">{{ formatPreco(realizado) }}</p>
          <div class="mt-1.5 flex items-center gap-2">
            <span class="text-caption text-text-muted">faturamento realizado*</span>
            <span v-if="dRealizado" class="tabular shrink-0 text-caption font-semibold" :class="dRealizado.up ? 'text-success' : 'text-danger'">{{ dRealizado.up ? '↑' : '↓' }} {{ Math.abs(dRealizado.pct).toFixed(0) }}%</span>
          </div>
        </div>
        <div class="rounded-xl border border-border bg-surface p-5 shadow-card">
          <span class="flex h-9 w-9 items-center justify-center rounded-lg bg-accent-soft text-accent ring-1 ring-inset ring-[color-mix(in_srgb,var(--accent)_30%,transparent)]"><Receipt class="h-5 w-5" :stroke-width="2" /></span>
          <p class="tabular mt-3 text-h1 font-display leading-tight text-text">{{ formatPreco(ticketMedio) }}</p>
          <div class="mt-1.5 flex items-center gap-2">
            <span class="text-caption text-text-muted">ticket médio</span>
            <span v-if="dTicket" class="tabular shrink-0 text-caption font-semibold" :class="dTicket.up ? 'text-success' : 'text-danger'">{{ dTicket.up ? '↑' : '↓' }} {{ Math.abs(dTicket.pct).toFixed(0) }}%</span>
          </div>
        </div>
        <div class="rounded-xl border border-border bg-surface p-5 shadow-card">
          <span class="flex h-9 w-9 items-center justify-center rounded-lg bg-info/15 text-info"><CalendarClock class="h-5 w-5" :stroke-width="2" /></span>
          <p class="tabular mt-3 text-h1 font-display leading-tight text-text">{{ formatPreco(aReceber) }}</p>
          <p class="mt-1.5 text-caption text-text-muted">a receber · próx. 30 dias</p>
        </div>
        <div class="rounded-xl border border-border bg-surface p-5 shadow-card">
          <span class="flex h-9 w-9 items-center justify-center rounded-lg" :class="perdas > 0 ? 'bg-warning/15 text-warning' : 'bg-surface-2 text-text-muted'"><TrendingDown class="h-5 w-5" :stroke-width="2" /></span>
          <p class="tabular mt-3 text-h1 font-display leading-tight" :class="perdas > 0 ? 'text-warning' : 'text-text'">{{ formatPreco(perdas) }}</p>
          <div class="mt-1.5 flex items-center gap-2">
            <span class="text-caption text-text-muted">perdas · no-show + canc.</span>
            <span v-if="dPerdas" class="tabular shrink-0 text-caption font-semibold" :class="dPerdas.up ? 'text-danger' : 'text-success'">{{ dPerdas.up ? '↑' : '↓' }} {{ Math.abs(dPerdas.pct).toFixed(0) }}%</span>
          </div>
        </div>
      </div>
      <p class="mt-2 text-caption text-text-muted">Comparativo vs. período anterior de {{ dias }} dias.</p>

      <!-- Tendência diária -->
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
            class="flex-1 rounded-t-sm transition-colors"
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

      <!-- Quebras -->
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
                <span class="truncate text-small text-text">{{ s.nome }} <span class="text-text-muted">· {{ s.qtd }}</span></span>
                <span class="tabular shrink-0 text-small font-semibold text-text">{{ formatPreco(s.valor) }}</span>
              </div>
              <div class="h-2 overflow-hidden rounded-pill bg-surface-2"><div class="h-full rounded-pill bg-accent" :style="{ width: (s.valor / maxServico) * 100 + '%' }" /></div>
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
                <span class="truncate text-small text-text">{{ p.nome }} <span class="text-text-muted">· {{ p.qtd }}</span></span>
                <span class="tabular shrink-0 text-small font-semibold text-text">{{ formatPreco(p.valor) }}</span>
              </div>
              <div class="h-2 overflow-hidden rounded-pill bg-surface-2"><div class="h-full rounded-pill bg-info" :style="{ width: (p.valor / maxProf) * 100 + '%' }" /></div>
            </li>
          </ul>
        </section>
      </div>

      <p class="mt-3 text-caption text-text-muted">
        * Faturamento estimado pela soma do preço dos serviços concluídos. Valores de referência, não substituem o controle fiscal.
      </p>
    </template>
  </div>
</template>
