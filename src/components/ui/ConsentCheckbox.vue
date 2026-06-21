<script setup lang="ts">
import { useId } from 'vue'

// ConsentCheckbox LGPD (ADENDO §14/§20): NUNCA pré-marcado, link para a
// política sempre visível, sem dark patterns.
defineProps<{ modelValue: boolean; policyUrl?: string }>()
defineEmits<{ 'update:modelValue': [value: boolean] }>()
const id = useId()
</script>

<template>
  <label :for="id" class="flex cursor-pointer items-start gap-3">
    <input
      :id="id"
      type="checkbox"
      :checked="modelValue"
      class="mt-0.5 h-5 w-5 shrink-0 rounded border-border text-accent focus:outline-none"
      @change="$emit('update:modelValue', ($event.target as HTMLInputElement).checked)"
    />
    <span class="text-small text-text">
      Autorizo o uso dos meus dados para gerenciar este agendamento e receber lembretes.
      <a
        v-if="policyUrl"
        :href="policyUrl"
        target="_blank"
        rel="noopener"
        class="text-accent underline"
        @click.stop
      >Política de privacidade</a>
    </span>
  </label>
</template>
