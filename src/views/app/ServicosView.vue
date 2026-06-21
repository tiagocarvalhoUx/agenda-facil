<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { useToast } from '@/composables/useToast'
import { formatPreco, formatDuracao } from '@/lib/format'
import type { Service, Professional } from '@/types/database.types'
import BaseButton from '@/components/ui/BaseButton.vue'
import BaseInput from '@/components/ui/BaseInput.vue'
import BaseSkeleton from '@/components/ui/BaseSkeleton.vue'
import EmptyState from '@/components/ui/EmptyState.vue'

const auth = useAuthStore()
const toast = useToast()

const list = ref<Service[]>([])
const profs = ref<Professional[]>([])
const loading = ref(true)
const showForm = ref(false)
const saving = ref(false)

// form com os campos v2: categoria, buffer, depósito e vínculo de profissionais
const form = reactive({
  id: '',
  nome: '',
  categoria: '',
  duracao_min: '45',
  buffer_min: '0',
  preco: '0',
  exige_deposito: false,
  deposito_valor: '0',
})
const linkedProfs = ref<string[]>([]) // professional_services do serviço em edição

async function load() {
  loading.value = true
  const [{ data: svc }, { data: pr }] = await Promise.all([
    supabase.from('services').select('*').is('deleted_at', null).order('nome'),
    supabase.from('professionals').select('*').is('deleted_at', null).order('nome'),
  ])
  list.value = (svc as Service[]) ?? []
  profs.value = (pr as Professional[]) ?? []
  loading.value = false
}
onMounted(load)

function resetForm() {
  Object.assign(form, {
    id: '', nome: '', categoria: '', duracao_min: '45', buffer_min: '0',
    preco: '0', exige_deposito: false, deposito_valor: '0',
  })
  linkedProfs.value = []
}

function novo() {
  resetForm()
  showForm.value = true
}

async function editar(s: Service) {
  Object.assign(form, {
    id: s.id,
    nome: s.nome,
    categoria: s.categoria ?? '',
    duracao_min: String(s.duracao_min),
    buffer_min: String(s.buffer_min ?? 0),
    preco: String(s.preco),
    exige_deposito: s.exige_deposito ?? false,
    deposito_valor: String(s.deposito_valor ?? 0),
  })
  // carrega vínculos atuais
  const { data } = await supabase
    .from('professional_services')
    .select('professional_id')
    .eq('service_id', s.id)
  linkedProfs.value = ((data as { professional_id: string }[]) ?? []).map((r) => r.professional_id)
  showForm.value = true
}

function toggleProf(id: string) {
  const i = linkedProfs.value.indexOf(id)
  if (i >= 0) linkedProfs.value.splice(i, 1)
  else linkedProfs.value.push(id)
}

async function syncVinculos(serviceId: string) {
  // estratégia simples e idempotente: apaga e reinsere os vínculos do serviço
  await supabase.from('professional_services').delete().eq('service_id', serviceId)
  if (linkedProfs.value.length > 0) {
    await supabase.from('professional_services').insert(
      linkedProfs.value.map((pid) => ({
        tenant_id: auth.tenant!.id,
        service_id: serviceId,
        professional_id: pid,
      })),
    )
  }
}

async function salvar() {
  if (!form.nome.trim() || Number(form.duracao_min) <= 0) {
    toast.error('Preencha nome e duração válidos.')
    return
  }
  if (form.exige_deposito && Number(form.deposito_valor) <= 0) {
    toast.error('Defina o valor do depósito.')
    return
  }
  saving.value = true
  const payload = {
    tenant_id: auth.tenant!.id, // WITH CHECK valida no servidor que pertence ao usuário
    nome: form.nome.trim(),
    categoria: form.categoria.trim() || null,
    duracao_min: Number(form.duracao_min),
    buffer_min: Number(form.buffer_min) || 0,
    preco: Number(form.preco),
    exige_deposito: form.exige_deposito,
    deposito_valor: form.exige_deposito ? Number(form.deposito_valor) : 0,
  }
  const { data, error } = form.id
    ? await supabase.from('services').update(payload).eq('id', form.id).select('id').single()
    : await supabase.from('services').insert(payload).select('id').single()

  if (error || !data) {
    saving.value = false
    toast.error('Não foi possível salvar.')
    return
  }
  await syncVinculos((data as { id: string }).id)
  saving.value = false
  toast.success('Serviço salvo.')
  showForm.value = false
  await load()
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
          <p class="text-body font-semibold text-text">
            {{ s.nome }}
            <span v-if="s.categoria" class="ml-1 rounded-pill bg-surface-2 px-2 py-0.5 text-caption text-text-muted">{{ s.categoria }}</span>
          </p>
          <p class="tabular text-small text-text-muted">
            {{ formatDuracao(s.duracao_min) }}<span v-if="s.buffer_min"> +{{ s.buffer_min }}min</span> · {{ formatPreco(s.preco) }}
            <span v-if="s.exige_deposito"> · depósito {{ formatPreco(s.deposito_valor) }}</span>
          </p>
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
      <div v-if="showForm" class="theme-admin fixed inset-0 z-50 flex items-end justify-center overflow-y-auto bg-black/30 sm:items-center" @click.self="showForm = false">
        <div class="my-4 w-full max-w-sm rounded-t-lg bg-surface p-5 shadow-lg sm:rounded-lg">
          <h2 class="mb-4 text-h2 font-display text-text">{{ form.id ? 'Editar' : 'Novo' }} serviço</h2>
          <div class="flex flex-col gap-3">
            <BaseInput v-model="form.nome" label="Nome" required />
            <BaseInput v-model="form.categoria" label="Categoria (opcional)" placeholder="Ex.: Cabelo, Estética" />
            <div class="grid grid-cols-2 gap-3">
              <BaseInput v-model="form.duracao_min" label="Duração (min)" type="number" inputmode="numeric" required />
              <BaseInput v-model="form.buffer_min" label="Buffer (min)" type="number" inputmode="numeric" />
            </div>
            <BaseInput v-model="form.preco" label="Preço (R$)" type="number" inputmode="decimal" />

            <label class="flex items-center gap-2 text-small text-text">
              <input v-model="form.exige_deposito" type="checkbox" class="h-4 w-4 rounded border-border" />
              Exigir depósito anti no-show
            </label>
            <BaseInput
              v-if="form.exige_deposito"
              v-model="form.deposito_valor"
              label="Valor do depósito (R$)"
              type="number"
              inputmode="decimal"
            />

            <div v-if="profs.length > 0" class="flex flex-col gap-1">
              <label class="text-small font-medium text-text">Profissionais que realizam</label>
              <p class="text-caption text-text-muted">Nenhum marcado = todos realizam.</p>
              <div class="flex flex-wrap gap-2 pt-1">
                <button
                  v-for="p in profs"
                  :key="p.id"
                  type="button"
                  class="rounded-pill border px-3 py-1 text-small transition-colors duration-fast"
                  :class="linkedProfs.includes(p.id) ? 'border-accent bg-accent-soft text-text' : 'border-border text-text-muted'"
                  @click="toggleProf(p.id)"
                >
                  {{ p.nome }}
                </button>
              </div>
            </div>

            <BaseButton :loading="saving" block @click="salvar">Salvar</BaseButton>
            <BaseButton variant="ghost" block @click="showForm = false">Cancelar</BaseButton>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
