<script setup lang="ts">
import { ref, reactive, watch, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { useToast } from '@/composables/useToast'
import { applyAccent, accentPassesAA } from '@/lib/accent'
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
        <h2 class="mb-3 text-h2 font-display text-text">Página pública</h2>
        <p class="mb-2 text-small text-text-muted">Compartilhe este link para receber agendamentos:</p>
        <code class="block truncate rounded-md bg-surface-2 p-3 text-small text-text">{{ publicUrl }}</code>
      </section>
    </div>
  </div>
</template>
