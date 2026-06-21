<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { useToast } from '@/composables/useToast'
import { formatPreco, formatDuracao } from '@/lib/format'
import type { Service } from '@/types/database.types'
import BaseButton from '@/components/ui/BaseButton.vue'
import BaseInput from '@/components/ui/BaseInput.vue'
import BaseSkeleton from '@/components/ui/BaseSkeleton.vue'
import EmptyState from '@/components/ui/EmptyState.vue'

const auth = useAuthStore()
const toast = useToast()

const list = ref<Service[]>([])
const loading = ref(true)
const showForm = ref(false)
const saving = ref(false)
const form = reactive({ id: '', nome: '', duracao_min: '45', preco: '0' })

async function load() {
  loading.value = true
  const { data } = await supabase
    .from('services')
    .select('*')
    .is('deleted_at', null)
    .order('nome')
  list.value = (data as Service[]) ?? []
  loading.value = false
}
onMounted(load)

function novo() {
  Object.assign(form, { id: '', nome: '', duracao_min: '45', preco: '0' })
  showForm.value = true
}
function editar(s: Service) {
  Object.assign(form, { id: s.id, nome: s.nome, duracao_min: String(s.duracao_min), preco: String(s.preco) })
  showForm.value = true
}

async function salvar() {
  if (!form.nome.trim() || Number(form.duracao_min) <= 0) {
    toast.error('Preencha nome e duração válidos.')
    return
  }
  saving.value = true
  const payload = {
    tenant_id: auth.tenant!.id, // WITH CHECK valida no servidor que pertence ao usuário
    nome: form.nome.trim(),
    duracao_min: Number(form.duracao_min),
    preco: Number(form.preco),
  }
  const { error } = form.id
    ? await supabase.from('services').update(payload).eq('id', form.id)
    : await supabase.from('services').insert(payload)
  saving.value = false
  if (error) {
    toast.error('Não foi possível salvar.')
  } else {
    toast.success('Serviço salvo.')
    showForm.value = false
    await load()
  }
}

async function toggleAtivo(s: Service) {
  const { error } = await supabase.from('services').update({ ativo: !s.ativo }).eq('id', s.id)
  if (error) toast.error('Não foi possível atualizar.')
  else await load()
}

async function remover(s: Service) {
  const { error } = await supabase.from('services').update({ deleted_at: new Date().toISOString() }).eq('id', s.id)
  if (error) toast.error('Não foi possível remover.')
  else {
    toast.success('Serviço removido.')
    await load()
  }
}
</script>

<template>
  <div class="mx-auto max-w-2xl p-4 sm:p-5">
    <header class="mb-5 flex items-center justify-between">
      <div>
        <p class="eyebrow">Serviços</p>
        <h1 class="text-h1 font-display text-text">Serviços</h1>
      </div>
      <BaseButton @click="novo">Novo serviço</BaseButton>
    </header>

    <div v-if="loading" class="flex flex-col gap-2">
      <BaseSkeleton v-for="n in 3" :key="n" height="64px" />
    </div>

    <EmptyState
      v-else-if="list.length === 0"
      icon="✂️"
      title="Nenhum serviço ainda"
      description="Cadastre seu primeiro serviço para começar a receber agendamentos."
      cta-label="Novo serviço"
      @cta="novo"
    />

    <ul v-else class="flex flex-col gap-2">
      <li
        v-for="s in list"
        :key="s.id"
        class="flex items-center justify-between gap-3 rounded-md border border-border bg-surface p-4"
      >
        <div>
          <p class="text-body font-semibold text-text">{{ s.nome }}</p>
          <p class="tabular text-small text-text-muted">{{ formatDuracao(s.duracao_min) }} · {{ formatPreco(s.preco) }}</p>
        </div>
        <div class="flex items-center gap-2">
          <button class="text-small text-text-muted underline" @click="toggleAtivo(s)">
            {{ s.ativo ? 'Ativo' : 'Inativo' }}
          </button>
          <button class="text-small text-accent underline" @click="editar(s)">Editar</button>
          <button class="text-small text-danger underline" @click="remover(s)">Remover</button>
        </div>
      </li>
    </ul>

    <Teleport to="body">
      <div v-if="showForm" class="fixed inset-0 z-50 flex items-end justify-center bg-black/30 sm:items-center" @click.self="showForm = false">
        <div class="w-full max-w-sm rounded-t-lg bg-surface p-5 shadow-lg sm:rounded-lg">
          <h2 class="mb-4 text-h2 font-display text-text">{{ form.id ? 'Editar' : 'Novo' }} serviço</h2>
          <div class="flex flex-col gap-3">
            <BaseInput v-model="form.nome" label="Nome" required />
            <BaseInput v-model="form.duracao_min" label="Duração (min)" type="number" inputmode="numeric" required />
            <BaseInput v-model="form.preco" label="Preço (R$)" type="number" inputmode="decimal" />
            <BaseButton :loading="saving" block @click="salvar">Salvar</BaseButton>
            <BaseButton variant="ghost" block @click="showForm = false">Cancelar</BaseButton>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
