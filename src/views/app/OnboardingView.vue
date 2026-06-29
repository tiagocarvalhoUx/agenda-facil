<script setup lang="ts">
import { ref, reactive, computed } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { useToast } from '@/composables/useToast'
import { applyAccent } from '@/lib/accent'
import BookingStepper from '@/components/public/BookingStepper.vue'
import BaseButton from '@/components/ui/BaseButton.vue'
import BaseInput from '@/components/ui/BaseInput.vue'

// Setup wizard de ativação do tenant (§8.4): marca → serviço → profissional+
// horários → link público. Cada passo grava imediatamente para não perder
// progresso. Sai com a base mínima pronta para receber agendamentos.
const auth = useAuthStore()
const router = useRouter()
const toast = useToast()

const STEPS = ['Marca', 'Serviço', 'Equipe', 'Pronto']
const step = ref(0)
const saving = ref(false)

// passo 1 — marca
const marca = reactive({ nome: auth.tenant?.nome ?? '', accent_color: auth.tenant?.accent_color ?? '#0E9F9A' })

// passo 2 — serviço
const servico = reactive({ nome: '', duracao_min: '45', preco: '0' })

// passo 3 — profissional + horários
const profissional = reactive({ nome: '' })
const WEEKDAYS = [
  { v: 1, label: 'Seg' }, { v: 2, label: 'Ter' }, { v: 3, label: 'Qua' },
  { v: 4, label: 'Qui' }, { v: 5, label: 'Sex' }, { v: 6, label: 'Sáb' }, { v: 0, label: 'Dom' },
]
const horario = reactive({ dias: [1, 2, 3, 4, 5] as number[], inicio: '09:00', fim: '18:00' })

function toggleDia(d: number) {
  const i = horario.dias.indexOf(d)
  if (i >= 0) horario.dias.splice(i, 1)
  else horario.dias.push(d)
}

const publicUrl = computed(() => `${window.location.origin}/${auth.tenant?.slug ?? ''}`)

async function salvarMarca() {
  if (!marca.nome.trim()) {
    toast.error('Informe o nome do estabelecimento.')
    return
  }
  saving.value = true
  const { error } = await supabase
    .from('tenants')
    .update({ nome: marca.nome.trim(), accent_color: marca.accent_color })
    .eq('id', auth.tenant!.id)
  saving.value = false
  if (error) return toast.error('Não foi possível salvar.')
  applyAccent(marca.accent_color, auth.tenant?.vertical)
  await auth.loadContext()
  step.value = 1
}

async function salvarServico() {
  if (!servico.nome.trim() || Number(servico.duracao_min) <= 0) {
    toast.error('Preencha nome e duração.')
    return
  }
  saving.value = true
  const { error } = await supabase.from('services').insert({
    tenant_id: auth.tenant!.id,
    nome: servico.nome.trim(),
    duracao_min: Number(servico.duracao_min),
    preco: Number(servico.preco),
  })
  saving.value = false
  if (error) return toast.error('Não foi possível salvar.')
  toast.success('Serviço criado.')
  step.value = 2
}

async function salvarEquipe() {
  if (!profissional.nome.trim()) {
    toast.error('Informe o nome do profissional.')
    return
  }
  if (horario.dias.length === 0) {
    toast.error('Escolha ao menos um dia de atendimento.')
    return
  }
  if (horario.fim <= horario.inicio) {
    toast.error('O horário de fim deve ser depois do início.')
    return
  }
  saving.value = true
  const { data, error } = await supabase
    .from('professionals')
    .insert({ tenant_id: auth.tenant!.id, nome: profissional.nome.trim() })
    .select('id')
    .single()
  if (error || !data) {
    saving.value = false
    return toast.error('Não foi possível salvar.')
  }
  const profId = (data as { id: string }).id
  const rows = horario.dias.map((d) => ({
    tenant_id: auth.tenant!.id,
    professional_id: profId,
    weekday: d,
    hora_inicio: horario.inicio,
    hora_fim: horario.fim,
  }))
  const { error: errHoras } = await supabase.from('working_hours').insert(rows)
  saving.value = false
  if (errHoras) return toast.error('Profissional criado, mas falhou ao salvar os horários.')
  toast.success('Equipe configurada!')
  await auth.refreshSetupState()
  step.value = 3
}

async function concluir() {
  await auth.refreshSetupState()
  router.push({ name: 'agenda' })
}

async function copiarLink() {
  try {
    await navigator.clipboard.writeText(publicUrl.value)
    toast.success('Link copiado!')
  } catch {
    toast.info('Copie o link manualmente.')
  }
}
</script>

<template>
  <div class="mx-auto flex min-h-screen max-w-lg flex-col px-4 py-6">
    <header class="mb-5">
      <p class="eyebrow">Bem-vindo</p>
      <h1 class="text-h1 font-display text-text">Vamos configurar sua agenda</h1>
    </header>

    <BookingStepper v-if="step < 3" :steps="STEPS" :current="step" />

    <main class="mt-6 flex-1">
      <!-- Passo 0 — Marca -->
      <section v-if="step === 0" class="flex flex-col gap-4">
        <h2 class="text-h2 font-display text-text">Sua marca</h2>
        <BaseInput v-model="marca.nome" label="Nome do estabelecimento" required />
        <div class="flex flex-col gap-1">
          <label class="text-small font-medium text-text">Cor de destaque</label>
          <div class="flex items-center gap-3">
            <input v-model="marca.accent_color" type="color" class="h-10 w-14 cursor-pointer rounded-lg border border-border" aria-label="Selecionar cor" />
            <span class="tabular text-small text-text-muted">{{ marca.accent_color.toUpperCase() }}</span>
          </div>
        </div>
        <BaseButton :loading="saving" block @click="salvarMarca">Continuar</BaseButton>
      </section>

      <!-- Passo 1 — Serviço -->
      <section v-else-if="step === 1" class="flex flex-col gap-4">
        <h2 class="text-h2 font-display text-text">Seu primeiro serviço</h2>
        <BaseInput v-model="servico.nome" label="Nome do serviço" placeholder="Ex.: Corte de cabelo" required />
        <div class="grid grid-cols-2 gap-3">
          <BaseInput v-model="servico.duracao_min" label="Duração (min)" type="number" inputmode="numeric" required />
          <BaseInput v-model="servico.preco" label="Preço (R$)" type="number" inputmode="decimal" />
        </div>
        <BaseButton :loading="saving" block @click="salvarServico">Continuar</BaseButton>
        <BaseButton variant="ghost" block @click="step = 0">Voltar</BaseButton>
      </section>

      <!-- Passo 2 — Profissional + horários -->
      <section v-else-if="step === 2" class="flex flex-col gap-4">
        <h2 class="text-h2 font-display text-text">Quem atende</h2>
        <BaseInput v-model="profissional.nome" label="Nome do profissional" required />
        <div class="flex flex-col gap-2">
          <label class="text-small font-medium text-text">Dias de atendimento</label>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="d in WEEKDAYS"
              :key="d.v"
              type="button"
              class="min-h-touch rounded-pill border px-3 text-small transition-colors duration-fast"
              :class="horario.dias.includes(d.v) ? 'border-accent bg-accent-soft text-text' : 'border-border text-text-muted'"
              @click="toggleDia(d.v)"
            >{{ d.label }}</button>
          </div>
        </div>
        <div class="grid grid-cols-2 gap-3">
          <BaseInput v-model="horario.inicio" label="Abre às" type="time" />
          <BaseInput v-model="horario.fim" label="Fecha às" type="time" />
        </div>
        <BaseButton :loading="saving" block @click="salvarEquipe">Continuar</BaseButton>
        <BaseButton variant="ghost" block @click="step = 1">Voltar</BaseButton>
      </section>

      <!-- Passo 3 — Pronto -->
      <section v-else class="flex flex-col items-center gap-5 pt-6 text-center">
        <div class="flex h-16 w-16 items-center justify-center rounded-pill bg-success text-2xl text-on-accent" aria-hidden="true">✓</div>
        <div>
          <h2 class="text-h1 font-display text-text">Tudo pronto!</h2>
          <p class="mt-1 text-body text-text-muted">Compartilhe seu link e comece a receber agendamentos.</p>
        </div>
        <code class="block w-full truncate rounded-lg bg-surface-2 p-3 text-small text-text">{{ publicUrl }}</code>
        <BaseButton block @click="copiarLink">Copiar link público</BaseButton>
        <BaseButton variant="secondary" block @click="concluir">Ir para a agenda</BaseButton>
      </section>
    </main>
  </div>
</template>
