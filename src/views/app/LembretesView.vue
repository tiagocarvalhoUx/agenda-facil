<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { useToast } from '@/composables/useToast'
import { formatHora } from '@/lib/format'
import type { AppointmentStatus, ReminderChannel, ReminderStatus } from '@/types/database.types'
import {
  VARIAVEIS,
  MENSAGEM_PADRAO,
  renderTemplate,
  waLink,
  temTelefone,
  loadTemplate,
  saveTemplate,
  loadSentLog,
  markSent,
  clearSent,
  type TemplateVars,
  type SentLog,
} from '@/lib/whatsapp'
import PageHeader from '@/components/app/PageHeader.vue'
import BaseButton from '@/components/ui/BaseButton.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import BaseSkeleton from '@/components/ui/BaseSkeleton.vue'
import {
  RefreshCw,
  MessageSquare,
  Send,
  Check,
  Eye,
  EyeOff,
  RotateCcw,
  Save,
  Info,
  BellRing,
  Clock,
  User,
  CalendarClock,
} from '@lucide/vue'

// Lembretes via WhatsApp: ferramenta de envio MANUAL (link wa.me) + editor da
// mensagem + histórico local dos envios + fila dos lembretes automáticos (que
// rodam no servidor). O rastreio de envios manuais vive no localStorage do
// tenant (ver @/lib/whatsapp); a tabela `reminders` só é lida aqui.
const auth = useAuthStore()
const toast = useToast()
const TZ = 'America/Sao_Paulo'

type Aba = 'agendamentos' | 'historico' | 'mensagem' | 'automaticos'
const aba = ref<Aba>('agendamentos')

interface ApptRow {
  id: string
  inicio_at: string
  status: AppointmentStatus
  customer: { nome: string; telefone: string } | null
  professional: { nome: string } | null
  service: { nome: string } | null
}

const rows = ref<ApptRow[]>([])
const loading = ref(true)
const sentLog = ref<SentLog>({})

// ---------- Datas / variáveis da mensagem ----------
function periodoSaudacao(iso: string): string {
  const h = Number(
    new Intl.DateTimeFormat('pt-BR', { hour: 'numeric', hour12: false, timeZone: TZ }).format(new Date(iso)),
  )
  if (h < 12) return 'bom dia'
  if (h < 18) return 'boa tarde'
  return 'boa noite'
}

function relativeDay(iso: string): string {
  const alvo = new Date(iso)
  alvo.setHours(0, 0, 0, 0)
  const hoje = new Date()
  hoje.setHours(0, 0, 0, 0)
  const diff = Math.round((alvo.getTime() - hoje.getTime()) / 86_400_000)
  if (diff === 0) return 'hoje'
  if (diff === 1) return 'amanhã'
  return new Intl.DateTimeFormat('pt-BR', { weekday: 'long', timeZone: TZ }).format(new Date(iso))
}

function dataCompleta(iso: string): string {
  return new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric', timeZone: TZ }).format(
    new Date(iso),
  )
}

function varsFrom(r: ApptRow): TemplateVars {
  return {
    nome: r.customer?.nome?.split(' ')[0] ?? 'cliente',
    periodo: periodoSaudacao(r.inicio_at),
    quando: relativeDay(r.inicio_at),
    data: dataCompleta(r.inicio_at),
    hora: formatHora(r.inicio_at),
    profissional: r.professional?.nome ?? '',
    servico: r.service?.nome ?? '',
  }
}

// ---------- Carregamento ----------
async function loadAgendamentos() {
  loading.value = true
  const inicio = new Date()
  const fim = new Date()
  fim.setDate(fim.getDate() + 7)
  const { data, error } = await supabase
    .from('appointments')
    .select(
      'id, inicio_at, status, customer:customers(nome, telefone), professional:professionals(nome), service:services(nome)',
    )
    .gte('inicio_at', inicio.toISOString())
    .lte('inicio_at', fim.toISOString())
    .neq('status', 'cancelado')
    .is('deleted_at', null)
    .order('inicio_at')
  if (error) {
    toast.error('Não foi possível carregar os agendamentos.')
  } else {
    rows.value = (data as unknown as ApptRow[]) ?? []
  }
  loading.value = false
}

function refreshLog() {
  if (auth.tenant) sentLog.value = loadSentLog(auth.tenant.id)
}

async function atualizar() {
  refreshLog()
  await loadAgendamentos()
  if (aba.value === 'automaticos') await loadFila()
}

onMounted(() => {
  refreshLog()
  loadTemplateFromStore()
  void loadAgendamentos()
})

// ---------- Aba: Agendamentos (pendentes de envio) ----------
// Ainda não lembrados manualmente e não confirmados.
const pendentes = computed(() =>
  rows.value.filter((r) => !sentLog.value[r.id] && r.status !== 'confirmado'),
)

function enviarWhatsApp(r: ApptRow) {
  if (!temTelefone(r.customer?.telefone)) {
    toast.error('Este cliente não tem telefone cadastrado.')
    return
  }
  const texto = renderTemplate(template.value, varsFrom(r))
  window.open(waLink(r.customer!.telefone, texto), '_blank', 'noopener')
  sentLog.value = markSent(auth.tenant!.id, r.id)
  toast.success('WhatsApp aberto com a mensagem pronta. Registrado no histórico.')
}

// ---------- Aba: Histórico ----------
const mostrarConfirmados = ref(false)

// Enviados (no log). Confirmados = agendamento com status 'confirmado'.
const historico = computed(() => {
  const enviados = rows.value.filter((r) => sentLog.value[r.id])
  return mostrarConfirmados.value ? enviados : enviados.filter((r) => r.status !== 'confirmado')
})

async function marcarConfirmado(r: ApptRow) {
  const { error } = await supabase.from('appointments').update({ status: 'confirmado' }).eq('id', r.id)
  if (error) {
    toast.error('Não foi possível confirmar.')
    return
  }
  r.status = 'confirmado'
  toast.success('Agendamento confirmado.')
}

function reenviar(r: ApptRow) {
  enviarWhatsApp(r)
}

function removerDoHistorico(r: ApptRow) {
  sentLog.value = clearSent(auth.tenant!.id, r.id)
}

// ---------- Aba: Mensagem ----------
const template = ref(MENSAGEM_PADRAO)
const msgArea = ref<HTMLTextAreaElement | null>(null)

function loadTemplateFromStore() {
  if (auth.tenant) template.value = loadTemplate(auth.tenant.id)
}

function inserirVariavel(v: string) {
  const el = msgArea.value
  const tag = `{${v}}`
  if (!el) {
    template.value += tag
    return
  }
  const start = el.selectionStart ?? template.value.length
  const end = el.selectionEnd ?? template.value.length
  template.value = template.value.slice(0, start) + tag + template.value.slice(end)
  // Reposiciona o cursor após a variável inserida.
  requestAnimationFrame(() => {
    el.focus()
    const pos = start + tag.length
    el.setSelectionRange(pos, pos)
  })
}

function restaurarPadrao() {
  template.value = MENSAGEM_PADRAO
}

function salvarTemplate() {
  if (!template.value.trim()) {
    toast.error('A mensagem não pode ficar vazia.')
    return
  }
  saveTemplate(auth.tenant!.id, template.value)
  toast.success('Mensagem salva.')
}

// Preview: usa o próximo agendamento; se não houver, dados de exemplo.
const exemploVars: TemplateVars = {
  nome: 'Ana',
  periodo: 'bom dia',
  quando: 'amanhã',
  data: '25/05/2026',
  hora: '14:00',
  profissional: 'Maria',
  servico: 'Corte de Cabelo',
}
const previewVars = computed<TemplateVars>(() => (rows.value[0] ? varsFrom(rows.value[0]) : exemploVars))
const preview = computed(() => renderTemplate(template.value, previewVars.value))

// ---------- Aba: Automáticos (fila real da tabela reminders) ----------
interface FilaRow {
  id: string
  canal: ReminderChannel
  agendado_para: string
  status: ReminderStatus
  appointment: {
    inicio_at: string
    customer: { nome: string } | null
    professional: { nome: string } | null
    service: { nome: string } | null
  } | null
}
const fila = ref<FilaRow[]>([])
const filaLoading = ref(false)

async function loadFila() {
  filaLoading.value = true
  const { data, error } = await supabase
    .from('reminders')
    .select(
      'id, canal, agendado_para, status, appointment:appointments(inicio_at, customer:customers(nome), professional:professionals(nome), service:services(nome))',
    )
    .eq('status', 'pendente')
    .gte('agendado_para', new Date().toISOString())
    .order('agendado_para')
    .limit(100)
  if (!error) fila.value = (data as unknown as FilaRow[]) ?? []
  filaLoading.value = false
}

const CANAL_LABEL: Record<ReminderChannel, string> = { email: 'E-mail', whatsapp: 'WhatsApp', sms: 'SMS' }

function irParaAba(a: Aba) {
  aba.value = a
  if (a === 'automaticos' && fila.value.length === 0) void loadFila()
}

const tabs = computed(() => [
  { id: 'agendamentos' as Aba, label: `Agendamentos (${pendentes.value.length})`, icon: null },
  { id: 'historico' as Aba, label: `Histórico (${historico.value.length})`, icon: null },
  { id: 'mensagem' as Aba, label: 'Mensagem', icon: MessageSquare },
  { id: 'automaticos' as Aba, label: 'Automáticos', icon: BellRing },
])
</script>

<template>
  <div class="mx-auto max-w-3xl p-4 sm:p-5">
    <PageHeader
      eyebrow="WhatsApp"
      title="Lembretes via WhatsApp"
      subtitle="Envie lembretes manuais para seus agendamentos (próximos 7 dias)"
    >
      <template #actions>
        <BaseButton variant="secondary" :loading="loading" @click="atualizar">
          <RefreshCw class="h-4 w-4" :stroke-width="2" /> Atualizar
        </BaseButton>
      </template>
    </PageHeader>

    <!-- Abas -->
    <div class="mb-5 flex gap-1 overflow-x-auto border-b border-border">
      <button
        v-for="t in tabs"
        :key="t.id"
        class="flex items-center gap-1.5 whitespace-nowrap border-b-2 px-3 pb-2.5 pt-1 text-small font-medium transition-colors duration-fast"
        :class="aba === t.id
          ? 'border-accent text-accent'
          : 'border-transparent text-text-muted hover:text-text'"
        @click="irParaAba(t.id)"
      >
        <component :is="t.icon" v-if="t.icon" class="h-4 w-4" :stroke-width="2" />
        {{ t.label }}
      </button>
    </div>

    <!-- ============ Agendamentos ============ -->
    <section v-if="aba === 'agendamentos'" class="flex flex-col gap-3">
      <template v-if="loading">
        <BaseSkeleton v-for="i in 3" :key="i" height="5rem" rounded="lg" />
      </template>

      <EmptyState
        v-else-if="pendentes.length === 0"
        icon="💬"
        title="Nenhum agendamento"
        description="Não há agendamentos pendentes de lembrete nos próximos 7 dias."
      />

      <div
        v-for="r in pendentes"
        v-else
        :key="r.id"
        class="flex flex-col gap-3 rounded-2xl border border-border bg-surface p-4 shadow-card sm:flex-row sm:items-center sm:justify-between"
      >
        <div class="min-w-0">
          <p class="truncate text-body font-semibold text-text">{{ r.customer?.nome ?? 'Cliente' }}</p>
          <p class="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-small text-text-muted">
            <span class="inline-flex items-center gap-1">
              <CalendarClock class="h-3.5 w-3.5" :stroke-width="2" />
              {{ dataCompleta(r.inicio_at) }} às {{ formatHora(r.inicio_at) }}
            </span>
            <span v-if="r.professional" class="inline-flex items-center gap-1">
              <User class="h-3.5 w-3.5" :stroke-width="2" />{{ r.professional.nome }}
            </span>
            <span v-if="r.service">· {{ r.service.nome }}</span>
          </p>
          <p v-if="!temTelefone(r.customer?.telefone)" class="mt-1 text-caption text-warning">
            Sem telefone cadastrado
          </p>
        </div>
        <BaseButton
          class="shrink-0"
          :disabled="!temTelefone(r.customer?.telefone)"
          @click="enviarWhatsApp(r)"
        >
          <Send class="h-4 w-4" :stroke-width="2" /> Enviar lembrete
        </BaseButton>
      </div>
    </section>

    <!-- ============ Histórico ============ -->
    <section v-else-if="aba === 'historico'" class="flex flex-col gap-3">
      <div class="flex justify-end">
        <button
          class="inline-flex items-center gap-1.5 text-small text-text-muted transition-colors hover:text-text"
          @click="mostrarConfirmados = !mostrarConfirmados"
        >
          <component :is="mostrarConfirmados ? EyeOff : Eye" class="h-4 w-4" :stroke-width="2" />
          {{ mostrarConfirmados ? 'Ocultar Confirmados' : 'Mostrar Confirmados' }}
        </button>
      </div>

      <EmptyState
        v-if="historico.length === 0"
        icon="💬"
        title="Nenhum lembrete"
        description="Não há lembretes pendentes ou enviados. Use o toggle acima para ver confirmados."
      />

      <div
        v-for="r in historico"
        v-else
        :key="r.id"
        class="flex flex-col gap-3 rounded-2xl border border-border bg-surface p-4 shadow-card sm:flex-row sm:items-center sm:justify-between"
      >
        <div class="min-w-0">
          <div class="flex items-center gap-2">
            <p class="truncate text-body font-semibold text-text">{{ r.customer?.nome ?? 'Cliente' }}</p>
            <span
              v-if="r.status === 'confirmado'"
              class="inline-flex items-center gap-1 rounded-full bg-success px-2 py-0.5 text-caption font-medium text-white"
            >
              <Check class="h-3 w-3" :stroke-width="3" /> Confirmado
            </span>
            <span
              v-else
              class="inline-flex items-center gap-1 rounded-full bg-accent-soft px-2 py-0.5 text-caption font-medium text-accent"
            >
              <Clock class="h-3 w-3" :stroke-width="2.5" /> Aguardando
            </span>
          </div>
          <p class="mt-0.5 text-small text-text-muted">
            {{ dataCompleta(r.inicio_at) }} às {{ formatHora(r.inicio_at) }}
            <template v-if="r.professional"> · {{ r.professional.nome }}</template>
          </p>
        </div>
        <div class="flex shrink-0 items-center gap-2">
          <BaseButton variant="ghost" @click="reenviar(r)">
            <Send class="h-4 w-4" :stroke-width="2" /> Reenviar
          </BaseButton>
          <BaseButton v-if="r.status !== 'confirmado'" variant="secondary" @click="marcarConfirmado(r)">
            <Check class="h-4 w-4" :stroke-width="2" /> Confirmar
          </BaseButton>
          <button
            class="text-caption text-text-muted underline underline-offset-2 hover:text-text"
            @click="removerDoHistorico(r)"
          >
            Remover
          </button>
        </div>
      </div>
    </section>

    <!-- ============ Mensagem ============ -->
    <section v-else-if="aba === 'mensagem'" class="flex flex-col gap-4">
      <div class="rounded-2xl border border-border bg-surface p-5 shadow-card">
        <h2 class="flex items-center gap-2 text-h3 font-display text-text">
          <MessageSquare class="h-5 w-5 text-accent" :stroke-width="2" /> Mensagem de Lembrete
        </h2>
        <p class="mt-1 text-small text-text-muted">
          Personalize o texto enviado aos clientes. Use as variáveis abaixo para incluir dados do agendamento.
        </p>

        <div class="mt-4 flex flex-wrap items-center gap-2">
          <button
            v-for="v in VARIAVEIS"
            :key="v"
            class="rounded-md border border-accent-border bg-accent-soft px-2 py-1 font-mono text-caption text-accent transition-opacity hover:opacity-80"
            @click="inserirVariavel(v)"
          >
            {{ '{' + v + '}' }}
          </button>
          <span class="text-caption text-text-muted">Clique para inserir</span>
        </div>

        <textarea
          ref="msgArea"
          v-model="template"
          rows="4"
          class="mt-3 w-full resize-y rounded-lg border border-border bg-surface-2 p-3 text-small text-text outline-none focus:border-accent"
          placeholder="Escreva a mensagem do lembrete…"
        />

        <div class="mt-2 flex justify-end">
          <button
            class="inline-flex items-center gap-1.5 text-caption text-text-muted transition-colors hover:text-text"
            @click="restaurarPadrao"
          >
            <RotateCcw class="h-3.5 w-3.5" :stroke-width="2" /> Restaurar mensagem padrão
          </button>
        </div>
      </div>

      <div class="rounded-2xl border border-accent-border bg-accent-soft p-5">
        <h3 class="flex items-center gap-2 text-body font-semibold text-accent">
          <Eye class="h-4 w-4" :stroke-width="2" /> Preview da mensagem
        </h3>
        <div class="mt-3 rounded-lg border border-border bg-surface p-3 text-small text-text">
          {{ preview }}
        </div>
        <p class="mt-2 text-caption text-accent">
          Exemplo com: cliente "{{ previewVars.nome }}", {{ previewVars.quando }}, às
          {{ previewVars.hora }}, profissional {{ previewVars.profissional }}, serviço "{{ previewVars.servico }}",
          saudação "{{ previewVars.periodo }}".
        </p>
      </div>

      <div class="flex items-start gap-2 rounded-2xl border border-border bg-surface-2 p-4 text-small text-text-muted">
        <Info class="mt-0.5 h-4 w-4 shrink-0 text-accent" :stroke-width="2" />
        <p>
          Esta personalização se aplica apenas aos lembretes enviados manualmente. Os lembretes automáticos usam um
          template fixo aprovado pela Meta.
        </p>
      </div>

      <div class="flex justify-end">
        <BaseButton @click="salvarTemplate">
          <Save class="h-4 w-4" :stroke-width="2" /> Salvar template
        </BaseButton>
      </div>
    </section>

    <!-- ============ Automáticos ============ -->
    <section v-else class="flex flex-col gap-4">
      <div class="rounded-2xl border border-border bg-surface p-5 shadow-card">
        <h2 class="flex items-center gap-2 text-h3 font-display text-text">
          <BellRing class="h-5 w-5 text-accent" :stroke-width="2" /> Lembretes automáticos
        </h2>
        <p class="mt-1 text-small text-text-muted">
          O sistema agenda automaticamente um lembrete <strong class="text-text">24h</strong> e outro
          <strong class="text-text">2h</strong> antes de cada agendamento. Abaixo está a fila dos que ainda serão
          enviados.
        </p>
      </div>

      <div class="flex items-center justify-between">
        <p class="text-small font-medium text-text">Fila de envio ({{ fila.length }})</p>
        <BaseButton variant="ghost" :loading="filaLoading" @click="loadFila">
          <RefreshCw class="h-4 w-4" :stroke-width="2" /> Atualizar fila
        </BaseButton>
      </div>

      <template v-if="filaLoading">
        <BaseSkeleton v-for="i in 3" :key="i" height="4rem" rounded="lg" />
      </template>

      <EmptyState
        v-else-if="fila.length === 0"
        icon="🔔"
        title="Fila vazia"
        description="Não há lembretes automáticos agendados no momento."
      />

      <div
        v-for="f in fila"
        v-else
        :key="f.id"
        class="flex items-center justify-between gap-3 rounded-2xl border border-border bg-surface p-4 shadow-card"
      >
        <div class="min-w-0">
          <p class="truncate text-body font-semibold text-text">
            {{ f.appointment?.customer?.nome ?? 'Cliente' }}
          </p>
          <p class="mt-0.5 text-small text-text-muted">
            Agendamento {{ f.appointment ? dataCompleta(f.appointment.inicio_at) : '—' }}
            <template v-if="f.appointment"> às {{ formatHora(f.appointment.inicio_at) }}</template>
          </p>
        </div>
        <div class="shrink-0 text-right">
          <span class="inline-flex items-center gap-1 rounded-full bg-accent-soft px-2 py-0.5 text-caption font-medium text-accent">
            {{ CANAL_LABEL[f.canal] }}
          </span>
          <p class="mt-1 text-caption text-text-muted">
            envia {{ dataCompleta(f.agendado_para) }} {{ formatHora(f.agendado_para) }}
          </p>
        </div>
      </div>

      <div class="flex items-start gap-2 rounded-2xl border border-border bg-surface-2 p-4 text-small text-text-muted">
        <Info class="mt-0.5 h-4 w-4 shrink-0 text-accent" :stroke-width="2" />
        <p>
          Os lembretes automáticos usam um template fixo aprovado pela Meta e são disparados pelo servidor no horário
          agendado — não dependem deste dispositivo estar aberto.
        </p>
      </div>
    </section>
  </div>
</template>
