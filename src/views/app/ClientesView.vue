<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { useToast } from '@/composables/useToast'
import type { Customer } from '@/types/database.types'
import BaseInput from '@/components/ui/BaseInput.vue'
import BaseSkeleton from '@/components/ui/BaseSkeleton.vue'
import EmptyState from '@/components/ui/EmptyState.vue'

// Clientes — visíveis só dentro do tenant (RLS). Inclui ação LGPD de
// anonimização via RPC anonimizar_cliente (§20).
const toast = useToast()
const list = ref<Customer[]>([])
const loading = ref(true)
const busca = ref('')

const filtrados = computed(() =>
  list.value.filter((c) => c.nome.toLowerCase().includes(busca.value.toLowerCase()) || c.telefone.includes(busca.value)),
)

async function load() {
  loading.value = true
  const { data } = await supabase.from('customers').select('*').is('deleted_at', null).order('nome')
  list.value = (data as Customer[]) ?? []
  loading.value = false
}
onMounted(load)

async function anonimizar(c: Customer) {
  if (!confirm(`Anonimizar os dados de ${c.nome}? Esta ação é irreversível (LGPD).`)) return
  const { error } = await supabase.rpc('anonimizar_cliente', { p_customer_id: c.id })
  if (error) toast.error('Não foi possível anonimizar.')
  else {
    toast.success('Dados anonimizados.')
    await load()
  }
}
</script>

<template>
  <div class="mx-auto max-w-2xl p-4 sm:p-5">
    <header class="mb-4">
      <p class="eyebrow">Base</p>
      <h1 class="text-h1 font-display text-text">Clientes</h1>
    </header>

    <div class="mb-4">
      <BaseInput v-model="busca" label="Buscar" placeholder="Nome ou telefone" />
    </div>

    <div v-if="loading" class="flex flex-col gap-2">
      <BaseSkeleton v-for="n in 4" :key="n" height="56px" />
    </div>
    <EmptyState
      v-else-if="list.length === 0"
      icon="👥"
      title="Nenhum cliente ainda"
      description="Clientes aparecem aqui conforme os agendamentos chegam."
    />
    <ul v-else class="flex flex-col gap-2">
      <li v-for="c in filtrados" :key="c.id" class="flex items-center justify-between rounded-md border border-border bg-surface p-4">
        <div>
          <p class="text-body font-semibold text-text">{{ c.nome }}</p>
          <p class="tabular text-small text-text-muted">{{ c.telefone }}<template v-if="c.email"> · {{ c.email }}</template></p>
        </div>
        <button v-if="!c.anonimizado_at" class="text-small text-danger underline" @click="anonimizar(c)">Anonimizar (LGPD)</button>
        <span v-else class="text-caption text-text-muted">Anonimizado</span>
      </li>
    </ul>
  </div>
</template>
