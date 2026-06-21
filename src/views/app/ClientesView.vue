<script setup lang="ts">
import { ref, reactive, computed, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { useToast } from '@/composables/useToast'
import type { Customer } from '@/types/database.types'
import BaseInput from '@/components/ui/BaseInput.vue'
import BaseButton from '@/components/ui/BaseButton.vue'
import BaseSkeleton from '@/components/ui/BaseSkeleton.vue'
import EmptyState from '@/components/ui/EmptyState.vue'

// Clientes — visíveis só dentro do tenant (RLS). Inclui reputação anti no-show
// (no_show_count), notas e tags editáveis, e ação LGPD de anonimização (§20).
const toast = useToast()
const list = ref<Customer[]>([])
const loading = ref(true)
const busca = ref('')

const filtrados = computed(() =>
  list.value.filter((c) => c.nome.toLowerCase().includes(busca.value.toLowerCase()) || c.telefone.includes(busca.value)),
)

// drawer/ficha do cliente
const drawer = ref<Customer | null>(null)
const editForm = reactive({ notas: '', tagsRaw: '' })
const savingFicha = ref(false)

async function load() {
  loading.value = true
  const { data } = await supabase.from('customers').select('*').is('deleted_at', null).order('nome')
  list.value = (data as Customer[]) ?? []
  loading.value = false
}
onMounted(load)

function abrirFicha(c: Customer) {
  drawer.value = c
  editForm.notas = c.notas ?? ''
  editForm.tagsRaw = (c.tags ?? []).join(', ')
}

async function salvarFicha() {
  if (!drawer.value) return
  savingFicha.value = true
  const tags = editForm.tagsRaw
    .split(',')
    .map((t) => t.trim())
    .filter(Boolean)
  const { error } = await supabase
    .from('customers')
    .update({ notas: editForm.notas.trim() || null, tags })
    .eq('id', drawer.value.id)
  savingFicha.value = false
  if (error) toast.error('Não foi possível salvar.')
  else {
    toast.success('Ficha atualizada.')
    drawer.value = null
    await load()
  }
}

async function anonimizar(c: Customer) {
  if (!confirm(`Anonimizar os dados de ${c.nome}? Esta ação é irreversível (LGPD).`)) return
  const { error } = await supabase.rpc('anonimizar_cliente', { p_customer_id: c.id })
  if (error) toast.error('Não foi possível anonimizar.')
  else {
    toast.success('Dados anonimizados.')
    drawer.value = null
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
      <li
        v-for="c in filtrados"
        :key="c.id"
        class="flex cursor-pointer items-center justify-between rounded-md border border-border bg-surface p-4 hover:border-accent"
        @click="abrirFicha(c)"
      >
        <div>
          <p class="flex items-center gap-2 text-body font-semibold text-text">
            {{ c.nome }}
            <!-- Reputação: destaca cliente reincidente (§6.3) -->
            <span
              v-if="c.no_show_count > 0"
              class="rounded-pill bg-warning/15 px-2 py-0.5 text-caption font-medium text-warning"
              :title="`${c.no_show_count} falta(s) registrada(s)`"
            >⚠ {{ c.no_show_count }} no-show</span>
          </p>
          <p class="tabular text-small text-text-muted">{{ c.telefone }}<template v-if="c.email"> · {{ c.email }}</template></p>
          <div v-if="c.tags && c.tags.length" class="mt-1 flex flex-wrap gap-1">
            <span v-for="t in c.tags" :key="t" class="rounded-pill bg-surface-2 px-2 py-0.5 text-caption text-text-muted">{{ t }}</span>
          </div>
        </div>
        <span v-if="c.anonimizado_at" class="text-caption text-text-muted">Anonimizado</span>
      </li>
    </ul>

    <!-- Ficha / drawer do cliente -->
    <Teleport to="body">
      <div v-if="drawer" class="fixed inset-0 z-50 flex items-end justify-center overflow-y-auto bg-black/30 sm:items-center" @click.self="drawer = null">
        <div class="my-4 w-full max-w-sm rounded-t-lg bg-surface p-5 shadow-lg sm:rounded-lg">
          <h2 class="text-h2 font-display text-text">{{ drawer.nome }}</h2>
          <p class="tabular mb-4 text-small text-text-muted">{{ drawer.telefone }}<template v-if="drawer.email"> · {{ drawer.email }}</template></p>

          <div class="flex flex-col gap-3">
            <div class="flex flex-col gap-1">
              <label class="text-small font-medium text-text">Notas</label>
              <textarea
                v-model="editForm.notas"
                rows="3"
                class="rounded-md border border-border bg-surface px-3 py-2 text-body text-text focus:border-accent focus:outline-none"
                placeholder="Preferências, observações..."
              />
            </div>
            <BaseInput v-model="editForm.tagsRaw" label="Tags (separadas por vírgula)" placeholder="VIP, alérgico, fidelidade" />

            <p v-if="drawer.no_show_count > 0" class="rounded-md bg-warning/10 p-2 text-small text-warning">
              ⚠ Este cliente tem {{ drawer.no_show_count }} falta(s) registrada(s).
            </p>

            <BaseButton :loading="savingFicha" block @click="salvarFicha">Salvar ficha</BaseButton>
            <BaseButton v-if="!drawer.anonimizado_at" variant="danger" block @click="anonimizar(drawer)">Anonimizar (LGPD)</BaseButton>
            <BaseButton variant="ghost" block @click="drawer = null">Fechar</BaseButton>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
