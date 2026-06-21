<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { useToast } from '@/composables/useToast'
import { formatHora, formatDataLonga } from '@/lib/format'
import type { TimeBlock, Professional } from '@/types/database.types'
import BaseButton from '@/components/ui/BaseButton.vue'
import BaseInput from '@/components/ui/BaseInput.vue'
import BaseSkeleton from '@/components/ui/BaseSkeleton.vue'
import EmptyState from '@/components/ui/EmptyState.vue'

// Bloqueios/folgas/feriados (§6.2 / time_blocks). Faixas indisponíveis
// subtraídas dos slots públicos e desenhadas na agenda. RLS: owner gerencia o
// tenant; staff só os próprios bloqueios.
const auth = useAuthStore()
const toast = useToast()

interface BlockRow extends TimeBlock {
  professional: { nome: string } | null
}

const list = ref<BlockRow[]>([])
const profs = ref<Professional[]>([])
const loading = ref(true)
const showForm = ref(false)
const saving = ref(false)
const form = reactive({ professional_id: '', inicio: '', fim: '', motivo: '' })

async function load() {
  loading.value = true
  const [{ data: blocks }, { data: pr }] = await Promise.all([
    supabase
      .from('time_blocks')
      .select('*, professional:professionals(nome)')
      .gte('fim_at', new Date().toISOString())
      .order('inicio_at'),
    supabase.from('professionals').select('*').is('deleted_at', null).order('nome'),
  ])
  list.value = (blocks as unknown as BlockRow[]) ?? []
  profs.value = (pr as Professional[]) ?? []
  loading.value = false
}
onMounted(load)

function novo() {
  Object.assign(form, { professional_id: profs.value[0]?.id ?? '', inicio: '', fim: '', motivo: '' })
  showForm.value = true
}

async function salvar() {
  if (!form.professional_id || !form.inicio || !form.fim) {
    toast.error('Preencha profissional, início e fim.')
    return
  }
  const inicioIso = new Date(form.inicio).toISOString()
  const fimIso = new Date(form.fim).toISOString()
  if (fimIso <= inicioIso) {
    toast.error('O fim deve ser depois do início.')
    return
  }
  saving.value = true
  const { error } = await supabase.from('time_blocks').insert({
    tenant_id: auth.tenant!.id,
    professional_id: form.professional_id,
    inicio_at: inicioIso,
    fim_at: fimIso,
    motivo: form.motivo.trim() || null,
  })
  saving.value = false
  if (error) toast.error('Não foi possível salvar.')
  else {
    toast.success('Bloqueio criado.')
    showForm.value = false
    await load()
  }
}

async function remover(b: BlockRow) {
  const { error } = await supabase.from('time_blocks').delete().eq('id', b.id)
  if (error) toast.error('Não foi possível remover.')
  else {
    toast.success('Bloqueio removido.')
    await load()
  }
}
</script>

<template>
  <div class="mx-auto max-w-2xl p-4 sm:p-5">
    <header class="mb-5 flex items-center justify-between">
      <div>
        <p class="eyebrow">Disponibilidade</p>
        <h1 class="text-h1 font-display text-text">Bloqueios e folgas</h1>
      </div>
      <BaseButton :disabled="profs.length === 0" @click="novo">Novo bloqueio</BaseButton>
    </header>

    <div v-if="loading" class="flex flex-col gap-2">
      <BaseSkeleton v-for="n in 3" :key="n" height="64px" />
    </div>

    <EmptyState
      v-else-if="profs.length === 0"
      icon="🧑‍⚕️"
      title="Cadastre profissionais primeiro"
      description="Bloqueios e folgas são por profissional."
    />

    <EmptyState
      v-else-if="list.length === 0"
      icon="🌴"
      title="Nenhum bloqueio futuro"
      description="Cadastre folgas, almoço ou feriados para esses horários não aparecerem na agenda pública."
      cta-label="Novo bloqueio"
      @cta="novo"
    />

    <ul v-else class="flex flex-col gap-2">
      <li v-for="b in list" :key="b.id" class="flex items-center justify-between gap-3 rounded-md border border-border bg-surface p-4">
        <div>
          <p class="text-body font-semibold text-text">{{ b.professional?.nome ?? '—' }}</p>
          <p class="tabular text-small text-text-muted capitalize">
            {{ formatDataLonga(b.inicio_at) }} · {{ formatHora(b.inicio_at) }}–{{ formatHora(b.fim_at) }}
          </p>
          <p v-if="b.motivo" class="text-small text-text-muted">{{ b.motivo }}</p>
        </div>
        <button class="text-small text-danger underline" @click="remover(b)">Remover</button>
      </li>
    </ul>

    <Teleport to="body">
      <div v-if="showForm" class="theme-admin fixed inset-0 z-50 flex items-end justify-center overflow-y-auto bg-black/30 sm:items-center" @click.self="showForm = false">
        <div class="my-4 w-full max-w-sm rounded-t-lg bg-surface p-5 shadow-lg sm:rounded-lg">
          <h2 class="mb-4 text-h2 font-display text-text">Novo bloqueio</h2>
          <div class="flex flex-col gap-3">
            <div class="flex flex-col gap-1">
              <label class="text-small font-medium text-text">Profissional</label>
              <select v-model="form.professional_id" class="min-h-touch rounded-md border border-border bg-surface px-3 text-body text-text focus:border-accent focus:outline-none">
                <option v-for="p in profs" :key="p.id" :value="p.id">{{ p.nome }}</option>
              </select>
            </div>
            <BaseInput v-model="form.inicio" label="Início" type="datetime-local" required />
            <BaseInput v-model="form.fim" label="Fim" type="datetime-local" required />
            <BaseInput v-model="form.motivo" label="Motivo (opcional)" placeholder="Almoço, feriado, folga..." />
            <BaseButton :loading="saving" block @click="salvar">Salvar</BaseButton>
            <BaseButton variant="ghost" block @click="showForm = false">Cancelar</BaseButton>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
