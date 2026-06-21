<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { useToast } from '@/composables/useToast'
import type { Professional } from '@/types/database.types'
import BaseButton from '@/components/ui/BaseButton.vue'
import BaseInput from '@/components/ui/BaseInput.vue'
import BaseSkeleton from '@/components/ui/BaseSkeleton.vue'
import EmptyState from '@/components/ui/EmptyState.vue'

const auth = useAuthStore()
const toast = useToast()

const list = ref<Professional[]>([])
const loading = ref(true)
const showForm = ref(false)
const saving = ref(false)
const form = reactive({ id: '', nome: '' })

async function load() {
  loading.value = true
  const { data } = await supabase.from('professionals').select('*').is('deleted_at', null).order('nome')
  list.value = (data as Professional[]) ?? []
  loading.value = false
}
onMounted(load)

function novo() {
  Object.assign(form, { id: '', nome: '' })
  showForm.value = true
}
function editar(p: Professional) {
  Object.assign(form, { id: p.id, nome: p.nome })
  showForm.value = true
}
async function salvar() {
  if (!form.nome.trim()) {
    toast.error('Informe o nome.')
    return
  }
  saving.value = true
  const payload = { tenant_id: auth.tenant!.id, nome: form.nome.trim() }
  const { error } = form.id
    ? await supabase.from('professionals').update({ nome: payload.nome }).eq('id', form.id)
    : await supabase.from('professionals').insert(payload)
  saving.value = false
  if (error) toast.error('Não foi possível salvar.')
  else {
    toast.success('Profissional salvo.')
    showForm.value = false
    await load()
  }
}
async function toggleAtivo(p: Professional) {
  const { error } = await supabase.from('professionals').update({ ativo: !p.ativo }).eq('id', p.id)
  if (error) toast.error('Não foi possível atualizar.')
  else await load()
}
</script>

<template>
  <div class="mx-auto max-w-2xl p-4 sm:p-5">
    <header class="mb-5 flex items-center justify-between">
      <div>
        <p class="eyebrow">Equipe</p>
        <h1 class="text-h1 font-display text-text">Profissionais</h1>
      </div>
      <BaseButton @click="novo">Novo profissional</BaseButton>
    </header>

    <div v-if="loading" class="flex flex-col gap-2">
      <BaseSkeleton v-for="n in 3" :key="n" height="56px" />
    </div>
    <EmptyState
      v-else-if="list.length === 0"
      icon="🧑‍⚕️"
      title="Nenhum profissional"
      description="Cadastre quem atende para montar a agenda."
      cta-label="Novo profissional"
      @cta="novo"
    />
    <ul v-else class="flex flex-col gap-2">
      <li v-for="p in list" :key="p.id" class="flex items-center justify-between rounded-md border border-border bg-surface p-4">
        <div class="flex items-center gap-3">
          <span class="flex h-9 w-9 items-center justify-center rounded-pill bg-surface-2 font-semibold text-text" aria-hidden="true">{{ p.nome.charAt(0) }}</span>
          <p class="text-body font-semibold text-text">{{ p.nome }}</p>
        </div>
        <div class="flex items-center gap-3">
          <button class="text-small text-text-muted underline" @click="toggleAtivo(p)">{{ p.ativo ? 'Ativo' : 'Inativo' }}</button>
          <button class="text-small text-accent underline" @click="editar(p)">Editar</button>
        </div>
      </li>
    </ul>

    <Teleport to="body">
      <div v-if="showForm" class="fixed inset-0 z-50 flex items-end justify-center bg-black/30 sm:items-center" @click.self="showForm = false">
        <div class="w-full max-w-sm rounded-t-lg bg-surface p-5 shadow-lg sm:rounded-lg">
          <h2 class="mb-4 text-h2 font-display text-text">{{ form.id ? 'Editar' : 'Novo' }} profissional</h2>
          <div class="flex flex-col gap-3">
            <BaseInput v-model="form.nome" label="Nome" required />
            <BaseButton :loading="saving" block @click="salvar">Salvar</BaseButton>
            <BaseButton variant="ghost" block @click="showForm = false">Cancelar</BaseButton>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
