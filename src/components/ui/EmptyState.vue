<script setup lang="ts">
// EmptyState (ADENDO §14/§10.5): ícone + frase + 1 CTA. Todo vazio convida a agir.
defineProps<{ icon?: string; title: string; description?: string; ctaLabel?: string }>()
defineEmits<{ cta: [] }>()
</script>

<template>
  <div class="flex flex-col items-center justify-center gap-3 rounded-lg border border-dashed border-border bg-surface p-8 text-center">
    <div class="flex h-12 w-12 items-center justify-center rounded-pill bg-accent-soft text-2xl" aria-hidden="true">
      {{ icon ?? '📅' }}
    </div>
    <h3 class="text-h3 font-display text-text">{{ title }}</h3>
    <p v-if="description" class="max-w-xs text-small text-text-muted">{{ description }}</p>
    <button
      v-if="ctaLabel"
      class="mt-1 inline-flex min-h-touch items-center rounded-md bg-accent px-5 py-2 text-body font-semibold text-on-accent transition-colors duration-fast hover:bg-accent-hover"
      @click="$emit('cta')"
    >
      {{ ctaLabel }}
    </button>
  </div>
</template>
