<script setup lang="ts">
// Stepper do funil público (ADENDO §15.1): progresso sempre visível.
defineProps<{ steps: string[]; current: number }>()
</script>

<template>
  <nav class="flex items-center gap-2" aria-label="Progresso do agendamento">
    <template v-for="(step, i) in steps" :key="i">
      <div class="flex items-center gap-2">
        <span
          class="flex h-6 w-6 items-center justify-center rounded-pill text-caption font-semibold transition-colors duration-base"
          :class="
            i < current
              ? 'bg-accent text-on-accent'
              : i === current
                ? 'bg-accent text-on-accent ring-2 ring-accent-soft'
                : 'bg-surface-2 text-text-muted'
          "
          :aria-current="i === current ? 'step' : undefined"
        >
          <span v-if="i < current" aria-hidden="true">✓</span>
          <span v-else>{{ i + 1 }}</span>
        </span>
        <span class="hidden text-small sm:inline" :class="i === current ? 'text-text' : 'text-text-muted'">
          {{ step }}
        </span>
      </div>
      <span v-if="i < steps.length - 1" class="h-px w-4 flex-1 bg-border" aria-hidden="true" />
    </template>
  </nav>
</template>
