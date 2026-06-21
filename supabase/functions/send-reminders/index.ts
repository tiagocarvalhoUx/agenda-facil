// Edge Function agendada (§6): a cada X min busca lembretes pendentes cuja
// janela chegou e dispara via provedor. Idempotente — marca enviado_at e nunca
// reenvia (status sai de 'pendente'). Roda no SERVIDOR com service_role
// (JAMAIS no frontend — §5.2).
//
// Deploy:  supabase functions deploy send-reminders
// Agendar: pg_cron chamando esta função (ver README) a cada 5 min.

import { createClient } from 'jsr:@supabase/supabase-js@2'
import { getProvider, type ReminderPayload } from './providers.ts'

const TZ = 'America/Sao_Paulo'

function formatQuando(iso: string): string {
  return new Intl.DateTimeFormat('pt-BR', {
    weekday: 'long',
    day: '2-digit',
    month: 'long',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
    timeZone: TZ,
  }).format(new Date(iso))
}

Deno.serve(async (req) => {
  // Protege o endpoint: só aceita com o segredo de cron.
  const auth = req.headers.get('Authorization')
  if (auth !== `Bearer ${Deno.env.get('CRON_SECRET')}`) {
    return new Response('Unauthorized', { status: 401 })
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, // server-only
  )

  // Lembretes pendentes cuja janela já chegou (com folga de 15 min).
  const { data: due, error } = await supabase
    .from('reminders')
    .select(
      'id, canal, appointment:appointments(inicio_at, customer:customers(nome, email), service:services(nome), professional:professionals(nome), tenant:tenants(nome))',
    )
    .eq('status', 'pendente')
    .lte('agendado_para', new Date().toISOString())
    .limit(100)

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }

  let enviados = 0
  let falhas = 0

  for (const r of due ?? []) {
    // Trava idempotente: marca como 'enviado' ANTES de disparar; se falhar,
    // volta para 'falhou'. Evita reenvio em execuções concorrentes.
    const claim = await supabase
      .from('reminders')
      .update({ status: 'enviado', enviado_at: new Date().toISOString() })
      .eq('id', r.id)
      .eq('status', 'pendente')
      .select('id')
      .maybeSingle()

    if (!claim.data) continue // outro worker já pegou

    const appt = (r as Record<string, unknown>).appointment as Record<string, unknown>
    const customer = appt?.customer as { nome: string; email: string | null }
    const destino = customer?.email
    if (!destino) {
      await supabase.from('reminders').update({ status: 'cancelado', erro: 'sem destino' }).eq('id', r.id)
      continue
    }

    const payload: ReminderPayload = {
      destino,
      estabelecimento: (appt.tenant as { nome: string }).nome,
      servico: (appt.service as { nome: string }).nome,
      quando: formatQuando(appt.inicio_at as string),
      profissional: (appt.professional as { nome: string } | null)?.nome,
    }

    try {
      await getProvider(r.canal as string).send(payload)
      enviados++
    } catch (e) {
      falhas++
      await supabase
        .from('reminders')
        .update({ status: 'falhou', erro: String(e), tentativas: 1 })
        .eq('id', r.id)
    }
  }

  return new Response(JSON.stringify({ enviados, falhas }), {
    headers: { 'Content-Type': 'application/json' },
  })
})
