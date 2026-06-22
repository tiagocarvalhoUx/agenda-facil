<script setup lang="ts">
import { ref, reactive, computed, onMounted, watch } from 'vue'
import { useRoute } from 'vue-router'
import { applyAccent } from '@/lib/accent'
import { fetchEstablishment, fetchSlots, createBooking, joinWaitlist } from '@/lib/publicApi'
import { mapBookingError } from '@/lib/errors'
import { useToast } from '@/composables/useToast'
import { formatPreco, formatDuracao, formatHora, formatDataLonga, toDateParam } from '@/lib/format'
import { buildICS, downloadICS } from '@/lib/ics'
import type { PublicEstablishment, AvailableSlot, BookingResult } from '@/types/database.types'

import BookingStepper from '@/components/public/BookingStepper.vue'
import DateNavigator from '@/components/public/DateNavigator.vue'
import SlotPicker from '@/components/public/SlotPicker.vue'
import BaseButton from '@/components/ui/BaseButton.vue'
import BaseInput from '@/components/ui/BaseInput.vue'
import PhoneInput from '@/components/ui/PhoneInput.vue'
import ConsentCheckbox from '@/components/ui/ConsentCheckbox.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import BaseSkeleton from '@/components/ui/BaseSkeleton.vue'

// Funil linear (ADENDO §15.1): 1 decisão por tela no mobile, progresso
// preservado em memória ao voltar. Tempo até o agendamento < 60s.
const route = useRoute()
const slug = route.params.slug as string
const toast = useToast()

const STEPS = ['Serviço', 'Profissional', 'Horário', 'Seus dados', 'Pronto']
const step = ref(0)

const loadingEstab = ref(true)
const estabError = ref(false)
const estab = ref<PublicEstablishment | null>(null)

// progresso (mantido em memória — não recomeça ao voltar)
const form = reactive({
  serviceId: '' as string,
  professionalId: null as string | null,
  date: new Date(),
  slotIso: null as string | null,
  nome: '',
  telefone: '',
  email: '',
  consentimento: false,
})

const slots = ref<AvailableSlot[]>([])
const loadingSlots = ref(false)
const slotsError = ref(false)
const submitting = ref(false)
const confirmed = ref<BookingResult | null>(null)

const selectedService = computed(() => estab.value?.servicos.find((s) => s.id === form.serviceId))
const selectedProf = computed(() =>
  form.professionalId ? estab.value?.profissionais.find((p) => p.id === form.professionalId) : null,
)

// Só os profissionais que realizam o serviço escolhido (§6.2). Lista vazia de
// vínculos no serviço = todos realizam (retrocompatível).
const professionalsForService = computed(() => {
  const all = estab.value?.profissionais ?? []
  const ids = selectedService.value?.profissionais ?? []
  if (ids.length === 0) return all
  return all.filter((p) => ids.includes(p.id))
})

// Link de auto-gerenciamento (remarcar/cancelar sem login).
const manageUrl = computed(() =>
  confirmed.value ? `${window.location.origin}/b/${confirmed.value.manage_token}` : '',
)
const slotFim = computed(() => {
  const slot = slots.value.find((s) => s.inicio_at === form.slotIso)
  return slot?.fim_at ?? null
})

const formErrors = reactive({ nome: '', telefone: '', email: '' })

async function loadEstablishment() {
  loadingEstab.value = true
  estabError.value = false
  try {
    estab.value = await fetchEstablishment(slug)
    if (estab.value) {
      // Tema por tenant via runtime (§13.1) — SSR-ready: o mesmo applyAccent
      // roda no servidor quando houver pré-render.
      applyAccent(estab.value.accent_color, estab.value.vertical)
      document.title = `Agendar — ${estab.value.nome}`
    }
  } catch {
    // Falha de rede/servidor é distinta de tenant inexistente (data === null):
    // aqui o link pode estar certo, então oferecemos "Tentar de novo".
    estabError.value = true
  } finally {
    loadingEstab.value = false
  }
}

onMounted(loadEstablishment)

async function loadSlots() {
  if (!form.serviceId) return
  loadingSlots.value = true
  slotsError.value = false
  form.slotIso = null
  try {
    slots.value = await fetchSlots({
      slug,
      serviceId: form.serviceId,
      data: toDateParam(form.date),
      professionalId: form.professionalId,
    })
  } catch {
    slotsError.value = true
  } finally {
    loadingSlots.value = false
  }
}

// recarrega horários quando muda a data no passo de horário
watch(
  () => form.date,
  () => {
    if (step.value === 2) void loadSlots()
  },
)

function chooseService(id: string) {
  form.serviceId = id
  step.value = 1
}
function chooseProfessional(id: string | null) {
  form.professionalId = id
  step.value = 2
  void loadSlots()
}

function validateIdent(): boolean {
  formErrors.nome = form.nome.trim() ? '' : 'Informe seu nome.'
  formErrors.telefone = /^\+?[0-9]{10,15}$/.test(form.telefone) ? '' : 'Telefone inválido. Use DDD + número.'
  formErrors.email =
    !form.email || /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(form.email) ? '' : 'E-mail inválido.'
  return !formErrors.nome && !formErrors.telefone && !formErrors.email
}

async function submit() {
  if (!form.consentimento) {
    toast.error('É preciso autorizar o uso dos dados para concluir.')
    return
  }
  if (!validateIdent() || !form.slotIso) return
  submitting.value = true
  try {
    confirmed.value = await createBooking({
      slug,
      serviceId: form.serviceId,
      professionalId: form.professionalId,
      inicio: form.slotIso,
      nome: form.nome,
      telefone: form.telefone,
      email: form.email,
      consentimento: form.consentimento,
    })
    step.value = 4
  } catch (e: unknown) {
    const msg = mapBookingError((e as { message?: string }).message)
    toast.error(msg)
    // Slot tomado na hora de confirmar: re-ofertar horários (§15.1)
    if ((e as { message?: string }).message?.includes('slot_taken')) {
      step.value = 2
      await loadSlots()
    }
  } finally {
    submitting.value = false
  }
}

function addToCalendar() {
  if (!form.slotIso || !slotFim.value || !selectedService.value || !estab.value) return
  const ics = buildICS({
    title: `${selectedService.value.nome} — ${estab.value.nome}`,
    inicio: form.slotIso,
    fim: slotFim.value,
    local: estab.value.nome,
    descricao: selectedProf.value ? `Com ${selectedProf.value.nome}` : undefined,
  })
  downloadICS('agendamento.ics', ics)
}

function back() {
  if (step.value > 0) step.value--
}

// ----- Lista de espera (§6.5): quando não há horário no dia -----
const waitlistOpen = ref(false)
const waitlist = reactive({ nome: '', contato: '' })
const waitlistSending = ref(false)
const waitlistDone = ref(false)

async function submitWaitlist() {
  if (!waitlist.nome.trim() || !waitlist.contato.trim()) {
    toast.error('Informe nome e contato.')
    return
  }
  waitlistSending.value = true
  try {
    await joinWaitlist({
      slug,
      serviceId: form.serviceId,
      professionalId: form.professionalId,
      nome: waitlist.nome,
      contato: waitlist.contato,
      janela: { data: toDateParam(form.date) },
    })
    waitlistDone.value = true
    toast.success('Você entrou na lista de espera!')
  } catch (e: unknown) {
    toast.error(mapBookingError((e as { message?: string }).message))
  } finally {
    waitlistSending.value = false
  }
}
</script>

<template>
  <div class="mx-auto flex min-h-screen max-w-lg flex-col bg-bg px-4 py-5">
    <!-- loading da capa -->
    <div v-if="loadingEstab" class="flex flex-col gap-4">
      <BaseSkeleton height="2rem" />
      <BaseSkeleton height="6rem" rounded="lg" />
      <BaseSkeleton height="6rem" rounded="lg" />
    </div>

    <!-- falha de rede/servidor (distinta de tenant inexistente) -->
    <EmptyState
      v-else-if="estabError"
      icon="📡"
      title="Não foi possível carregar"
      description="Verifique sua conexão e tente novamente."
      cta-label="Tentar de novo"
      @cta="loadEstablishment"
    />

    <!-- tenant inexistente -->
    <EmptyState
      v-else-if="!estab"
      icon="🔍"
      title="Estabelecimento não encontrado"
      description="Confira o link com quem te enviou."
    />

    <template v-else>
      <!-- Cabeçalho + stepper -->
      <header class="mb-5 flex flex-col gap-4">
        <div class="flex items-center gap-3">
          <button
            v-if="step > 0 && step < 4"
            class="flex h-touch w-touch items-center justify-center rounded-md text-text-muted hover:bg-surface-2"
            aria-label="Voltar"
            @click="back"
          >‹</button>
          <img
            :src="estab.brand_logo_url || '/logo-agenda.png'"
            :alt="estab.nome"
            class="h-12 w-12 shrink-0 rounded-lg object-contain"
          />
          <div>
            <p class="eyebrow">Agendar</p>
            <h1 class="text-h1 font-display text-text">{{ estab.nome }}</h1>
          </div>
        </div>
        <BookingStepper v-if="step < 4" :steps="STEPS" :current="step" />
      </header>

      <main class="flex-1">
        <!-- PASSO 0 — Serviço -->
        <section v-if="step === 0" class="flex flex-col gap-3">
          <h2 class="text-h2 font-display text-text">Escolha o serviço</h2>
          <EmptyState
            v-if="estab.servicos.length === 0"
            title="Sem serviços disponíveis"
            description="Este estabelecimento ainda não publicou serviços."
          />
          <button
            v-for="s in estab.servicos"
            :key="s.id"
            class="flex min-h-touch items-center justify-between gap-4 rounded-lg border border-border bg-surface p-4 text-left transition-colors duration-fast hover:border-accent hover:bg-accent-soft"
            @click="chooseService(s.id)"
          >
            <div>
              <p class="text-h3 font-semibold text-text">{{ s.nome }}</p>
              <p class="tabular text-small text-text-muted">{{ formatDuracao(s.duracao_min) }}</p>
            </div>
            <span class="tabular text-body font-semibold text-text">{{ formatPreco(s.preco) }}</span>
          </button>
        </section>

        <!-- PASSO 1 — Profissional -->
        <section v-else-if="step === 1" class="flex flex-col gap-3">
          <h2 class="text-h2 font-display text-text">Com quem?</h2>
          <!-- "Qualquer disponível" reduz atrito (§15.1) -->
          <button
            class="flex min-h-touch items-center gap-3 rounded-lg border border-accent bg-accent-soft p-4 text-left"
            @click="chooseProfessional(null)"
          >
            <span class="flex h-10 w-10 items-center justify-center rounded-pill bg-accent text-on-accent" aria-hidden="true">★</span>
            <div>
              <p class="text-h3 font-semibold text-text">Qualquer profissional disponível</p>
              <p class="text-small text-text-muted">Mais opções de horário</p>
            </div>
          </button>
          <button
            v-for="p in professionalsForService"
            :key="p.id"
            class="flex min-h-touch items-center gap-3 rounded-lg border border-border bg-surface p-4 text-left transition-colors duration-fast hover:border-accent hover:bg-accent-soft"
            @click="chooseProfessional(p.id)"
          >
            <img
              v-if="p.avatar_url"
              :src="p.avatar_url"
              :alt="p.nome"
              class="h-10 w-10 rounded-pill object-cover"
            />
            <span v-else class="flex h-10 w-10 items-center justify-center rounded-pill bg-surface-2 text-body font-semibold text-text" aria-hidden="true">
              {{ p.nome.charAt(0) }}
            </span>
            <div>
              <p class="text-h3 font-semibold text-text">{{ p.nome }}</p>
              <p v-if="p.bio" class="line-clamp-1 text-small text-text-muted">{{ p.bio }}</p>
            </div>
          </button>
        </section>

        <!-- PASSO 2 — Horário -->
        <section v-else-if="step === 2" class="flex flex-col gap-5">
          <DateNavigator v-model="form.date" />

          <SlotPicker
            v-if="loadingSlots || (slots.length > 0 && !slotsError)"
            v-model="form.slotIso"
            :slots="slots"
            :loading="loadingSlots"
          />

          <EmptyState
            v-else-if="slotsError"
            icon="📡"
            title="Não foi possível carregar os horários"
            description="Verifique sua conexão."
            cta-label="Tentar de novo"
            @cta="loadSlots"
          />
          <template v-else>
            <EmptyState
              icon="🗓️"
              title="Sem horários nesse dia"
              description="Tente outra data ou entre na lista de espera."
              cta-label="Ver próximo dia"
              @cta="form.date = new Date(form.date.getTime() + 86400000)"
            />

            <!-- Lista de espera (§6.5): avisamos quando liberar horário -->
            <div v-if="waitlistDone" class="rounded-lg border border-success/40 bg-success/10 p-4 text-center text-small text-text">
              ✓ Você está na lista de espera. Avisamos assim que abrir um horário.
            </div>
            <div v-else class="rounded-lg border border-border bg-surface p-4">
              <button v-if="!waitlistOpen" class="text-small font-medium text-accent underline" @click="waitlistOpen = true">
                Entrar na lista de espera
              </button>
              <div v-else class="flex flex-col gap-3">
                <p class="text-small text-text-muted">Deixe seu contato e avisamos quando liberar um horário.</p>
                <BaseInput v-model="waitlist.nome" label="Nome" required />
                <BaseInput v-model="waitlist.contato" label="Telefone ou e-mail" required />
                <BaseButton :loading="waitlistSending" block @click="submitWaitlist">Entrar na lista</BaseButton>
              </div>
            </div>
          </template>

          <BaseButton :disabled="!form.slotIso" block @click="step = 3">Continuar</BaseButton>
        </section>

        <!-- PASSO 3 — Identificação + LGPD -->
        <section v-else-if="step === 3" class="flex flex-col gap-4">
          <h2 class="text-h2 font-display text-text">Seus dados</h2>
          <BaseInput v-model="form.nome" label="Nome" required :error="formErrors.nome" autocomplete="name" />
          <PhoneInput v-model="form.telefone" label="Telefone" required :error="formErrors.telefone" />
          <BaseInput
            v-model="form.email"
            label="E-mail (para o lembrete)"
            type="email"
            inputmode="email"
            autocomplete="email"
            :error="formErrors.email"
          />
          <ConsentCheckbox v-model="form.consentimento" policy-url="/politica-privacidade" />
          <BaseButton :loading="submitting" :disabled="!form.consentimento" block @click="submit">
            Confirmar agendamento
          </BaseButton>
        </section>

        <!-- PASSO 4 — Confirmação -->
        <section v-else class="flex flex-col items-center gap-5 pt-6 text-center">
          <div class="flex h-16 w-16 items-center justify-center rounded-pill bg-success text-2xl text-on-accent" aria-hidden="true">✓</div>
          <div>
            <h2 class="text-h1 font-display text-text">Agendamento confirmado!</h2>
            <p class="mt-1 text-body text-text-muted">Você receberá um lembrete antes.</p>
          </div>

          <dl class="w-full rounded-lg border border-border bg-surface p-4 text-left">
            <div class="flex justify-between border-b border-border py-2">
              <dt class="text-small text-text-muted">Serviço</dt>
              <dd class="text-small font-medium text-text">{{ selectedService?.nome }}</dd>
            </div>
            <div v-if="selectedProf" class="flex justify-between border-b border-border py-2">
              <dt class="text-small text-text-muted">Profissional</dt>
              <dd class="text-small font-medium text-text">{{ selectedProf.nome }}</dd>
            </div>
            <div class="flex justify-between border-b border-border py-2">
              <dt class="text-small text-text-muted">Data</dt>
              <dd class="text-small font-medium capitalize text-text">{{ form.slotIso ? formatDataLonga(form.slotIso) : '' }}</dd>
            </div>
            <div class="flex justify-between py-2">
              <dt class="text-small text-text-muted">Horário</dt>
              <dd class="tabular text-small font-medium text-text">{{ form.slotIso ? formatHora(form.slotIso) : '' }}</dd>
            </div>
          </dl>

          <BaseButton variant="secondary" block @click="addToCalendar">Adicionar ao calendário</BaseButton>

          <!-- Link de auto-gerenciamento (§6.4): remarcar/cancelar sem login -->
          <a
            :href="manageUrl"
            class="flex min-h-touch w-full items-center justify-center rounded-md border border-border text-small font-medium text-text-muted transition-colors duration-fast hover:border-accent hover:text-text"
          >
            Remarcar ou cancelar
          </a>
          <p class="text-small text-text-muted">
            Guarde este link — é por ele que você gerencia o agendamento.
          </p>
        </section>
      </main>
    </template>
  </div>
</template>
