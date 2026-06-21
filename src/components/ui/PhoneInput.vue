<script setup lang="ts">
import { computed, useId } from 'vue'

// PhoneInput (ADENDO §14): máscara de telefone BR. Emite só dígitos para o
// modelValue (o backend valida ^\+?[0-9]{10,15}$); exibe formatado.
const props = defineProps<{
  label: string
  modelValue: string
  error?: string
  required?: boolean
}>()
const emit = defineEmits<{ 'update:modelValue': [value: string] }>()

const id = useId()

function maskBR(digits: string): string {
  const d = digits.replace(/\D/g, '').slice(0, 11)
  if (d.length <= 2) return d.length ? `(${d}` : ''
  if (d.length <= 6) return `(${d.slice(0, 2)}) ${d.slice(2)}`
  if (d.length <= 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`
  return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`
}

const display = computed(() => maskBR(props.modelValue))

function onInput(e: Event) {
  const digits = (e.target as HTMLInputElement).value.replace(/\D/g, '')
  emit('update:modelValue', digits)
}
</script>

<template>
  <div class="flex flex-col gap-1">
    <label :for="id" class="text-small font-medium text-text">
      {{ label }}
      <span v-if="required" class="text-danger" aria-hidden="true">*</span>
    </label>
    <input
      :id="id"
      type="tel"
      inputmode="tel"
      autocomplete="tel"
      :value="display"
      placeholder="(11) 99999-9999"
      :aria-invalid="!!error"
      :aria-describedby="error ? `${id}-err` : undefined"
      class="min-h-touch rounded-md border bg-surface px-4 py-2 text-body text-text placeholder:text-text-muted focus:outline-none"
      :class="error ? 'border-danger' : 'border-border'"
      @input="onInput"
    />
    <p v-if="error" :id="`${id}-err`" class="text-small text-danger">{{ error }}</p>
  </div>
</template>
