<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { formatPreco } from '@/lib/format'
import BaseSkeleton from '@/components/ui/BaseSkeleton.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import PageHeader from '@/components/app/PageHeader.vue'
import { CalendarDays, Wallet, UserX, CalendarRange, CalendarClock, ArrowUpRight } from '@lucide/vue'

// Classe compartilhada dos cards de métrica clicáveis: card premium + afordância
// de link (eleva no hover, borda destaca, foco visível, mostra a seta ↗).
const metricCard =
  'group relative block rounded-xl border border-border bg-surface p-5 shadow-card transition-all duration-base ease-standard hover:-translate-y-0.5 hover:border-[color-mix(in_srgb,var(--accent)_30%,var(--border))] hover:shadow-float focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent'

// Dashboard do dono (§6.6): métricas que orientam retenção. Agregação no
// servidor via RPC SECURITY DEFINER (só owner). Nenhuma é vaidade.
const auth = useAuthStore()

interface Dashboard {
  periodo_dias: number
  agendamentos_hoje: number
  total_periodo: number
  concluidos: number
  no_show: number
  cancelados: number
  faturamento_estimado: number
  taxa_no_show: number
  top_servicos: { nome: string; total: number }[]
}

const data = ref<Dashboard | null>(null)
const loading = ref(true)
const errored = ref(false)
const dias = ref(30)

async function load() {
  loading.value = true
  errored.value = false
  const { data: d, error } = await supabase.rpc('get_owner_dashboard', {
    p_tenant_id: auth.tenant!.id,
    p_days: dias.value,
  })
  if (error) errored.value = true
  else data.value = d as Dashboard
  loading.value = false
}
onMounted(load)

// "A receber" (pipeline): soma do preço dos agendados/confirmados nos próximos
// 30 dias. Independe do período do dashboard; usa o preço congelado (fallback
// para o preço atual). Mesma lógica do Financeiro.
const aReceber = ref(0)
async function loadPipeline() {
  const now = new Date()
  const end = new Date(now)
  end.setDate(end.getDate() + 30)
  const { data: pipe } = await supabase
    .from('appointments')
    .select('preco_total, service:services(preco)')
    .gt('inicio_at', now.toISOString())
    .lte('inicio_at', end.toISOString())
    .in('status', ['agendado', 'confirmado'])
    .is('deleted_at', null)
  aReceber.value = ((pipe as unknown as { preco_total: number | null; service: { preco: number } | null }[]) ?? []).reduce(
    (s, r) => s + (r.preco_total ?? r.service?.preco ?? 0),
    0,
  )
}
onMounted(loadPipeline)

function setDias(n: number) {
  dias.value = n
  void load()
}
</script>

<template>
  <div class="mx-auto max-w-5xl p-4 sm:p-5">
    <PageHeader eyebrow="Visão geral" title="Dashboard">
      <template #actions>
        <!-- Período: controle segmentado em pílula -->
        <div class="inline-flex items-center gap-1 rounded-pill border border-border bg-surface/70 p-1 shadow-card backdrop-blur-sm">
          <button
            v-for="n in [7, 30, 90]"
            :key="n"
            class="h-9 rounded-pill px-3.5 text-small font-semibold transition-colors duration-fast"
            :class="dias === n ? 'bg-accent text-on-accent shadow-glow' : 'text-text-muted hover:text-text'"
            @click="setDias(n)"
          >{{ n }}d</button>
        </div>
      </template>
    </PageHeader>

    <div v-if="loading" class="grid grid-cols-2 gap-3 lg:grid-cols-4">
      <BaseSkeleton v-for="n in 4" :key="n" height="120px" rounded="xl" />
    </div>

    <EmptyState
      v-else-if="errored"
      icon="📡"
      title="Não foi possível carregar"
      description="Tente novamente."
      cta-label="Tentar de novo"
      @cta="load"
    />

    <template v-else-if="data">
      <!-- Cartões de métrica (clicáveis → drill-down na tela relacionada) -->
      <div class="stagger grid grid-cols-2 gap-3 lg:grid-cols-4">
        <RouterLink :to="{ name: 'agenda' }" :class="metricCard" aria-label="Ver agenda de hoje">
          <ArrowUpRight class="absolute right-4 top-4 h-4 w-4 text-text-muted opacity-0 transition-opacity group-hover:opacity-100" :stroke-width="2" aria-hidden="true" />
          <span class="flex h-9 w-9 items-center justify-center rounded-lg bg-accent-soft text-accent ring-1 ring-inset ring-[color-mix(in_srgb,var(--accent)_30%,transparent)]">
            <CalendarDays class="h-5 w-5" :stroke-width="2" />
          </span>
          <p class="tabular mt-3 text-display-lg font-display leading-none text-text">{{ data.agendamentos_hoje }}</p>
          <p class="mt-1.5 text-caption text-text-muted">agendamentos hoje</p>
        </RouterLink>
        <RouterLink :to="{ name: 'financeiro' }" :class="metricCard" aria-label="Abrir financeiro">
          <ArrowUpRight class="absolute right-4 top-4 h-4 w-4 text-text-muted opacity-0 transition-opacity group-hover:opacity-100" :stroke-width="2" aria-hidden="true" />
          <span class="flex h-9 w-9 items-center justify-center rounded-lg bg-success/15 text-success">
            <Wallet class="h-5 w-5" :stroke-width="2" />
          </span>
          <p class="tabular mt-3 text-h1 font-display leading-tight text-text">{{ formatPreco(data.faturamento_estimado) }}</p>
          <p class="mt-1.5 text-caption text-text-muted">faturamento* no período</p>
        </RouterLink>
        <RouterLink :to="{ name: 'clientes' }" :class="metricCard" aria-label="Ver clientes">
          <ArrowUpRight class="absolute right-4 top-4 h-4 w-4 text-text-muted opacity-0 transition-opacity group-hover:opacity-100" :stroke-width="2" aria-hidden="true" />
          <span class="flex h-9 w-9 items-center justify-center rounded-lg" :class="data.taxa_no_show > 0.15 ? 'bg-warning/15 text-warning' : 'bg-surface-2 text-text-muted'">
            <UserX class="h-5 w-5" :stroke-width="2" />
          </span>
          <p class="tabular mt-3 text-display-lg font-display leading-none" :class="data.taxa_no_show > 0.15 ? 'text-warning' : 'text-text'">
            {{ (data.taxa_no_show * 100).toFixed(0) }}%
          </p>
          <p class="mt-1.5 text-caption text-text-muted">no-show · {{ data.no_show }} falta(s)</p>
        </RouterLink>
        <RouterLink :to="{ name: 'agenda' }" :class="metricCard" aria-label="Ver agenda">
          <ArrowUpRight class="absolute right-4 top-4 h-4 w-4 text-text-muted opacity-0 transition-opacity group-hover:opacity-100" :stroke-width="2" aria-hidden="true" />
          <span class="flex h-9 w-9 items-center justify-center rounded-lg bg-info/15 text-info">
            <CalendarRange class="h-5 w-5" :stroke-width="2" />
          </span>
          <p class="tabular mt-3 text-display-lg font-display leading-none text-text">{{ data.total_periodo }}</p>
          <p class="mt-1.5 text-caption text-text-muted">no período</p>
        </RouterLink>
      </div>

      <!-- A receber (pipeline próximos 30 dias) → abre o Financeiro -->
      <RouterLink
        :to="{ name: 'financeiro' }"
        class="group mt-3 flex items-center justify-between gap-3 rounded-xl border border-border bg-surface p-4 shadow-card transition-all duration-base ease-standard hover:-translate-y-0.5 hover:border-[color-mix(in_srgb,var(--accent)_30%,var(--border))] hover:shadow-float focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
        aria-label="Abrir financeiro"
      >
        <div class="flex items-center gap-3">
          <span class="flex h-10 w-10 items-center justify-center rounded-lg bg-info/15 text-info">
            <CalendarClock class="h-5 w-5" :stroke-width="2" />
          </span>
          <div>
            <p class="text-caption text-text-muted">A receber · próximos 30 dias</p>
            <p class="tabular text-h2 font-display leading-tight text-text">{{ formatPreco(aReceber) }}</p>
          </div>
        </div>
        <ArrowUpRight class="h-5 w-5 shrink-0 text-text-muted opacity-0 transition-opacity group-hover:opacity-100" :stroke-width="2" aria-hidden="true" />
      </RouterLink>

      <!-- Detalhe do período -->
      <div class="mt-3 grid grid-cols-3 gap-3">
        <div class="rounded-xl border border-border bg-surface p-4 text-center shadow-card">
          <p class="tabular text-h1 font-display text-success">{{ data.concluidos }}</p>
          <p class="mt-1 text-caption text-text-muted">concluídos</p>
        </div>
        <div class="rounded-xl border border-border bg-surface p-4 text-center shadow-card">
          <p class="tabular text-h1 font-display text-warning">{{ data.no_show }}</p>
          <p class="mt-1 text-caption text-text-muted">faltas</p>
        </div>
        <div class="rounded-xl border border-border bg-surface p-4 text-center shadow-card">
          <p class="tabular text-h1 font-display text-text-muted">{{ data.cancelados }}</p>
          <p class="mt-1 text-caption text-text-muted">cancelados</p>
        </div>
      </div>

      <!-- Serviços mais agendados -->
      <section class="mt-5 rounded-2xl border border-border bg-surface p-5 shadow-card sm:p-6">
        <h2 class="mb-4 text-h2 font-display text-text">Serviços mais agendados</h2>
        <EmptyState
          v-if="data.top_servicos.length === 0"
          title="Sem dados ainda"
          description="As métricas aparecem conforme os agendamentos chegam."
        />
        <ul v-else class="flex flex-col gap-1">
          <li
            v-for="(s, i) in data.top_servicos"
            :key="s.nome"
            class="flex items-center gap-3 rounded-lg px-3 py-2.5 transition-colors hover:bg-surface-2"
          >
            <span class="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-accent-soft text-caption font-bold text-text">{{ i + 1 }}</span>
            <span class="flex-1 truncate text-body text-text">{{ s.nome }}</span>
            <span class="tabular text-small font-semibold text-text-muted">{{ s.total }}</span>
          </li>
        </ul>
      </section>

      <p class="mt-3 text-caption text-text-muted">* Faturamento estimado pela soma do preço dos serviços concluídos.</p>
    </template>
  </div>
</template>
