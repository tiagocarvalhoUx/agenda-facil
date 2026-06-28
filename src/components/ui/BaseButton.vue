<script setup lang="ts">
import { computed } from 'vue'

// Button (ADENDO §14) — variantes primary/secondary/ghost/danger.
// Estados: default · hover · focus(visível) · active · disabled · loading.
// Alvo de toque ≥ 44px (§18).
const props = withDefaults(
  defineProps<{
    variant?: 'primary' | 'secondary' | 'ghost' | 'danger'
    type?: 'button' | 'submit'
    loading?: boolean
    disabled?: boolean
    block?: boolean
  }>(),
  { variant: 'primary', type: 'button', loading: false, disabled: false, block: false },
)

const isDisabled = computed(() => props.disabled || props.loading)

const variants: Record<string, string> = {
  primary:
    'bg-accent text-on-accent shadow-glow hover:bg-accent-hover active:scale-[0.98] disabled:opacity-50 disabled:shadow-none',
  secondary:
    'border border-border bg-surface text-text hover:bg-surface-2 active:scale-[0.98] disabled:opacity-50',
  ghost: 'text-text hover:bg-surface-2 active:scale-[0.98] disabled:opacity-50',
  danger: 'bg-danger text-white hover:opacity-90 active:scale-[0.98] disabled:opacity-50',
}
</script>

<template>
  <button
    :type="type"
    :disabled="isDisabled"
    :aria-busy="loading"
    class="inline-flex min-h-touch items-center justify-center gap-2 rounded-lg px-5 py-2 text-body font-semibold transition-[background,transform,box-shadow] duration-fast ease-standard disabled:cursor-not-allowed"
    :class="[variants[variant], block ? 'w-full' : '']"
  >
    <svg
      v-if="loading"
      class="h-4 w-4 animate-spin"
      viewBox="0 0 24 24"
      fill="none"
      aria-hidden="true"
    >
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v4a4 4 0 00-4 4H4z" />
    </svg>
    <slot />
  </button>
</template>
