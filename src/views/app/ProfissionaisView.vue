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
import PageHeader from '@/components/app/PageHeader.vue'
import PageFab from '@/components/app/PageFab.vue'
import { Plus, Pencil } from '@lucide/vue'

const auth = useAuthStore()
const toast = useToast()

const list = ref<Professional[]>([])
const loading = ref(true)
const showForm = ref(false)
const saving = ref(false)
const form = reactive({ id: '', nome: '', avatar_url: '', bio: '' })

async function load() {
  loading.value = true
  const { data } = await supabase.from('professionals').select('*').is('deleted_at', null).order('nome')
  list.value = (data as Professional[]) ?? []
  loading.value = false
}
onMounted(load)

function novo() {
  Object.assign(form, { id: '', nome: '', avatar_url: '', bio: '' })
  showForm.value = true
}
function editar(p: Professional) {
  Object.assign(form, { id: p.id, nome: p.nome, avatar_url: p.avatar_url ?? '', bio: p.bio ?? '' })
  showForm.value = true
}
async function salvar() {
  if (!form.nome.trim()) {
    toast.error('Informe o nome.')
    return
  }
  saving.value = true
  const fields = {
    nome: form.nome.trim(),
    avatar_url: form.avatar_url.trim() || null,
    bio: form.bio.trim() || null,
  }
  const { error } = form.id
    ? await supabase.from('professionals').update(fields).eq('id', form.id)
    : await supabase.from('professionals').insert({ tenant_id: auth.tenant!.id, ...fields })
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
  <div class="mx-auto max-w-4xl p-4 sm:p-5">
    <PageHeader eyebrow="Equipe" title="Profissionais">
      <template #actions>
        <BaseButton class="hidden lg:inline-flex" @click="novo">
          <Plus class="h-5 w-5" :stroke-width="2.25" /> Novo profissional
        </BaseButton>
      </template>
    </PageHeader>

    <div v-if="loading" class="grid gap-3 sm:grid-cols-2">
      <BaseSkeleton v-for="n in 4" :key="n" height="84px" rounded="xl" />
    </div>
    <EmptyState
      v-else-if="list.length === 0"
      icon="🧑‍⚕️"
      title="Nenhum profissional"
      description="Cadastre quem atende para montar a agenda."
      cta-label="Novo profissional"
      @cta="novo"
    />
    <ul v-else class="stagger grid gap-3 sm:grid-cols-2">
      <li v-for="p in list" :key="p.id" class="flex items-center gap-3 rounded-xl border border-border bg-surface p-4 shadow-card" :class="p.ativo ? '' : 'opacity-60'">
        <img v-if="p.avatar_url" :src="p.avatar_url" :alt="p.nome" class="h-11 w-11 shrink-0 rounded-full object-cover ring-1 ring-inset ring-border" />
        <span v-else class="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-accent-soft font-semibold text-text ring-1 ring-inset ring-[color-mix(in_srgb,var(--accent)_35%,transparent)]" aria-hidden="true">{{ p.nome.charAt(0).toUpperCase() }}</span>
        <div class="min-w-0 flex-1">
          <p class="truncate text-body font-semibold text-text">{{ p.nome }}</p>
          <p v-if="p.bio" class="line-clamp-1 text-small text-text-muted">{{ p.bio }}</p>
        </div>
        <div class="flex shrink-0 items-center gap-1.5">
          <button
            class="rounded-pill px-2.5 py-1 text-caption font-medium transition-colors"
            :class="p.ativo ? 'bg-success/15 text-success' : 'bg-surface-2 text-text-muted'"
            @click="toggleAtivo(p)"
          >{{ p.ativo ? 'Ativo' : 'Inativo' }}</button>
          <button class="flex h-9 w-9 items-center justify-center rounded-lg text-text-muted transition-colors hover:bg-surface-2 hover:text-text" aria-label="Editar" @click="editar(p)">
            <Pencil class="h-4 w-4" :stroke-width="2" />
          </button>
        </div>
      </li>
    </ul>

    <PageFab label="Novo profissional" @click="novo" />

    <Teleport to="body">
      <div v-if="showForm" class="theme-admin fixed inset-0 z-50 flex items-end justify-center overflow-y-auto bg-black/50 backdrop-blur-sm sm:items-center sm:p-4" @click.self="showForm = false">
        <div class="anim-sheet-up w-full max-w-sm rounded-t-2xl border border-border bg-surface p-5 shadow-pop sm:my-4 sm:rounded-2xl">
          <div class="mx-auto mb-4 h-1 w-10 rounded-pill bg-border sm:hidden" aria-hidden="true" />
          <h2 class="mb-4 text-h2 font-display text-text">{{ form.id ? 'Editar' : 'Novo' }} profissional</h2>
          <div class="flex flex-col gap-3">
            <BaseInput v-model="form.nome" label="Nome" required />
            <BaseInput v-model="form.avatar_url" label="URL da foto (opcional)" placeholder="https://..." />
            <div class="flex flex-col gap-1">
              <label class="text-small font-medium text-text">Bio (opcional)</label>
              <textarea
                v-model="form.bio"
                rows="3"
                class="rounded-lg border border-border bg-surface px-3 py-2 text-body text-text focus:border-accent focus:outline-none"
                placeholder="Especialidades, experiência..."
              />
            </div>
            <BaseButton :loading="saving" block @click="salvar">Salvar</BaseButton>
            <BaseButton variant="ghost" block @click="showForm = false">Cancelar</BaseButton>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
