<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useToast } from '@/composables/useToast'
import { waLink, temTelefone } from '@/lib/whatsapp'
import {
  DIAS_OPCOES,
  fetchInativos,
  fetchCampanhas,
  fetchStats,
  fetchRecipients,
  criarCampanha,
  marcarEnviado,
  gerarMensagensIA,
  type ClienteInativo,
  type CampaignStats,
  type RecipientRow,
} from '@/lib/reativacao'
import type { Campaign } from '@/types/database.types'
import PageHeader from '@/components/app/PageHeader.vue'
import BaseButton from '@/components/ui/BaseButton.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import BaseSkeleton from '@/components/ui/BaseSkeleton.vue'
import {
  Sparkles,
  RefreshCw,
  Send,
  Check,
  Users,
  Wand2,
  ChevronLeft,
  Info,
  MessageSquare,
} from '@lucide/vue'

// Reativação de Clientes por IA (Fase 1): segmenta a base parada (RPC),
// gera a mensagem com IA (Edge Function) e dispara MANUALMENTE via wa.me —
// mesmo modelo dos Lembretes, sem API oficial e sem custo por mensagem.
// A conversão (cliente agendou depois do envio) vem de reativacao_campaign_stats.
const auth = useAuthStore()
const toast = useToast()
const TZ = 'America/Sao_Paulo'

type Aba = 'nova' | 'campanhas'
const aba = ref<Aba>('nova')

// ---------- Passo 1: clientes inativos ----------
const dias = ref<number>(90)
const inativos = ref<ClienteInativo[]>([])
const loadingInativos = ref(false)
const selecionados = ref<Set<string>>(new Set())

async function loadInativos() {
  if (!auth.tenant) return
  loadingInativos.value = true
  try {
    inativos.value = await fetchInativos(auth.tenant.id, dias.value)
    // Pré-seleciona todos que têm telefone.
    selecionados.value = new Set(
      inativos.value.filter((c) => temTelefone(c.telefone)).map((c) => c.customer_id),
    )
  } catch {
    toast.error('Não foi possível carregar os clientes inativos.')
  }
  loadingInativos.value = false
}

function setDias(d: number) {
  dias.value = d
  void loadInativos()
}

function toggleCliente(id: string) {
  const s = new Set(selecionados.value)
  if (s.has(id)) s.delete(id)
  else s.add(id)
  selecionados.value = s
}

function toggleTodos() {
  const comFone = inativos.value.filter((c) => temTelefone(c.telefone))
  selecionados.value =
    selecionados.value.size === comFone.length ? new Set() : new Set(comFone.map((c) => c.customer_id))
}

function dataCurta(iso: string): string {
  return new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric', timeZone: TZ }).format(
    new Date(iso),
  )
}

function haQuanto(iso: string): string {
  const d = Math.floor((Date.now() - new Date(iso).getTime()) / 86_400_000)
  if (d < 60) return `há ${d} dias`
  return `há ${Math.floor(d / 30)} meses`
}

// ---------- Passo 2: mensagem por IA ----------
const objetivo = ref('')
const tom = ref<'amigavel' | 'profissional' | 'descontraido'>('amigavel')
const oferta = ref('')
const gerando = ref(false)
const sugestoes = ref<string[]>([])
const mensagem = ref('')

const TONS = [
  { id: 'amigavel' as const, label: 'Amigável' },
  { id: 'profissional' as const, label: 'Profissional' },
  { id: 'descontraido' as const, label: 'Descontraído' },
]

async function gerar() {
  if (!auth.tenant) return
  gerando.value = true
  try {
    sugestoes.value = await gerarMensagensIA({
      tenantId: auth.tenant.id,
      objetivo: objetivo.value || 'reativar clientes que não voltam há algum tempo',
      tom: tom.value,
      oferta: oferta.value,
      diasInatividade: dias.value,
    })
    if (sugestoes.value[0]) mensagem.value = sugestoes.value[0]
  } catch (e) {
    toast.error(
      (e as Error).message === 'sem_creditos'
        ? 'A conta de IA está sem créditos. Adicione créditos em console.anthropic.com → Plans & Billing.'
        : 'A IA não conseguiu gerar a mensagem. Tente novamente.',
    )
  }
  gerando.value = false
}

const previewMensagem = computed(() => {
  const primeiro = inativos.value.find((c) => selecionados.value.has(c.customer_id))
  const nome = primeiro?.nome?.split(' ')[0] ?? 'Ana'
  return mensagem.value.replace(/\{nome\}/g, nome)
})

// ---------- Passo 3: criar campanha ----------
const nomeCampanha = ref('')
const criando = ref(false)

const podeCriar = computed(() => mensagem.value.trim().length > 0 && selecionados.value.size > 0)

async function criar() {
  if (!auth.tenant || !podeCriar.value) return
  criando.value = true
  try {
    const c = await criarCampanha({
      tenantId: auth.tenant.id,
      nome: nomeCampanha.value.trim() || `Reativação ${dataCurta(new Date().toISOString())}`,
      objetivo: objetivo.value,
      mensagem: mensagem.value.trim(),
      diasInatividade: dias.value,
      customerIds: [...selecionados.value],
    })
    toast.success('Campanha criada! Agora é só disparar as mensagens.')
    await loadCampanhas()
    abrirCampanha(c)
    aba.value = 'campanhas'
    // Limpa o formulário para a próxima.
    nomeCampanha.value = ''
    sugestoes.value = []
  } catch {
    toast.error('Não foi possível criar a campanha.')
  }
  criando.value = false
}

// ---------- Aba: campanhas (histórico + disparo) ----------
const campanhas = ref<Campaign[]>([])
const stats = ref<Record<string, CampaignStats>>({})
const loadingCampanhas = ref(false)
const ativa = ref<Campaign | null>(null)
const recipients = ref<RecipientRow[]>([])
const loadingRecipients = ref(false)

async function loadCampanhas() {
  if (!auth.tenant) return
  loadingCampanhas.value = true
  try {
    ;[campanhas.value, stats.value] = await Promise.all([
      fetchCampanhas(auth.tenant.id),
      fetchStats(auth.tenant.id),
    ])
  } catch {
    toast.error('Não foi possível carregar as campanhas.')
  }
  loadingCampanhas.value = false
}

async function abrirCampanha(c: Campaign) {
  ativa.value = c
  loadingRecipients.value = true
  try {
    recipients.value = await fetchRecipients(c.id)
  } catch {
    toast.error('Não foi possível carregar os destinatários.')
  }
  loadingRecipients.value = false
}

function fecharCampanha() {
  ativa.value = null
  void loadCampanhas() // atualiza os números (enviados/reativados)
}

const pendentesEnvio = computed(() => recipients.value.filter((r) => !r.enviado_at))
const jaEnviados = computed(() => recipients.value.filter((r) => r.enviado_at))

async function enviarWhatsApp(r: RecipientRow) {
  if (!ativa.value || !r.customer || !temTelefone(r.customer.telefone)) {
    toast.error('Este cliente não tem telefone cadastrado.')
    return
  }
  const texto = ativa.value.mensagem.replace(/\{nome\}/g, r.customer.nome.split(' ')[0] ?? '')
  window.open(waLink(r.customer.telefone, texto), '_blank', 'noopener')
  try {
    await marcarEnviado(r.id)
    r.enviado_at = new Date().toISOString()
  } catch {
    toast.error('WhatsApp aberto, mas não foi possível registrar o envio.')
  }
}

onMounted(() => {
  void loadInativos()
  void loadCampanhas()
})

const tabs = computed(() => [
  { id: 'nova' as Aba, label: 'Nova campanha', icon: Wand2 },
  { id: 'campanhas' as Aba, label: `Campanhas (${campanhas.value.length})`, icon: MessageSquare },
])
</script>

<template>
  <div class="mx-auto max-w-3xl p-4 sm:p-5">
    <PageHeader
      eyebrow="IA"
      title="Reativação de Clientes"
      subtitle="Transforme sua base parada em novos agendamentos com campanhas escritas por IA"
    >
      <template #actions>
        <BaseButton variant="secondary" :loading="loadingInativos" @click="loadInativos">
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
        :class="aba === t.id ? 'border-accent text-accent' : 'border-transparent text-text-muted hover:text-text'"
        @click="aba = t.id"
      >
        <component :is="t.icon" class="h-4 w-4" :stroke-width="2" />
        {{ t.label }}
      </button>
    </div>

    <!-- ============ Nova campanha ============ -->
    <section v-if="aba === 'nova'" class="flex flex-col gap-4">
      <!-- Passo 1: segmentação -->
      <div class="rounded-2xl border border-border bg-surface p-5 shadow-card">
        <h2 class="flex items-center gap-2 text-h3 font-display text-text">
          <Users class="h-5 w-5 text-accent" :stroke-width="2" /> 1. Clientes inativos
        </h2>
        <p class="mt-1 text-small text-text-muted">
          Clientes sem visita no período escolhido e sem agendamento futuro.
        </p>

        <div class="mt-4 flex flex-wrap items-center gap-2">
          <button
            v-for="d in DIAS_OPCOES"
            :key="d"
            class="rounded-pill border px-3 py-1.5 text-small font-medium transition-colors duration-fast"
            :class="dias === d
              ? 'border-accent bg-accent-soft text-accent'
              : 'border-border text-text-muted hover:text-text'"
            @click="setDias(d)"
          >
            {{ d }}+ dias
          </button>
        </div>

        <template v-if="loadingInativos">
          <BaseSkeleton v-for="i in 3" :key="i" class="mt-3" height="3.5rem" rounded="lg" />
        </template>

        <EmptyState
          v-else-if="inativos.length === 0"
          icon="🎉"
          title="Nenhum cliente parado"
          description="Todos os seus clientes visitaram recentemente ou já têm agendamento futuro."
          class="mt-4"
        />

        <template v-else>
          <div class="mt-4 flex items-center justify-between">
            <p class="text-small text-text-muted">
              <strong class="text-text">{{ selecionados.size }}</strong> de {{ inativos.length }} selecionados
            </p>
            <button class="text-caption text-accent underline underline-offset-2" @click="toggleTodos">
              Selecionar todos / nenhum
            </button>
          </div>
          <div class="mt-2 flex max-h-72 flex-col gap-1.5 overflow-y-auto pr-1">
            <label
              v-for="c in inativos"
              :key="c.customer_id"
              class="flex cursor-pointer items-center gap-3 rounded-lg border border-border bg-surface-2 p-3 transition-colors duration-fast"
              :class="{ 'opacity-50': !temTelefone(c.telefone) }"
            >
              <input
                type="checkbox"
                class="h-4 w-4 accent-[var(--accent)]"
                :checked="selecionados.has(c.customer_id)"
                :disabled="!temTelefone(c.telefone)"
                @change="toggleCliente(c.customer_id)"
              />
              <div class="min-w-0 flex-1">
                <p class="truncate text-small font-semibold text-text">{{ c.nome }}</p>
                <p class="text-caption text-text-muted">
                  Última visita {{ haQuanto(c.ultima_visita) }} ({{ dataCurta(c.ultima_visita) }}) ·
                  {{ c.total_visitas }} visita(s)
                  <template v-if="!temTelefone(c.telefone)"> · sem telefone</template>
                </p>
              </div>
            </label>
          </div>
        </template>
      </div>

      <!-- Passo 2: mensagem por IA -->
      <div class="rounded-2xl border border-border bg-surface p-5 shadow-card">
        <h2 class="flex items-center gap-2 text-h3 font-display text-text">
          <Sparkles class="h-5 w-5 text-accent" :stroke-width="2" /> 2. Mensagem por IA
        </h2>
        <p class="mt-1 text-small text-text-muted">
          Descreva o objetivo e deixe a IA escrever. Você pode editar o texto antes de criar a campanha.
        </p>

        <div class="mt-4 flex flex-col gap-3">
          <input
            v-model="objetivo"
            type="text"
            class="w-full rounded-lg border border-border bg-surface-2 p-3 text-small text-text outline-none focus:border-accent"
            placeholder="Objetivo (ex.: trazer de volta quem sumiu, divulgar horários de julho…)"
          />
          <input
            v-model="oferta"
            type="text"
            class="w-full rounded-lg border border-border bg-surface-2 p-3 text-small text-text outline-none focus:border-accent"
            placeholder="Oferta opcional (ex.: 10% de desconto na volta)"
          />
          <div class="flex flex-wrap items-center gap-2">
            <span class="text-caption text-text-muted">Tom:</span>
            <button
              v-for="t in TONS"
              :key="t.id"
              class="rounded-pill border px-3 py-1 text-caption font-medium transition-colors duration-fast"
              :class="tom === t.id
                ? 'border-accent bg-accent-soft text-accent'
                : 'border-border text-text-muted hover:text-text'"
              @click="tom = t.id"
            >
              {{ t.label }}
            </button>
          </div>
          <div>
            <BaseButton :loading="gerando" @click="gerar">
              <Wand2 class="h-4 w-4" :stroke-width="2" />
              {{ sugestoes.length ? 'Gerar novamente' : 'Gerar mensagem com IA' }}
            </BaseButton>
          </div>
        </div>

        <!-- Sugestões da IA -->
        <div v-if="sugestoes.length" class="mt-4 flex flex-col gap-2">
          <p class="text-caption font-medium text-text-muted">Escolha uma sugestão:</p>
          <button
            v-for="(s, i) in sugestoes"
            :key="i"
            class="rounded-lg border p-3 text-left text-small transition-colors duration-fast"
            :class="mensagem === s
              ? 'border-accent bg-accent-soft text-text'
              : 'border-border bg-surface-2 text-text-muted hover:text-text'"
            @click="mensagem = s"
          >
            {{ s }}
          </button>
        </div>

        <div v-if="mensagem" class="mt-4">
          <p class="mb-1 text-caption font-medium text-text-muted">
            Mensagem final (use <span class="font-mono text-accent">{nome}</span> para o nome do cliente):
          </p>
          <textarea
            v-model="mensagem"
            rows="4"
            class="w-full resize-y rounded-lg border border-border bg-surface-2 p-3 text-small text-text outline-none focus:border-accent"
          />
          <div class="mt-2 rounded-lg border border-accent-border bg-accent-soft p-3 text-small text-text">
            <p class="mb-1 text-caption font-medium text-accent">Preview:</p>
            {{ previewMensagem }}
          </div>
        </div>
      </div>

      <!-- Passo 3: criar -->
      <div class="rounded-2xl border border-border bg-surface p-5 shadow-card">
        <h2 class="flex items-center gap-2 text-h3 font-display text-text">
          <Send class="h-5 w-5 text-accent" :stroke-width="2" /> 3. Criar campanha
        </h2>
        <div class="mt-3 flex flex-col gap-3 sm:flex-row">
          <input
            v-model="nomeCampanha"
            type="text"
            maxlength="80"
            class="w-full rounded-lg border border-border bg-surface-2 p-3 text-small text-text outline-none focus:border-accent"
            placeholder="Nome da campanha (opcional)"
          />
          <BaseButton class="shrink-0" :disabled="!podeCriar" :loading="criando" @click="criar">
            <Check class="h-4 w-4" :stroke-width="2" />
            Criar com {{ selecionados.size }} cliente(s)
          </BaseButton>
        </div>
        <p v-if="!podeCriar" class="mt-2 text-caption text-text-muted">
          Selecione ao menos 1 cliente e gere (ou escreva) a mensagem para continuar.
        </p>
      </div>

      <div class="flex items-start gap-2 rounded-2xl border border-border bg-surface-2 p-4 text-small text-text-muted">
        <Info class="mt-0.5 h-4 w-4 shrink-0 text-accent" :stroke-width="2" />
        <p>
          O envio é manual: cada clique abre o seu WhatsApp com a mensagem personalizada pronta — sem custo e sem
          risco de bloqueio. Respeite quem pedir para não receber mais mensagens (LGPD).
        </p>
      </div>
    </section>

    <!-- ============ Campanhas ============ -->
    <section v-else class="flex flex-col gap-3">
      <!-- Detalhe: disparo -->
      <template v-if="ativa">
        <button
          class="inline-flex w-fit items-center gap-1 text-small text-text-muted transition-colors hover:text-text"
          @click="fecharCampanha"
        >
          <ChevronLeft class="h-4 w-4" :stroke-width="2" /> Voltar às campanhas
        </button>

        <div class="rounded-2xl border border-border bg-surface p-5 shadow-card">
          <h2 class="text-h3 font-display text-text">{{ ativa.nome }}</h2>
          <p class="mt-1 text-small text-text-muted">
            {{ recipients.length }} destinatário(s) · inativos {{ ativa.dias_inatividade }}+ dias
          </p>
          <div class="mt-3 rounded-lg border border-border bg-surface-2 p-3 text-small text-text">
            {{ ativa.mensagem }}
          </div>
        </div>

        <template v-if="loadingRecipients">
          <BaseSkeleton v-for="i in 3" :key="i" height="4rem" rounded="lg" />
        </template>

        <template v-else>
          <p v-if="pendentesEnvio.length" class="text-small font-medium text-text">
            Pendentes ({{ pendentesEnvio.length }})
          </p>
          <div
            v-for="r in pendentesEnvio"
            :key="r.id"
            class="flex items-center justify-between gap-3 rounded-2xl border border-border bg-surface p-4 shadow-card"
          >
            <div class="min-w-0">
              <p class="truncate text-body font-semibold text-text">{{ r.customer?.nome ?? 'Cliente' }}</p>
              <p v-if="!temTelefone(r.customer?.telefone)" class="text-caption text-warning">Sem telefone</p>
            </div>
            <BaseButton class="shrink-0" :disabled="!temTelefone(r.customer?.telefone)" @click="enviarWhatsApp(r)">
              <Send class="h-4 w-4" :stroke-width="2" /> Enviar
            </BaseButton>
          </div>

          <p v-if="jaEnviados.length" class="mt-2 text-small font-medium text-text">
            Enviados ({{ jaEnviados.length }})
          </p>
          <div
            v-for="r in jaEnviados"
            :key="r.id"
            class="flex items-center justify-between gap-3 rounded-2xl border border-border bg-surface p-4 shadow-card"
          >
            <div class="min-w-0">
              <p class="truncate text-body font-semibold text-text">{{ r.customer?.nome ?? 'Cliente' }}</p>
              <p class="text-caption text-text-muted">Enviado em {{ dataCurta(r.enviado_at!) }}</p>
            </div>
            <div class="flex shrink-0 items-center gap-2">
              <span class="inline-flex items-center gap-1 rounded-full bg-success px-2 py-0.5 text-caption font-medium text-white">
                <Check class="h-3 w-3" :stroke-width="3" /> Enviado
              </span>
              <BaseButton variant="ghost" @click="enviarWhatsApp(r)">
                <Send class="h-4 w-4" :stroke-width="2" /> Reenviar
              </BaseButton>
            </div>
          </div>

          <EmptyState
            v-if="recipients.length === 0"
            icon="📭"
            title="Sem destinatários"
            description="Esta campanha não tem destinatários."
          />
        </template>
      </template>

      <!-- Lista de campanhas -->
      <template v-else>
        <template v-if="loadingCampanhas">
          <BaseSkeleton v-for="i in 3" :key="i" height="5rem" rounded="lg" />
        </template>

        <EmptyState
          v-else-if="campanhas.length === 0"
          icon="✨"
          title="Nenhuma campanha ainda"
          description="Crie sua primeira campanha de reativação na aba ao lado."
        />

        <button
          v-for="c in campanhas"
          v-else
          :key="c.id"
          class="flex flex-col gap-3 rounded-2xl border border-border bg-surface p-4 text-left shadow-card transition-colors duration-fast hover:border-accent sm:flex-row sm:items-center sm:justify-between"
          @click="abrirCampanha(c)"
        >
          <div class="min-w-0">
            <p class="truncate text-body font-semibold text-text">{{ c.nome }}</p>
            <p class="mt-0.5 text-small text-text-muted">
              {{ dataCurta(c.created_at) }} · inativos {{ c.dias_inatividade }}+ dias
            </p>
          </div>
          <div class="flex shrink-0 items-center gap-2 text-caption">
            <span class="rounded-full bg-surface-2 px-2 py-0.5 font-medium text-text-muted">
              {{ stats[c.id]?.total ?? 0 }} clientes
            </span>
            <span class="rounded-full bg-accent-soft px-2 py-0.5 font-medium text-accent">
              {{ stats[c.id]?.enviados ?? 0 }} enviados
            </span>
            <span class="rounded-full bg-success px-2 py-0.5 font-medium text-white">
              {{ stats[c.id]?.convertidos ?? 0 }} reativados
            </span>
          </div>
        </button>
      </template>
    </section>
  </div>
</template>
