<script setup lang="ts">
import { ref, computed } from 'vue'
import { useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import BaseButton from '@/components/ui/BaseButton.vue'
import BaseInput from '@/components/ui/BaseInput.vue'

// Modo "aquisição": acessada via /comecar (anúncios). Mesma tela e ações, mas
// copy voltada a quem ainda não tem conta (cadastro + teste grátis).
const route = useRoute()
const signup = computed(() => route.name === 'comecar')

// Login Magic Link (ADENDO §16.3): só e-mail. Após envio, estado "confira
// seu e-mail" que NÃO revela se o e-mail existe (privacidade).
const auth = useAuthStore()
const email = ref('')
const sending = ref(false)
const sent = ref(false)
const error = ref('')
const googleLoading = ref(false)

async function entrarComGoogle() {
  googleLoading.value = true
  const { error: err } = await auth.signInWithGoogle()
  if (err) {
    googleLoading.value = false
    error.value = 'Não foi possível entrar com Google agora.'
  }
  // Em sucesso, o navegador redireciona para o Google (não volta aqui).
}

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
      <p class="eyebrow">{{ signup ? 'Agenda Fácil' : 'Painel' }}</p>
      <h1 class="text-h1 font-display text-text" :class="signup ? 'mb-2' : 'mb-5'">
        {{ signup ? 'Comece grátis' : 'Entrar' }}
      </h1>
      <p v-if="signup && !sent" class="mb-5 text-small text-text-muted">
        <strong class="text-text">7 dias grátis</strong>, sem cartão. Seu cliente marca, remarca e
        cancela sozinho — sem WhatsApp manual.
      </p>

      <div v-if="!sent" class="flex flex-col gap-4">
        <!-- Google: sem e-mail, sem rate limit, 1 clique -->
        <BaseButton variant="secondary" :loading="googleLoading" block @click="entrarComGoogle">
          <svg class="h-5 w-5" viewBox="0 0 24 24" aria-hidden="true">
            <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.27-4.74 3.27-8.1Z"/>
            <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.99.66-2.26 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84A11 11 0 0 0 12 23Z"/>
            <path fill="#FBBC05" d="M5.84 14.1a6.6 6.6 0 0 1 0-4.2V7.06H2.18a11 11 0 0 0 0 9.88l3.66-2.84Z"/>
            <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1A11 11 0 0 0 2.18 7.06l3.66 2.84C6.71 7.3 9.14 5.38 12 5.38Z"/>
          </svg>
          {{ signup ? 'Criar conta com Google' : 'Entrar com Google' }}
        </BaseButton>

        <div class="flex items-center gap-3 text-caption text-text-muted">
          <span class="h-px flex-1 bg-border" />ou<span class="h-px flex-1 bg-border" />
        </div>

        <form class="flex flex-col gap-4" @submit.prevent="submit">
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
          <BaseButton type="submit" :loading="sending" block>
            {{ signup ? 'Começar grátis' : 'Enviar link de acesso' }}
          </BaseButton>
          <p class="text-small text-text-muted">Enviamos um link de acesso — sem senha.</p>
        </form>

        <!-- Alterna entre cadastro e login -->
        <p class="text-center text-small text-text-muted">
          <template v-if="signup">
            Já tem conta?
            <RouterLink :to="{ name: 'login' }" class="font-medium text-accent underline">Entrar</RouterLink>
          </template>
          <template v-else>
            Novo por aqui?
            <RouterLink :to="{ name: 'comecar' }" class="font-medium text-accent underline">Comece grátis</RouterLink>
          </template>
        </p>
      </div>

      <div v-else class="flex flex-col items-center gap-3 py-4 text-center">
        <div class="flex h-12 w-12 items-center justify-center rounded-pill bg-accent-soft text-2xl" aria-hidden="true">✉️</div>
        <h2 class="text-h2 font-display text-text">Confira seu e-mail</h2>
        <p class="text-small text-text-muted">
          <template v-if="signup">
            Enviamos um link para <strong>{{ email }}</strong>. Abra-o neste dispositivo para criar sua conta e
            começar o teste grátis.
          </template>
          <template v-else>
            Se houver uma conta para <strong>{{ email }}</strong>, enviamos um link de acesso. Abra-o neste dispositivo.
          </template>
        </p>
      </div>
    </div>
  </div>
</template>
