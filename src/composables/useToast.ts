import { ref } from 'vue'

export type ToastKind = 'success' | 'error' | 'info'
export interface Toast {
  id: number
  kind: ToastKind
  message: string
}

// Fila global de toasts (ADENDO §14): feedback de ação, 4s, em fila.
const toasts = ref<Toast[]>([])
let seq = 0

export function useToast() {
  function push(message: string, kind: ToastKind = 'info', ttl = 4000) {
    const id = ++seq
    toasts.value.push({ id, kind, message })
    window.setTimeout(() => dismiss(id), ttl)
  }
  function dismiss(id: number) {
    toasts.value = toasts.value.filter((t) => t.id !== id)
  }
  return {
    toasts,
    success: (m: string) => push(m, 'success'),
    error: (m: string) => push(m, 'error'),
    info: (m: string) => push(m, 'info'),
    dismiss,
  }
}
