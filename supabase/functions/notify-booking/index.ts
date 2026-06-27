// Edge Function: notifica o DONO quando um cliente agenda pelo link público.
// Chamada pelo trigger trg_notify_new_booking (pg_net) com o appointment_id e
// o segredo NOTIFY_SECRET. Roda no SERVIDOR com service_role — envia Web Push
// assinado com VAPID para todos os dispositivos inscritos do tenant.
//
// Deploy:  supabase functions deploy notify-booking
// Secrets: VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT, NOTIFY_SECRET
//          (e os SUPABASE_URL/SERVICE_ROLE já injetados pela plataforma).

import { createClient } from 'jsr:@supabase/supabase-js@2'
import webpush from 'npm:web-push@3.6.7'

const TZ = 'America/Sao_Paulo'

function formatQuando(iso: string): string {
  return new Intl.DateTimeFormat('pt-BR', {
    weekday: 'short',
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
    timeZone: TZ,
  }).format(new Date(iso))
}

Deno.serve(async (req) => {
  // Protege o endpoint: só o trigger (com o segredo) entra.
  if (req.headers.get('Authorization') !== `Bearer ${Deno.env.get('NOTIFY_SECRET')}`) {
    return new Response('Unauthorized', { status: 401 })
  }

  const vapidPublic = Deno.env.get('VAPID_PUBLIC_KEY')
  const vapidPrivate = Deno.env.get('VAPID_PRIVATE_KEY')
  const vapidSubject = Deno.env.get('VAPID_SUBJECT') ?? 'mailto:no-reply@example.com'
  if (!vapidPublic || !vapidPrivate) {
    return new Response('VAPID keys ausentes', { status: 500 })
  }
  webpush.setVapidDetails(vapidSubject, vapidPublic, vapidPrivate)

  const { appointment_id } = (await req.json().catch(() => ({}))) as { appointment_id?: string }
  if (!appointment_id) {
    return new Response('appointment_id ausente', { status: 400 })
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  // Carrega o agendamento (com nomes para a mensagem).
  const { data: appt, error: apptErr } = await supabase
    .from('appointments')
    .select(
      'tenant_id, inicio_at, customer:customers(nome), service:services(nome), professional:professionals(nome, user_id)',
    )
    .eq('id', appointment_id)
    .maybeSingle()

  if (apptErr || !appt) {
    return new Response(JSON.stringify({ error: apptErr?.message ?? 'not found' }), { status: 404 })
  }

  // Destinatários: TODOS os donos do tenant + o profissional designado neste
  // agendamento (se tiver login). Staff só vê a própria agenda, então notificar
  // outros profissionais sobre um horário que não é deles não faz sentido.
  const { data: owners } = await supabase
    .from('memberships')
    .select('user_id')
    .eq('tenant_id', appt.tenant_id)
    .eq('role', 'owner')

  const recipientIds = new Set<string>((owners ?? []).map((m) => m.user_id))
  const profUserId = (appt.professional as { user_id: string | null } | null)?.user_id
  if (profUserId) recipientIds.add(profUserId)

  if (recipientIds.size === 0) {
    return new Response(JSON.stringify({ enviados: 0 }), { headers: { 'Content-Type': 'application/json' } })
  }

  const { data: subs } = await supabase
    .from('push_subscriptions')
    .select('id, endpoint, p256dh, auth')
    .in('user_id', [...recipientIds])

  const customer = (appt.customer as { nome: string } | null)?.nome ?? 'Cliente'
  const servico = (appt.service as { nome: string } | null)?.nome ?? 'Serviço'
  const profissional = (appt.professional as { nome: string } | null)?.nome
  const payload = JSON.stringify({
    title: 'Novo agendamento 🗓️',
    body: `${customer} marcou ${servico}${profissional ? ` com ${profissional}` : ''} — ${formatQuando(
      appt.inicio_at as string,
    )}`,
    url: '/app/agenda',
  })

  let enviados = 0
  let removidos = 0
  for (const s of subs ?? []) {
    try {
      await webpush.sendNotification(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
        payload,
      )
      enviados++
    } catch (e) {
      // 404/410 = inscrição expirada/cancelada → limpa do banco.
      const status = (e as { statusCode?: number }).statusCode
      if (status === 404 || status === 410) {
        await supabase.from('push_subscriptions').delete().eq('id', s.id)
        removidos++
      }
    }
  }

  return new Response(JSON.stringify({ enviados, removidos }), {
    headers: { 'Content-Type': 'application/json' },
  })
})
