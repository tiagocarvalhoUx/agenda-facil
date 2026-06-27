import { ref } from 'vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'

// Gerencia a inscrição de Web Push do dispositivo atual: pede permissão,
// assina no PushManager com a chave VAPID pública e salva a inscrição no banco
// (push_subscriptions). O envio em si é feito pela Edge Function notify-booking.

const VAPID_PUBLIC = import.meta.env.VITE_VAPID_PUBLIC_KEY as string | undefined

// Suporte do navegador (SW + Push API + Notification). iOS só expõe isso quando
// o app está "instalado" na tela inicial (standalone) — comportamento do Safari.
export const pushSupported =
  typeof window !== 'undefined' &&
  'serviceWorker' in navigator &&
  'PushManager' in window &&
  'Notification' in window

function urlBase64ToUint8Array(base64: string): Uint8Array<ArrayBuffer> {
  const padding = '='.repeat((4 - (base64.length % 4)) % 4)
  const b64 = (base64 + padding).replace(/-/g, '+').replace(/_/g, '/')
  const raw = atob(b64)
  const out = new Uint8Array(new ArrayBuffer(raw.length))
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i)
  return out
}

export function usePushNotifications() {
  const auth = useAuthStore()
  const permission = ref<NotificationPermission>(
    pushSupported ? Notification.permission : 'denied',
  )
  const subscribed = ref(false)
  const busy = ref(false)

  // Verifica se ESTE dispositivo já tem uma inscrição ativa.
  async function refresh() {
    if (!pushSupported) return
    permission.value = Notification.permission
    const reg = await navigator.serviceWorker.ready
    const sub = await reg.pushManager.getSubscription()
    subscribed.value = !!sub
  }

  // Pede permissão, assina e persiste no banco. Retorna true se ativou.
  async function enable(): Promise<boolean> {
    if (!pushSupported) throw new Error('Este navegador não suporta notificações push.')
    if (!VAPID_PUBLIC) throw new Error('VITE_VAPID_PUBLIC_KEY não configurada.')
    if (!auth.tenant) throw new Error('Sem estabelecimento ativo.')

    busy.value = true
    try {
      permission.value = await Notification.requestPermission()
      if (permission.value !== 'granted') return false

      const reg = await navigator.serviceWorker.ready
      let sub = await reg.pushManager.getSubscription()
      if (!sub) {
        sub = await reg.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC),
        })
      }

      const json = sub.toJSON()
      const { error } = await supabase.from('push_subscriptions').upsert(
        {
          tenant_id: auth.tenant.id,
          user_id: auth.session?.user.id,
          endpoint: sub.endpoint,
          p256dh: json.keys?.p256dh,
          auth: json.keys?.auth,
          user_agent: navigator.userAgent,
          last_seen_at: new Date().toISOString(),
        },
        { onConflict: 'endpoint' },
      )
      if (error) throw error

      subscribed.value = true
      return true
    } finally {
      busy.value = false
    }
  }

  // Cancela a inscrição deste dispositivo (remove do banco e do PushManager).
  async function disable() {
    if (!pushSupported) return
    busy.value = true
    try {
      const reg = await navigator.serviceWorker.ready
      const sub = await reg.pushManager.getSubscription()
      if (sub) {
        await supabase.from('push_subscriptions').delete().eq('endpoint', sub.endpoint)
        await sub.unsubscribe()
      }
      subscribed.value = false
    } finally {
      busy.value = false
    }
  }

  return { permission, subscribed, busy, refresh, enable, disable }
}
