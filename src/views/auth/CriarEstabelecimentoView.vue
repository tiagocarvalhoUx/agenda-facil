<script setup lang="ts">
import { ref, reactive, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useToast } from '@/composables/useToast'
import { mapBookingError } from '@/lib/errors'
import BaseInput from '@/components/ui/BaseInput.vue'
import BaseButton from '@/components/ui/BaseButton.vue'

// Self-serve: novo cliente (ex.: login Google) cria o próprio estabelecimento.
// O trial de 7 dias começa automaticamente (trigger no banco).
const auth = useAuthStore()
const router = useRouter()
const toast = useToast()

const form = reactive({ nome: '', slug: '', vertical: 'salao' })
const saving = ref(false)
const slugEditado = ref(false)

function slugify(s: string): string {
  return s
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
}

// slug acompanha o nome até o usuário editar manualmente
watch(
  () => form.nome,
  (n) => {
    if (!slugEditado.value) form.slug = slugify(n)
  },
)

const publicPreview = computed(() => `${window.location.origin}/${form.slug || 'seu-link'}`)

async function criar() {
  if (!form.nome.trim()) {
    toast.error('Informe o nome do estabelecimento.')
    return
  }
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(form.slug)) {
    toast.error('Link inválido. Use letras minúsculas, números e hifens.')
    return
  }
  saving.value = true
  try {
    await auth.createTenant(form.nome, form.slug, form.vertical)
    toast.success('Estabelecimento criado! Você tem 7 dias grátis.')
    router.push({ name: 'agenda' })
  } catch (e: unknown) {
    const msg = (e as { message?: string }).message ?? ''
    toast.error(msg.includes('slug_taken') ? 'Esse link já está em uso. Escolha outro.' : mapBookingError(msg))
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-bg px-4 py-8">
    <div class="w-full max-w-sm rounded-lg border border-border bg-surface p-6 shadow-sm">
      <p class="eyebrow">Bem-vindo</p>
      <h1 class="mb-1 text-h1 font-display text-text">Crie seu estabelecimento</h1>
      <p class="mb-5 text-small text-text-muted">Comece com <strong>7 dias grátis</strong>. Sem cartão agora.</p>

      <div class="flex flex-col gap-4">
        <BaseInput v-model="form.nome" label="Nome do estabelecimento" placeholder="Ex.: Studio Bem-Estar" required />
        <div class="flex flex-col gap-1">
          <BaseInput
            v-model="form.slug"
            label="Link público"
            placeholder="studio-bem-estar"
            @input="slugEditado = true"
          />
          <p class="truncate text-caption text-text-muted">{{ publicPreview }}</p>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-small font-medium text-text">Tipo</label>
          <select v-model="form.vertical" class="min-h-touch rounded-md border border-border bg-surface px-3 text-body text-text focus:border-accent focus:outline-none">
            <option value="salao">Salão / Barbearia / Estética</option>
            <option value="clinica">Clínica / Consultório</option>
            <option value="outro">Outro</option>
          </select>
        </div>
        <BaseButton :loading="saving" block @click="criar">Criar e começar grátis</BaseButton>
      </div>
    </div>
  </div>
</template>
