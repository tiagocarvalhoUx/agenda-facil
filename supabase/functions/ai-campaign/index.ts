// Edge Function de IA para campanhas de reativação (Fase 1).
// O dono autenticado pede 3 sugestões de mensagem para reativar clientes
// inativos; a função valida identidade + posse do tenant (como em
// `payments`) e chama a API do Claude com a chave em env secret — a key
// NUNCA vai ao frontend (§5.2). A mensagem volta com a variável {nome}
// para o painel personalizar por cliente antes do wa.me.
//
// Deploy:
//   supabase functions deploy ai-campaign
//   supabase secrets set ANTHROPIC_API_KEY=...

import { createClient } from 'jsr:@supabase/supabase-js@2'
import Anthropic from 'npm:@anthropic-ai/sdk'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS },
  })
}

function service() {
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, // server-only
  )
}

// Saída estruturada: exatamente 3 variações prontas para WhatsApp.
const SCHEMA = {
  type: 'object',
  properties: {
    mensagens: {
      type: 'array',
      items: { type: 'string' },
      description: 'Exatamente 3 variações da mensagem de reativação',
    },
  },
  required: ['mensagens'],
  additionalProperties: false,
} as const

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)

  try {
    const jwt = req.headers.get('Authorization')?.replace('Bearer ', '')
    if (!jwt) return json({ error: 'unauthorized' }, 401)

    const db = service()
    const { data: userData, error: userErr } = await db.auth.getUser(jwt)
    if (userErr || !userData.user) return json({ error: 'unauthorized' }, 401)

    const body = await req.json().catch(() => ({}))
    const tenantId = body.tenant_id as string
    if (!tenantId) return json({ error: 'tenant_id_required' }, 400)

    // Posse: o chamador é OWNER do tenant?
    const { data: mem } = await db
      .from('memberships')
      .select('id')
      .eq('user_id', userData.user.id)
      .eq('tenant_id', tenantId)
      .eq('role', 'owner')
      .maybeSingle()
    if (!mem) return json({ error: 'forbidden' }, 403)

    // Contexto do negócio para a IA escrever algo específico, não genérico.
    const { data: tenant } = await db.from('tenants').select('nome, vertical').eq('id', tenantId).single()
    const { data: servicos } = await db
      .from('services')
      .select('nome')
      .eq('tenant_id', tenantId)
      .is('deleted_at', null)
      .limit(8)

    const objetivo = String(body.objetivo ?? 'reativar clientes que não voltam há algum tempo').slice(0, 300)
    const tom = String(body.tom ?? 'amigavel').slice(0, 40)
    const oferta = String(body.oferta ?? '').slice(0, 200)
    const dias = Number(body.dias_inatividade ?? 90)

    const anthropic = new Anthropic({ apiKey: Deno.env.get('ANTHROPIC_API_KEY')! })

    const prompt = [
      `Estabelecimento: "${tenant?.nome ?? 'meu negócio'}" (segmento: ${tenant?.vertical ?? 'serviços'}).`,
      servicos?.length ? `Serviços oferecidos: ${servicos.map((s) => s.nome).join(', ')}.` : '',
      `Público: clientes que não voltam há mais de ${dias} dias e não têm agendamento futuro.`,
      `Objetivo da campanha: ${objetivo}.`,
      oferta ? `Oferta/incentivo a incluir: ${oferta}.` : 'Sem oferta específica — foque no convite para voltar.',
      `Tom desejado: ${tom}.`,
      '',
      'Escreva 3 variações de mensagem de WhatsApp para reativar esses clientes. Regras:',
      '- Português do Brasil, curta (2 a 4 frases), pronta para enviar no WhatsApp.',
      '- Comece cumprimentando com a variável {nome} (será trocada pelo primeiro nome do cliente).',
      '- Use a variável {nome} exatamente assim, com chaves; não invente outras variáveis.',
      '- Personalize com o contexto do estabelecimento; nada de texto genérico de mala direta.',
      '- Termine com um convite claro para responder a mensagem e agendar.',
      '- Sem saudação de horário (não sabemos quando será enviada) e no máximo 1 emoji por mensagem.',
      '- Inclua uma saída educada, ex.: "se preferir não receber mais mensagens, é só avisar".',
    ]
      .filter(Boolean)
      .join('\n')

    const response = await anthropic.messages.create({
      model: 'claude-opus-4-8',
      max_tokens: 2048,
      thinking: { type: 'adaptive' },
      output_config: {
        effort: 'low',
        format: { type: 'json_schema', schema: SCHEMA },
      },
      system:
        'Você escreve mensagens de WhatsApp para pequenos negócios brasileiros reengajarem clientes inativos. Tom humano e pessoal, como se o próprio dono estivesse escrevendo.',
      messages: [{ role: 'user', content: prompt }],
    })

    if (response.stop_reason === 'refusal') return json({ error: 'ai_refused' }, 502)

    const text = response.content.find((b) => b.type === 'text')?.text ?? ''
    const parsed = JSON.parse(text) as { mensagens: string[] }
    const mensagens = (parsed.mensagens ?? []).map((m) => m.trim()).filter(Boolean).slice(0, 3)
    if (mensagens.length === 0) return json({ error: 'ai_empty' }, 502)

    return json({ mensagens })
  } catch (e) {
    const msg = String((e as Error).message ?? e)
    // Conta Anthropic sem créditos de API → código próprio para o painel orientar.
    if (msg.includes('credit balance')) return json({ error: 'sem_creditos' }, 402)
    return json({ error: msg }, 500)
  }
})
