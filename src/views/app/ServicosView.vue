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
import PageHeader from '@/components/app/PageHeader.vue'
import PageFab from '@/components/app/PageFab.vue'
import { Plus, Pencil, Trash2 } from '@lucide/vue'

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
  <div class="mx-auto max-w-4xl p-4 sm:p-5">
    <PageHeader eyebrow="Catálogo" title="Serviços">
      <template #actions>
        <BaseButton class="hidden lg:inline-flex" @click="novo">
          <Plus class="h-5 w-5" :stroke-width="2.25" /> Novo serviço
        </BaseButton>
      </template>
    </PageHeader>

    <div v-if="loading" class="grid gap-3 sm:grid-cols-2">
      <BaseSkeleton v-for="n in 4" :key="n" height="92px" rounded="xl" />
    </div>

    <EmptyState
      v-else-if="list.length === 0"
      icon="✂️"
      title="Nenhum serviço ainda"
      description="Cadastre seu primeiro serviço para começar a receber agendamentos."
      cta-label="Novo serviço"
      @cta="novo"
    />

    <ul v-else class="stagger grid gap-3 sm:grid-cols-2">
      <li
        v-for="s in list"
        :key="s.id"
        class="flex flex-col gap-3 rounded-xl border border-border bg-surface p-4 shadow-card transition-colors"
        :class="s.ativo ? '' : 'opacity-60'"
      >
        <div class="flex items-start justify-between gap-2">
          <div class="min-w-0">
            <p class="flex flex-wrap items-center gap-2 text-body font-semibold text-text">
              <span class="truncate">{{ s.nome }}</span>
              <span v-if="s.categoria" class="rounded-pill bg-surface-2 px-2 py-0.5 text-caption text-text-muted">{{ s.categoria }}</span>
            </p>
            <p class="tabular mt-1 text-small text-text-muted">
              {{ formatDuracao(s.duracao_min) }}<span v-if="s.buffer_min"> +{{ s.buffer_min }}min</span> · {{ formatPreco(s.preco) }}
              <span v-if="s.exige_deposito"> · depósito {{ formatPreco(s.deposito_valor) }}</span>
            </p>
          </div>
          <!-- Toggle de status como pílula -->
          <button
            class="shrink-0 rounded-pill px-2.5 py-1 text-caption font-medium transition-colors"
            :class="s.ativo ? 'bg-success/15 text-success' : 'bg-surface-2 text-text-muted'"
            @click="toggleAtivo(s)"
          >{{ s.ativo ? 'Ativo' : 'Inativo' }}</button>
        </div>
        <div class="flex items-center gap-2 border-t border-border pt-3">
          <button class="inline-flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-small font-medium text-text-muted transition-colors hover:bg-surface-2 hover:text-text" @click="editar(s)">
            <Pencil class="h-4 w-4" :stroke-width="2" /> Editar
          </button>
          <button class="inline-flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-small font-medium text-danger transition-colors hover:bg-danger/10" @click="remover(s)">
            <Trash2 class="h-4 w-4" :stroke-width="2" /> Remover
          </button>
        </div>
      </li>
    </ul>

    <PageFab label="Novo serviço" @click="novo" />

    <Teleport to="body">
      <div v-if="showForm" class="theme-admin fixed inset-0 z-50 flex items-end justify-center overflow-y-auto bg-black/50 backdrop-blur-sm sm:items-center sm:p-4" @click.self="showForm = false">
        <div class="anim-sheet-up w-full max-w-sm rounded-t-2xl border border-border bg-surface p-5 shadow-pop sm:my-4 sm:rounded-2xl">
          <div class="mx-auto mb-4 h-1 w-10 rounded-pill bg-border sm:hidden" aria-hidden="true" />
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
