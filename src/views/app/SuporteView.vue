<script setup lang="ts">
import { computed } from 'vue'
import { useAuthStore } from '@/stores/auth'
import BaseButton from '@/components/ui/BaseButton.vue'
import PageHeader from '@/components/app/PageHeader.vue'
import { MessageCircle, Clock3 } from '@lucide/vue'

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
    <PageHeader
      eyebrow="Ajuda"
      title="Suporte"
      subtitle="Dúvidas, problemas ou sugestões? Fale com a gente — respondemos pelo WhatsApp."
    />

    <!-- Card de contato principal (WhatsApp) -->
    <div class="anim-fade-up rounded-2xl border border-border bg-surface p-6 shadow-card">
      <div class="flex items-start gap-4">
        <span class="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-success/15 text-success" aria-hidden="true">
          <MessageCircle class="h-6 w-6" :stroke-width="2" />
        </span>
        <div class="flex-1">
          <p class="text-body font-semibold text-text">Atendimento por WhatsApp</p>
          <p class="mt-0.5 text-small text-text-muted">
            Tire dúvidas sobre o uso, relate um problema ou registre uma reclamação.
          </p>
          <p class="mt-3 text-h2 font-display text-text">{{ WHATS_DISPLAY }}</p>
          <p class="mt-1 flex items-center gap-1.5 text-small text-text-muted">
            <Clock3 class="h-4 w-4" :stroke-width="2" aria-hidden="true" /> Atendimento: <strong class="text-text">Seg–Sex, 9h–18h</strong>
          </p>
        </div>
      </div>
      <a :href="whatsLink" target="_blank" rel="noopener" class="mt-5 block">
        <BaseButton block>
          <MessageCircle class="h-5 w-5" :stroke-width="2" /> Falar no WhatsApp
        </BaseButton>
      </a>
    </div>

    <!-- Dica para agilizar o atendimento -->
    <div class="mt-4 rounded-2xl border border-border bg-surface-2 p-5">
      <p class="text-small font-semibold text-text">Para agilizar o atendimento</p>
      <ul class="mt-3 flex flex-col gap-2 text-small text-text-muted">
        <li class="flex gap-2"><span class="text-accent" aria-hidden="true">•</span> Descreva o que aconteceu e em qual tela.</li>
        <li class="flex gap-2"><span class="text-accent" aria-hidden="true">•</span> Se possível, envie um print do erro.</li>
        <li class="flex gap-2"><span class="text-accent" aria-hidden="true">•</span> Informe o nome do estabelecimento.</li>
      </ul>
    </div>
  </div>
</template>
