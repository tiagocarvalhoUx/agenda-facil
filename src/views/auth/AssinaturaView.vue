<script setup lang="ts">
import { ref, reactive, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useToast } from '@/composables/useToast'
import { fetchBilling, subscribe, type TenantBilling } from '@/lib/billing'
import { formatPreco } from '@/lib/format'
import { trackSubscribe } from '@/lib/pixel'
import BaseInput from '@/components/ui/BaseInput.vue'
import BaseButton from '@/components/ui/BaseButton.vue'

// Paywall: quando o trial acaba sem assinatura ativa, o acesso ao painel é
// interrompido e o dono cai aqui para assinar. Staff vê um aviso.
const auth = useAuthStore()
const router = useRouter()
const toast = useToast()

const PLANO_VALOR = 49
const billing = ref<TenantBilling | null>(null)
const loading = ref(true)
const assinando = ref(false)
const assina = reactive({ cpfCnpj: '', billingType: 'PIX' as 'PIX' | 'CREDIT_CARD' })

const emTrial = computed(() => auth.trialDaysLeft != null && auth.trialDaysLeft > 0)

onMounted(async () => {
  if (auth.tenant) billing.value = await fetchBilling(auth.tenant.id)
  loading.value = false
})

async function assinar() {
  const doc = assina.cpfCnpj.replace(/\D/g, '')
  if (doc.length !== 11 && doc.length !== 14) {
    toast.error('Informe um CPF (11 dígitos) ou CNPJ (14 dígitos) válido.')
    return
  }
  assinando.value = true
  try {
    await subscribe({ tenantId: auth.tenant!.id, cpfCnpj: doc, billingType: assina.billingType })
    trackSubscribe(PLANO_VALOR)
    toast.success('Assinatura criada! Acesso liberado.')
    await auth.refreshBilling()
    router.push({ name: 'agenda' })
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
