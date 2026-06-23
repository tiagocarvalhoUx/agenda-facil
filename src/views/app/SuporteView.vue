<script setup lang="ts">
import { computed } from 'vue'
import { useAuthStore } from '@/stores/auth'
import BaseButton from '@/components/ui/BaseButton.vue'

// Canal de suporte do SaaS (dúvidas, problemas, reclamações). O contato é o
// WhatsApp do responsável pelo Agenda Fácil — atende donos e equipe.
const auth = useAuthStore()

const WHATS_NUMERO = '5518981142927' // +55 (18) 98114-2927
const WHATS_DISPLAY = '(18) 98114-2927'

// Mensagem pré-preenchida com o nome do estabelecimento (ajuda a identificar).
const whatsLink = computed(() => {
  const nome = auth.tenant?.nome ? ` (${auth.tenant.nome})` : ''
  const msg = `Olá! Preciso de ajuda com o Agenda Fácil${nome}.`
  return `https://wa.me/${WHATS_NUMERO}?text=${encodeURIComponent(msg)}`
})
</script>

<template>
  <div class="mx-auto max-w-2xl p-4 sm:p-5">
    <header class="mb-5">
      <p class="eyebrow">Ajuda</p>
      <h1 class="text-h1 font-display text-text">Suporte</h1>
      <p class="mt-1 text-small text-text-muted">
        Dúvidas, problemas ou sugestões? Fale com a gente — respondemos pelo WhatsApp.
      </p>
    </header>

    <!-- Card de contato principal (WhatsApp) -->
    <div class="rounded-lg border border-border bg-surface p-5 shadow-sm">
      <div class="flex items-start gap-3">
        <span class="text-2xl" aria-hidden="true">💬</span>
        <div class="flex-1">
          <p class="text-body font-semibold text-text">Atendimento por WhatsApp</p>
          <p class="mt-0.5 text-small text-text-muted">
            Tire dúvidas sobre o uso, relate um problema ou registre uma reclamação.
          </p>
          <p class="mt-3 text-h3 font-display text-text">{{ WHATS_DISPLAY }}</p>
          <p class="mt-1 flex items-center gap-1.5 text-small text-text-muted">
            <span aria-hidden="true">🕒</span> Atendimento: <strong class="text-text">Seg–Sex, 9h–18h</strong>
          </p>
        </div>
      </div>
      <a :href="whatsLink" target="_blank" rel="noopener" class="mt-4 block">
        <BaseButton block>Falar no WhatsApp</BaseButton>
      </a>
    </div>

    <!-- Dica para agilizar o atendimento -->
    <div class="mt-4 rounded-lg border border-border bg-surface-2 p-4">
      <p class="text-small font-medium text-text">Para agilizar o atendimento</p>
      <ul class="mt-2 flex flex-col gap-1.5 text-small text-text-muted">
        <li class="flex gap-2"><span aria-hidden="true">•</span> Descreva o que aconteceu e em qual tela.</li>
        <li class="flex gap-2"><span aria-hidden="true">•</span> Se possível, envie um print do erro.</li>
        <li class="flex gap-2"><span aria-hidden="true">•</span> Informe o nome do estabelecimento.</li>
      </ul>
    </div>
  </div>
</template>
