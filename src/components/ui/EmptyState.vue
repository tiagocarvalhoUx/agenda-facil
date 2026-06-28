<script setup lang="ts">
import { CalendarDays } from '@lucide/vue'
// EmptyState (ADENDO §14/§10.5): ilustração + frase + 1 CTA. Todo vazio convida
// a agir. `icon` (emoji) é opcional; se ausente, usa o ícone de calendário Lucide.
defineProps<{ icon?: string; title: string; description?: string; ctaLabel?: string }>()
defineEmits<{ cta: [] }>()
</script>

<template>
  <div class="anim-fade-up flex flex-col items-center justify-center gap-4 rounded-2xl border border-border bg-surface px-6 py-12 text-center shadow-card">
    <!-- ilustração: disco com halo do accent -->
    <div class="relative flex h-20 w-20 items-center justify-center" aria-hidden="true">
      <span class="absolute inset-0 rounded-full bg-accent opacity-20 blur-2xl" />
      <span class="relative flex h-16 w-16 items-center justify-center rounded-2xl bg-accent-soft text-3xl ring-1 ring-inset ring-[color-mix(in_srgb,var(--accent)_30%,transparent)]">
        <span v-if="icon">{{ icon }}</span>
        <CalendarDays v-else class="h-7 w-7 text-accent" :stroke-width="1.75" />
      </span>
    </div>
    <div class="flex flex-col items-center gap-1.5">
      <h3 class="text-h2 font-display text-text">{{ title }}</h3>
      <p v-if="description" class="max-w-xs text-small text-text-muted">{{ description }}</p>
    </div>
    <button
      v-if="ctaLabel"
      class="mt-1 inline-flex min-h-touch items-center rounded-lg bg-accent px-6 py-2.5 text-body font-semibold text-on-accent shadow-glow transition-all duration-fast ease-standard hover:bg-accent-hover active:scale-[0.98]"
      @click="$emit('cta')"
    >
      {{ ctaLabel }}
    </button>
  </div>
</template>
