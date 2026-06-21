<script setup lang="ts">
import { ref } from 'vue'
import { useAuthStore } from '@/stores/auth'
import BaseButton from '@/components/ui/BaseButton.vue'
import BaseInput from '@/components/ui/BaseInput.vue'

// Login Magic Link (ADENDO §16.3): só e-mail. Após envio, estado "confira
// seu e-mail" que NÃO revela se o e-mail existe (privacidade).
const auth = useAuthStore()
const email = ref('')
const sending = ref(false)
const sent = ref(false)
const error = ref('')

async function submit() {
  error.value = ''
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.value)) {
    error.value = 'E-mail inválido. Confira o endereço.'
    return
  }
  sending.value = true
  const { error: err } = await auth.signInWithMagicLink(email.value)
  sending.value = false
  // Não distingue sucesso/falha por privacidade — sempre mostra o mesmo estado.
  if (err && err.status !== 400) error.value = 'Não foi possível enviar agora. Tente novamente.'
  else sent.value = true
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-bg px-4">
    <div class="w-full max-w-sm rounded-lg border border-border bg-surface p-6 shadow-sm">
      <p class="eyebrow">Painel</p>
      <h1 class="mb-5 text-h1 font-display text-text">Entrar</h1>

      <form v-if="!sent" class="flex flex-col gap-4" @submit.prevent="submit">
        <BaseInput
          v-model="email"
          label="E-mail"
          type="email"
          inputmode="email"
          autocomplete="email"
          placeholder="voce@estabelecimento.com"
          :error="error"
          required
        />
        <BaseButton type="submit" :loading="sending" block>Enviar link de acesso</BaseButton>
        <p class="text-small text-text-muted">Enviamos um link de acesso — sem senha.</p>
      </form>

      <div v-else class="flex flex-col items-center gap-3 py-4 text-center">
        <div class="flex h-12 w-12 items-center justify-center rounded-pill bg-accent-soft text-2xl" aria-hidden="true">✉️</div>
        <h2 class="text-h2 font-display text-text">Confira seu e-mail</h2>
        <p class="text-small text-text-muted">
          Se houver uma conta para <strong>{{ email }}</strong>, enviamos um link de acesso. Abra-o neste dispositivo.
        </p>
      </div>
    </div>
  </div>
</template>
