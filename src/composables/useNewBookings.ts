import { ref } from 'vue'
import type { RealtimeChannel } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase'
import { useToast } from '@/composables/useToast'

// Camada "app aberto": assina em tempo real os novos agendamentos do tenant e
// dá feedback imediato (toast + som + contador no menu). A RLS garante que só
// chegam eventos do próprio tenant. O push offline é tratado em paralelo pela
// Edge Function — aqui é só o que acontece com o painel aberto.
//
// Estado global (singleton) para o badge do menu e a agenda reagirem juntos.

export interface NewBooking {
  id: string
  inicio_at: string
  origem: string
}

const unreadCount = ref(0)
const listeners = new Set<(b: NewBooking) => void>()
let channel: RealtimeChannel | null = null

// Bipe curto via Web Audio (sem arquivo). Pode ficar suspenso até a primeira
// interação do usuário com a página — nesse caso simplesmente não toca.
function playBeep() {
  try {
    const Ctx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext
    const ctx = new Ctx()
    const osc = ctx.createOscillator()
    const gain = ctx.createGain()
    osc.connect(gain)
    gain.connect(ctx.destination)
    osc.type = 'sine'
    osc.frequency.value = 880
    gain.gain.setValueAtTime(0.0001, ctx.currentTime)
    gain.gain.exponentialRampToValueAtTime(0.2, ctx.currentTime + 0.02)
    gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.4)
    osc.start()
    osc.stop(ctx.currentTime + 0.42)
    osc.onended = () => ctx.close()
  } catch (_e) {
    /* navegador bloqueou áudio — ignora */
  }
}

export function useNewBookings() {
  const toast = useToast()

  // Inicia o canal de realtime para o tenant. Idempotente (um canal por sessão).
  function start(tenantId: string) {
    if (channel) return
    channel = supabase
      .channel(`new-bookings-${tenantId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'appointments',
          filter: `tenant_id=eq.${tenantId}`,
        },
        (payload) => {
          const row = payload.new as NewBooking
          // Só destaca os que vieram do link público (novidade real pro dono).
          if (row.origem !== 'publico') return
          unreadCount.value++
          playBeep()
          toast.success('Novo agendamento recebido! 🗓️')
          listeners.forEach((cb) => cb(row))
        },
      )
      .subscribe()
  }

  function stop() {
    if (channel) {
      void supabase.removeChannel(channel)
      channel = null
    }
  }

  // Registra um handler (ex.: a agenda recarrega o dia). Retorna o "off".
  function onNewBooking(cb: (b: NewBooking) => void): () => void {
    listeners.add(cb)
    return () => listeners.delete(cb)
  }

  function resetUnread() {
    unreadCount.value = 0
  }

  return { unreadCount, start, stop, onNewBooking, resetUnread }
}
