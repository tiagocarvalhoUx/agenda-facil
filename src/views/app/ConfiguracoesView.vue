<script setup lang="ts">
import { ref, reactive, watch, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { useToast } from '@/composables/useToast'
import { applyAccent, accentPassesAA } from '@/lib/accent'
import { fetchBilling, subscribe, type TenantBilling } from '@/lib/billing'
import { formatPreco } from '@/lib/format'
import BaseInput from '@/components/ui/BaseInput.vue'
import BaseButton from '@/components/ui/BaseButton.vue'

// Configurações (dono): marca + cor de acento com VALIDAÇÃO DE CONTRASTE AA
// ao salvar (§18). Pré-visualiza ao vivo aplicando o accent.
const auth = useAuthStore()
const toast = useToast()

const form = reactive({
  nome: '',
  accent_color: '#0E9F9A',
  brand_logo_url: '',
  auto_confirmar: true,
  antecedencia_min_horas: '1',
  antecedencia_max_dias: '60',
  cancelamento_ate_horas: '12',
})
const saving = ref(false)
const contrasteOk = ref(true)

onMounted(() => {
  if (auth.tenant) {
    form.nome = auth.tenant.nome
    form.accent_color = auth.tenant.accent_color ?? '#0E9F9A'
    form.brand_logo_url = auth.tenant.brand_logo_url ?? ''
    const p = auth.tenant.booking_policy
    if (p) {
      form.auto_confirmar = p.auto_confirmar ?? true
      form.antecedencia_min_horas = String(p.antecedencia_min_horas ?? 1)
      form.antecedencia_max_dias = String(p.antecedencia_max_dias ?? 60)
      form.cancelamento_ate_horas = String(p.cancelamento_ate_horas ?? 12)
    }
  }
})

// preview ao vivo + checa contraste
watch(
  () => form.accent_color,
  (c) => {
    contrasteOk.value = accentPassesAA(c)
    if (/^#[0-9a-f]{6}$/i.test(c)) applyAccent(c, auth.tenant?.vertical)
  },
)

const publicUrl = ref('')
onMounted(() => {
  publicUrl.value = `${window.location.origin}/${auth.tenant?.slug ?? ''}`
})

// ----- Assinatura do SaaS (Asaas) -----
const PLANO_VALOR = 49.9
const billing = ref<TenantBilling | null>(null)
const billingLoading = ref(true)
const assinando = ref(false)
const assina = reactive({ cpfCnpj: '', billingType: 'PIX' as 'PIX' | 'CREDIT_CARD' })

const STATUS_LABEL: Record<string, string> = {
  inativo: 'Sem assinatura',
  trial: 'Período de teste',
  ativo: 'Ativa',
  atrasado: 'Pagamento atrasado',
  cancelado: 'Cancelada',
}

async function loadBilling() {
  if (!auth.tenant) return
  billingLoading.value = true
  billing.value = await fetchBilling(auth.tenant.id)
  billingLoading.value = false
}
onMounted(loadBilling)

async function assinar() {
  const doc = assina.cpfCnpj.replace(/\D/g, '')
  if (doc.length !== 11 && doc.length !== 14) {
    toast.error('Informe um CPF (11 dígitos) ou CNPJ (14 dígitos) válido.')
    return
  }
  assinando.value = true
  try {
    await subscribe({ tenantId: auth.tenant!.id, cpfCnpj: doc, billingType: assina.billingType })
    toast.success('Assinatura criada! A cobrança chegará pelo Asaas.')
    await loadBilling()
  } catch (e: unknown) {
    toast.error('Não foi possível assinar: ' + ((e as { message?: string }).message ?? 'erro'))
  } finally {
    assinando.value = false
  }
}

async function salvar() {
  if (!form.nome.trim()) {
    toast.error('Informe o nome do estabelecimento.')
    return
  }
  saving.value = true
  const { error } = await supabase
    .from('tenants')
    .update({
      nome: form.nome.trim(),
      accent_color: form.accent_color,
      brand_logo_url: form.brand_logo_url.trim() || null,
      booking_policy: {
        auto_confirmar: form.auto_confirmar,
        antecedencia_min_horas: Number(form.antecedencia_min_horas) || 0,
        antecedencia_max_dias: Number(form.antecedencia_max_dias) || 365,
        cancelamento_ate_horas: Number(form.cancelamento_ate_horas) || 0,
      },
    })
    .eq('id', auth.tenant!.id)
  saving.value = false
  if (error) toast.error('Não foi possível salvar.')
  else {
    toast.success('Configurações salvas.')
    await auth.loadContext()
  }
}
</script>

<template>
  <div class="mx-auto max-w-xl p-4 sm:p-5">
    <header class="mb-5">
      <p class="eyebrow">Ajustes</p>
      <h1 class="text-h1 font-display text-text">Configurações</h1>
    </header>

    <div class="flex flex-col gap-5">
      <section class="rounded-lg border border-border bg-surface p-5">
        <h2 class="mb-3 text-h2 font-display text-text">Marca</h2>
        <div class="flex flex-col gap-4">
          <BaseInput v-model="form.nome" label="Nome do estabelecimento" required />
          <BaseInput v-model="form.brand_logo_url" label="URL do logo (opcional)" placeholder="https://..." />
          <div v-if="form.brand_logo_url" class="flex items-center gap-3">
            <img :src="form.brand_logo_url" alt="Pré-visualização do logo" class="h-12 w-12 rounded-md object-contain bg-surface-2 p-1" />
            <span class="text-small text-text-muted">Pré-visualização</span>
          </div>

          <div class="flex flex-col gap-1">
            <label class="text-small font-medium text-text">Cor de destaque</label>
            <div class="flex items-center gap-3">
              <input v-model="form.accent_color" type="color" class="h-10 w-14 cursor-pointer rounded-md border border-border" aria-label="Selecionar cor" />
              <span class="tabular text-small text-text-muted">{{ form.accent_color.toUpperCase() }}</span>
              <span class="ml-auto inline-flex items-center gap-1 rounded-pill px-2 py-0.5 text-caption" :class="contrasteOk ? 'bg-success/10 text-success' : 'bg-warning/10 text-warning'">
                {{ contrasteOk ? '✓ Contraste AA' : '⚠ Será escurecida' }}
              </span>
            </div>
            <p v-if="!contrasteOk" class="text-small text-text-muted">
              Essa cor não atinge contraste AA sobre branco — usaremos um tom mais escuro no texto e botões para manter a legibilidade.
            </p>
          </div>

          <BaseButton :loading="saving" @click="salvar">Salvar</BaseButton>
        </div>
      </section>

      <section class="rounded-lg border border-border bg-surface p-5">
        <h2 class="mb-3 text-h2 font-display text-text">Política de agendamento</h2>
        <div class="flex flex-col gap-4">
          <label class="flex items-center gap-2 text-small text-text">
            <input v-model="form.auto_confirmar" type="checkbox" class="h-4 w-4 rounded border-border" />
            Confirmar agendamentos públicos automaticamente
          </label>
          <div class="grid grid-cols-2 gap-3">
            <BaseInput v-model="form.antecedencia_min_horas" label="Antecedência mínima (horas)" type="number" inputmode="numeric" />
            <BaseInput v-model="form.antecedencia_max_dias" label="Janela máxima (dias)" type="number" inputmode="numeric" />
          </div>
          <BaseInput v-model="form.cancelamento_ate_horas" label="Cancelar/remarcar até (horas antes)" type="number" inputmode="numeric" />
          <BaseButton :loading="saving" @click="salvar">Salvar</BaseButton>
        </div>
      </section>

      <section class="rounded-lg border border-border bg-surface p-5">
        <h2 class="mb-1 text-h2 font-display text-text">Assinatura</h2>
        <p class="mb-4 text-small text-text-muted">
          Plano Mensal —
          <RouterLink
            :to="{ name: 'assinatura' }"
            class="font-semibold text-accent underline underline-offset-2 transition-opacity hover:opacity-80"
          >{{ formatPreco(PLANO_VALOR) }}/mês</RouterLink>
        </p>

        <div v-if="billingLoading" class="text-small text-text-muted">Carregando…</div>

        <template v-else>
          <!-- Já assinante / em trial → área clicável para as formas de pagamento -->
          <RouterLink
            v-if="billing && ['ativo', 'trial'].includes(billing.status)"
            :to="{ name: 'assinatura' }"
            class="flex items-center justify-between gap-3 rounded-md border border-success/40 bg-success/10 p-3 transition-colors duration-fast hover:bg-success/20"
          >
            <div>
              <p class="text-body font-semibold text-success">✓ Assinatura {{ STATUS_LABEL[billing.status] }}</p>
              <p class="text-small text-text-muted">
                {{ billing.plano ?? 'Mensal' }} · {{ formatPreco(billing.valor ?? PLANO_VALOR) }}
                <template v-if="billing.proximo_vencimento"> · próx. {{ billing.proximo_vencimento }}</template>
              </p>
              <p class="mt-1 text-caption font-medium text-accent">
                {{ billing.status === 'trial' ? 'Assinar agora · ver formas de pagamento' : 'Gerenciar pagamento' }}
              </p>
            </div>
            <span class="text-lg text-text-muted" aria-hidden="true">›</span>
          </RouterLink>

          <!-- Atrasada -->
          <div v-else-if="billing && billing.status === 'atrasado'" class="rounded-md border border-warning/40 bg-warning/10 p-3 text-small text-warning">
            ⚠ Pagamento atrasado. Verifique a cobrança no e-mail/SMS do Asaas para reativar.
          </div>

          <!-- Sem assinatura → formulário -->
          <div v-else class="flex flex-col gap-3">
            <BaseInput v-model="assina.cpfCnpj" label="CPF ou CNPJ do responsável" inputmode="numeric" placeholder="Somente números" />
            <div class="flex flex-col gap-1">
              <label class="text-small font-medium text-text">Forma de pagamento</label>
              <div class="flex gap-2">
                <button
                  type="button"
                  class="min-h-touch flex-1 rounded-md border px-3 text-small transition-colors duration-fast"
                  :class="assina.billingType === 'PIX' ? 'border-accent bg-accent-soft text-text' : 'border-border text-text-muted'"
                  @click="assina.billingType = 'PIX'"
                >Pix</button>
                <button
                  type="button"
                  class="min-h-touch flex-1 rounded-md border px-3 text-small transition-colors duration-fast"
                  :class="assina.billingType === 'CREDIT_CARD' ? 'border-accent bg-accent-soft text-text' : 'border-border text-text-muted'"
                  @click="assina.billingType = 'CREDIT_CARD'"
                >Cartão</button>
              </div>
            </div>
            <BaseButton :loading="assinando" @click="assinar">Assinar {{ formatPreco(PLANO_VALOR) }}/mês</BaseButton>
            <p class="text-caption text-text-muted">A cobrança é gerada pelo Asaas; você recebe o Pix/boleto/link por e-mail.</p>
          </div>
        </template>
      </section>

      <section class="rounded-lg border border-border bg-surface p-5">
        <h2 class="mb-3 text-h2 font-display text-text">Página pública</h2>
        <p class="mb-2 text-small text-text-muted">Compartilhe este link para receber agendamentos:</p>
        <code class="block truncate rounded-md bg-surface-2 p-3 text-small text-text">{{ publicUrl }}</code>
      </section>
    </div>
  </div>
</template>
