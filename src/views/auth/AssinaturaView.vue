<script setup lang="ts">
import { ref, reactive, computed, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useToast } from '@/composables/useToast'
import { fetchBilling, subscribe, type TenantBilling } from '@/lib/billing'
import { formatPreco } from '@/lib/format'
import { trackInitiateCheckout } from '@/lib/metaPixel'
import BaseInput from '@/components/ui/BaseInput.vue'
import BaseButton from '@/components/ui/BaseButton.vue'

// Paywall: quando o trial acaba sem assinatura ativa, o acesso ao painel é
// interrompido e o dono cai aqui para assinar. Staff vê um aviso.
const auth = useAuthStore()
const router = useRouter()
const toast = useToast()

const PLANO_VALOR = 79.9
const billing = ref<TenantBilling | null>(null)
const loading = ref(true)
const assinando = ref(false)
const assina = reactive({ cpfCnpj: '', billingType: 'PIX' as 'PIX' | 'CREDIT_CARD' })

// Estado "aguardando confirmação do pagamento": após gerar a cobrança sem
// acesso imediato, a tela fica escutando o billing até virar 'ativo' (webhook).
const aguardando = ref(false)
const verificando = ref(false)
let pollId: ReturnType<typeof setInterval> | null = null

const emTrial = computed(() => auth.trialDaysLeft != null && auth.trialDaysLeft > 0)

onMounted(async () => {
  if (auth.tenant) billing.value = await fetchBilling(auth.tenant.id)
  loading.value = false
})

onUnmounted(stopPolling)

function stopPolling() {
  if (pollId) {
    clearInterval(pollId)
    pollId = null
  }
}

// Recarrega o billing; se o acesso liberou (pagamento confirmado), entra no app.
async function checarLiberacao(): Promise<boolean> {
  await auth.refreshBilling()
  if (!auth.accessBlocked) {
    stopPolling()
    aguardando.value = false
    toast.success('Pagamento confirmado! Acesso liberado.')
    router.push({ name: 'agenda' })
    return true
  }
  return false
}

function startPolling() {
  stopPolling()
  aguardando.value = true
  pollId = setInterval(() => void checarLiberacao(), 5000) // a cada 5s
}

// Botão "Já paguei? Verificar agora" — checagem manual imediata.
async function verificarAgora() {
  verificando.value = true
  try {
    const liberou = await checarLiberacao()
    if (!liberou) toast.error('Pagamento ainda não confirmado. Pode levar alguns instantes.')
  } finally {
    verificando.value = false
  }
}

async function assinar() {
  const doc = assina.cpfCnpj.replace(/\D/g, '')
  if (doc.length !== 11 && doc.length !== 14) {
    toast.error('Informe um CPF (11 dígitos) ou CNPJ (14 dígitos) válido.')
    return
  }
  // InitiateCheckout: intenção de pagar (antes de seguir pro checkout). O
  // Subscribe que vale dinheiro sai do servidor (CAPI) quando o Asaas confirma.
  trackInitiateCheckout(assina.billingType === 'PIX' ? 'pix' : 'cartao')
  assinando.value = true
  try {
    await subscribe({ tenantId: auth.tenant!.id, cpfCnpj: doc, billingType: assina.billingType })
    await auth.refreshBilling()
    // O acesso só libera quando o pagamento confirma (webhook). Se o cliente
    // ainda está no trial válido, segue para a agenda; senão, fica aguardando.
    if (!auth.accessBlocked) {
      toast.success('Assinatura criada! Conclua o pagamento para garantir a continuidade.')
      router.push({ name: 'agenda' })
    } else {
      const via = assina.billingType === 'PIX' ? 'pelo Pix enviado' : 'pelo link enviado ao seu e-mail'
      toast.success(`Cobrança gerada! Pague ${via}. O acesso é liberado assim que o pagamento for confirmado.`)
      startPolling() // a tela passa a escutar a confirmação do pagamento
    }
  } catch (e: unknown) {
    toast.error('Não foi possível assinar: ' + ((e as { message?: string }).message ?? 'erro'))
  } finally {
    assinando.value = false
  }
}

async function sair() {
  await auth.signOut()
  router.push({ name: 'login' })
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-bg px-4 py-8">
    <div class="w-full max-w-sm rounded-lg border border-border bg-surface p-6 shadow-sm">
      <p class="eyebrow">Assinatura</p>
      <h1 class="mb-1 text-h1 font-display text-text">
        {{ emTrial ? 'Assine o seu plano' : 'Seu teste grátis terminou' }}
      </h1>
      <p class="mb-5 text-small text-text-muted">
        <template v-if="emTrial">Faltam {{ auth.trialDaysLeft }} dia(s) de teste. Garanta a continuidade.</template>
        <template v-else>Para continuar usando a agenda, assine o plano abaixo.</template>
      </p>

      <div v-if="loading" class="text-small text-text-muted">Carregando…</div>

      <!-- Aguardando confirmação do pagamento (escuta o webhook via polling) -->
      <div v-else-if="aguardando" class="flex flex-col gap-4">
        <div class="flex items-center gap-3 rounded-md border border-border bg-surface-2 p-3">
          <span class="h-2.5 w-2.5 flex-shrink-0 animate-pulse rounded-full bg-accent"></span>
          <p class="text-small text-text">
            Aguardando a confirmação do pagamento…<br />
            <span class="text-text-muted">
              Pague {{ assina.billingType === 'PIX' ? 'pelo Pix' : 'pelo link enviado ao seu e-mail' }}.
              O acesso libera automaticamente assim que o Asaas confirmar.
            </span>
          </p>
        </div>
        <BaseButton :loading="verificando" block @click="verificarAgora">Já paguei? Verificar agora</BaseButton>
        <button class="text-small text-text-muted underline" @click="sair">Sair</button>
      </div>

      <!-- Dono assina -->
      <div v-else-if="auth.isOwner" class="flex flex-col gap-4">
        <div class="rounded-md border border-border bg-surface-2 p-3">
          <p class="text-body font-semibold text-text">Plano Mensal</p>
          <p class="text-h2 font-display text-text">{{ formatPreco(PLANO_VALOR) }}<span class="text-small font-normal text-text-muted">/mês</span></p>
        </div>
        <BaseInput v-model="assina.cpfCnpj" label="CPF ou CNPJ do responsável" inputmode="numeric" placeholder="Somente números" />
        <div class="flex flex-col gap-1">
          <label class="text-small font-medium text-text">Forma de pagamento</label>
          <div class="flex gap-2">
            <button
              type="button"
              class="min-h-touch flex-1 rounded-md border px-3 text-small"
              :class="assina.billingType === 'PIX' ? 'border-accent bg-accent-soft text-text' : 'border-border text-text-muted'"
              @click="assina.billingType = 'PIX'"
            >Pix</button>
            <button
              type="button"
              class="min-h-touch flex-1 rounded-md border px-3 text-small"
              :class="assina.billingType === 'CREDIT_CARD' ? 'border-accent bg-accent-soft text-text' : 'border-border text-text-muted'"
              @click="assina.billingType = 'CREDIT_CARD'"
            >Cartão</button>
          </div>
        </div>
        <BaseButton :loading="assinando" block @click="assinar">Assinar {{ formatPreco(PLANO_VALOR) }}/mês</BaseButton>
        <button class="text-small text-text-muted underline" @click="sair">Sair</button>
      </div>

      <!-- Staff não assina -->
      <div v-else class="flex flex-col gap-4">
        <p class="rounded-md border border-border bg-surface-2 p-3 text-small text-text-muted">
          O período de teste do estabelecimento terminou. Peça ao responsável para assinar o plano para liberar o acesso.
        </p>
        <button class="text-small text-text-muted underline" @click="sair">Sair</button>
      </div>
    </div>
  </div>
</template>
