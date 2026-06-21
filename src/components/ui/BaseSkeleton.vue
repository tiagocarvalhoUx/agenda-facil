<script setup lang="ts">
// Skeleton (ADENDO §14/§19): placeholders no lugar de spinners brancos.
withDefaults(defineProps<{ height?: string; rounded?: string }>(), {
  height: '1rem',
  rounded: 'md',
})
const radius: Record<string, string> = { sm: 'rounded-sm', md: 'rounded-md', lg: 'rounded-lg', pill: 'rounded-pill' }
</script>

<template>
  <div
    class="animate-pulse bg-surface-2"
    :class="radius[rounded]"
    :style="{ height }"
    aria-hidden="true"
  />
</template>
