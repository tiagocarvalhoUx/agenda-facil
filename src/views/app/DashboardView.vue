<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { formatPreco } from '@/lib/format'
import BaseSkeleton from '@/components/ui/BaseSkeleton.vue'
import EmptyState from '@/components/ui/EmptyState.vue'

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

function setDias(n: number) {
  dias.value = n
  void load()
}
</script>

<template>
  <div class="mx-auto max-w-3xl p-4 sm:p-5">
    <header class="mb-5 flex flex-wrap items-center justify-between gap-3">
      <div>
        <p class="eyebrow">Visão geral</p>
        <h1 class="text-h1 font-display text-text">Dashboard</h1>
      </div>
      <div class="flex gap-1">
        <button
          v-for="n in [7, 30, 90]"
          :key="n"
          class="min-h-touch rounded-md border px-3 text-small"
          :class="dias === n ? 'border-accent bg-accent-soft text-text' : 'border-border text-text-muted'"
          @click="setDias(n)"
        >{{ n }}d</button>
      </div>
    </header>

    <div v-if="loading" class="grid grid-cols-2 gap-3 sm:grid-cols-4">
      <BaseSkeleton v-for="n in 4" :key="n" height="88px" rounded="lg" />
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
      <!-- Cartões de métrica -->
      <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <div class="rounded-lg border border-border bg-surface p-4">
          <p class="text-caption text-text-muted">Hoje</p>
          <p class="tabular text-h1 font-display text-text">{{ data.agendamentos_hoje }}</p>
          <p class="text-caption text-text-muted">agendamentos</p>
        </div>
        <div class="rounded-lg border border-border bg-surface p-4">
          <p class="text-caption text-text-muted">Faturamento*</p>
          <p class="tabular text-h2 font-display text-text">{{ formatPreco(data.faturamento_estimado) }}</p>
          <p class="text-caption text-text-muted">concluídos no período</p>
        </div>
        <div class="rounded-lg border border-border bg-surface p-4">
          <p class="text-caption text-text-muted">No-show</p>
          <p class="tabular text-h1 font-display" :class="data.taxa_no_show > 0.15 ? 'text-warning' : 'text-text'">
            {{ (data.taxa_no_show * 100).toFixed(0) }}%
          </p>
          <p class="text-caption text-text-muted">{{ data.no_show }} falta(s)</p>
        </div>
        <div class="rounded-lg border border-border bg-surface p-4">
          <p class="text-caption text-text-muted">Período</p>
          <p class="tabular text-h1 font-display text-text">{{ data.total_periodo }}</p>
          <p class="text-caption text-text-muted">agendamentos</p>
        </div>
      </div>

      <!-- Detalhe do período -->
      <div class="mt-3 grid grid-cols-3 gap-3">
        <div class="rounded-lg border border-border bg-surface p-3 text-center">
          <p class="tabular text-h3 font-semibold text-success">{{ data.concluidos }}</p>
          <p class="text-caption text-text-muted">concluídos</p>
        </div>
        <div class="rounded-lg border border-border bg-surface p-3 text-center">
          <p class="tabular text-h3 font-semibold text-warning">{{ data.no_show }}</p>
          <p class="text-caption text-text-muted">faltas</p>
        </div>
        <div class="rounded-lg border border-border bg-surface p-3 text-center">
          <p class="tabular text-h3 font-semibold text-text-muted">{{ data.cancelados }}</p>
          <p class="text-caption text-text-muted">cancelados</p>
        </div>
      </div>

      <!-- Serviços mais agendados -->
      <section class="mt-5 rounded-lg border border-border bg-surface p-5">
        <h2 class="mb-3 text-h3 font-display text-text">Serviços mais agendados</h2>
        <EmptyState
          v-if="data.top_servicos.length === 0"
          title="Sem dados ainda"
          description="As métricas aparecem conforme os agendamentos chegam."
        />
        <ul v-else class="flex flex-col gap-2">
          <li v-for="s in data.top_servicos" :key="s.nome" class="flex items-center justify-between">
            <span class="text-body text-text">{{ s.nome }}</span>
            <span class="tabular text-small font-semibold text-text-muted">{{ s.total }}</span>
          </li>
        </ul>
      </section>

      <p class="mt-3 text-caption text-text-muted">* Faturamento estimado pela soma do preço dos serviços concluídos.</p>
    </template>
  </div>
</template>
