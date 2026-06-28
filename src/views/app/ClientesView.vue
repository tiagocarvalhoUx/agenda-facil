<script setup lang="ts">
import { ref, reactive, computed, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { useToast } from '@/composables/useToast'
import type { Customer } from '@/types/database.types'
import BaseInput from '@/components/ui/BaseInput.vue'
import BaseButton from '@/components/ui/BaseButton.vue'
import BaseSkeleton from '@/components/ui/BaseSkeleton.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import PageHeader from '@/components/app/PageHeader.vue'
import { Search, ShieldCheck } from '@lucide/vue'

// Iniciais do cliente para o avatar (até 2 letras).
function iniciais(nome: string): string {
  const p = nome.trim().split(/\s+/).filter(Boolean)
  if (!p.length) return '—'
  return (p[0][0] + (p.length > 1 ? p[p.length - 1][0] : '')).toUpperCase()
}

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
  <div class="mx-auto max-w-4xl p-4 sm:p-5">
    <PageHeader eyebrow="Base" title="Clientes" />

    <!-- Busca com ícone (estilo filled premium) -->
    <div class="relative mb-4 max-w-md">
      <Search class="pointer-events-none absolute left-3.5 top-1/2 h-5 w-5 -translate-y-1/2 text-text-muted" :stroke-width="2" aria-hidden="true" />
      <input
        v-model="busca"
        type="search"
        placeholder="Buscar por nome ou telefone"
        aria-label="Buscar cliente"
        class="h-12 w-full rounded-lg border border-border bg-surface pl-11 pr-4 text-body text-text placeholder:text-text-muted transition-colors focus:border-accent focus:outline-none"
      />
    </div>

    <div v-if="loading" class="grid gap-3 sm:grid-cols-2">
      <BaseSkeleton v-for="n in 4" :key="n" height="84px" rounded="xl" />
    </div>
    <EmptyState
      v-else-if="list.length === 0"
      icon="👥"
      title="Nenhum cliente ainda"
      description="Clientes aparecem aqui conforme os agendamentos chegam."
    />
    <EmptyState
      v-else-if="filtrados.length === 0"
      icon="🔍"
      title="Nenhum resultado"
      description="Tente outro nome ou telefone."
    />
    <ul v-else class="stagger grid gap-3 sm:grid-cols-2">
      <li
        v-for="c in filtrados"
        :key="c.id"
        class="group flex cursor-pointer items-center gap-3 rounded-xl border border-border bg-surface p-4 shadow-card transition-all duration-base ease-standard hover:-translate-y-0.5 hover:border-[color-mix(in_srgb,var(--accent)_30%,var(--border))] hover:shadow-float"
        @click="abrirFicha(c)"
      >
        <span class="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-accent-soft text-small font-semibold text-text ring-1 ring-inset ring-[color-mix(in_srgb,var(--accent)_35%,transparent)]" aria-hidden="true">{{ iniciais(c.nome) }}</span>
        <div class="min-w-0 flex-1">
          <p class="flex items-center gap-2 text-body font-semibold text-text">
            <span class="truncate">{{ c.nome }}</span>
            <!-- Reputação: destaca cliente reincidente (§6.3) -->
            <span
              v-if="c.no_show_count > 0"
              class="shrink-0 rounded-pill bg-warning/15 px-2 py-0.5 text-caption font-medium text-warning"
              :title="`${c.no_show_count} falta(s) registrada(s)`"
            >⚠ {{ c.no_show_count }}</span>
          </p>
          <p class="tabular truncate text-small text-text-muted">{{ c.telefone }}<template v-if="c.email"> · {{ c.email }}</template></p>
          <div v-if="c.tags && c.tags.length" class="mt-1.5 flex flex-wrap gap-1">
            <span v-for="t in c.tags" :key="t" class="rounded-pill bg-surface-2 px-2 py-0.5 text-caption text-text-muted">{{ t }}</span>
          </div>
        </div>
        <span v-if="c.anonimizado_at" class="shrink-0 text-caption text-text-muted">Anonimizado</span>
      </li>
    </ul>

    <!-- Ficha / drawer do cliente -->
    <Teleport to="body">
      <div v-if="drawer" class="theme-admin fixed inset-0 z-50 flex items-end justify-center overflow-y-auto bg-black/50 backdrop-blur-sm sm:items-center sm:p-4" @click.self="drawer = null">
        <div class="anim-sheet-up w-full max-w-sm rounded-t-2xl border border-border bg-surface p-5 shadow-pop sm:my-4 sm:rounded-2xl">
          <div class="mx-auto mb-4 h-1 w-10 rounded-pill bg-border sm:hidden" aria-hidden="true" />
          <div class="mb-4 flex items-center gap-3">
            <span class="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-accent-soft text-body font-semibold text-text ring-1 ring-inset ring-[color-mix(in_srgb,var(--accent)_35%,transparent)]" aria-hidden="true">{{ iniciais(drawer.nome) }}</span>
            <div class="min-w-0">
              <h2 class="truncate text-h2 font-display text-text">{{ drawer.nome }}</h2>
              <p class="tabular truncate text-small text-text-muted">{{ drawer.telefone }}<template v-if="drawer.email"> · {{ drawer.email }}</template></p>
            </div>
          </div>

          <div class="flex flex-col gap-3">
            <div class="flex flex-col gap-1">
              <label class="text-small font-medium text-text">Notas</label>
              <textarea
                v-model="editForm.notas"
                rows="3"
                class="rounded-lg border border-border bg-surface px-3 py-2 text-body text-text focus:border-accent focus:outline-none"
                placeholder="Preferências, observações..."
              />
            </div>
            <BaseInput v-model="editForm.tagsRaw" label="Tags (separadas por vírgula)" placeholder="VIP, alérgico, fidelidade" />

            <p v-if="drawer.no_show_count > 0" class="rounded-lg bg-warning/10 p-3 text-small text-warning">
              ⚠ Este cliente tem {{ drawer.no_show_count }} falta(s) registrada(s).
            </p>

            <BaseButton :loading="savingFicha" block @click="salvarFicha">Salvar ficha</BaseButton>
            <BaseButton v-if="!drawer.anonimizado_at" variant="danger" block @click="anonimizar(drawer)">
              <ShieldCheck class="h-5 w-5" :stroke-width="2" /> Anonimizar (LGPD)
            </BaseButton>
            <BaseButton variant="ghost" block @click="drawer = null">Fechar</BaseButton>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
