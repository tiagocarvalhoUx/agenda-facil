<script setup lang="ts">
import { useId } from 'vue'

// Input (ADENDO §14/§17): label SEMPRE visível (nunca placeholder-como-label),
// erro abaixo do campo em --danger, foco visível, body ≥16px (evita zoom iOS).
withDefaults(
  defineProps<{
    label: string
    modelValue: string
    type?: string
    placeholder?: string
    error?: string
    required?: boolean
    autocomplete?: string
    inputmode?: 'text' | 'email' | 'numeric' | 'decimal' | 'tel' | 'search' | 'url' | 'none'
  }>(),
  { type: 'text', required: false },
)
defineEmits<{ 'update:modelValue': [value: string] }>()

const id = useId()
</script>

<template>
  <div class="flex flex-col gap-1">
    <label :for="id" class="text-small font-medium text-text">
      {{ label }}
      <span v-if="required" class="text-danger" aria-hidden="true">*</span>
    </label>
    <input
      :id="id"
      :type="type"
      :value="modelValue"
      :placeholder="placeholder"
      :required="required"
      :autocomplete="autocomplete"
      :inputmode="inputmode"
      :aria-invalid="!!error"
      :aria-describedby="error ? `${id}-err` : undefined"
      class="min-h-touch rounded-md border bg-surface px-4 py-2 text-body text-text placeholder:text-text-muted focus:outline-none"
      :class="error ? 'border-danger' : 'border-border'"
      @input="$emit('update:modelValue', ($event.target as HTMLInputElement).value)"
    />
    <p v-if="error" :id="`${id}-err`" class="text-small text-danger">{{ error }}</p>
  </div>
</template>
