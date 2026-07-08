<script setup lang="ts">
// Landing de aquisição (tema claro, público). Explica o Agenda Fácil ANTES de
// pedir cadastro — o anúncio aponta pra cá, aquece o lead e envia pro /comecar.
// Sem estado: só conteúdo + CTAs para as rotas de auth (comecar / login).
import { ref, onMounted } from 'vue'
import { trackViewContent, trackLead } from '@/lib/metaPixel'

// Topo de funil: registra a visita à landing (sinal de alto volume p/ o Meta).
onMounted(() => trackViewContent())

const PRECO = 'R$ 49,90'

const recursos = [
  {
    emoji: '🗓️',
    titulo: 'Agenda online 24h',
    texto: 'Seu cliente marca a qualquer hora pelo seu link — sem te ligar, sem WhatsApp manual, sem caderno.',
  },
  {
    emoji: '🔗',
    titulo: 'Seu link exclusivo',
    texto: 'Um endereço só seu para colocar no Instagram e no WhatsApp. Quem clica já cai na sua agenda.',
  },
  {
    emoji: '💬',
    titulo: 'Lembrete de WhatsApp',
    texto: 'Mande o lembrete pronto pro cliente em um toque e derrube as faltas de última hora.',
  },
  {
    emoji: '🔁',
    titulo: 'Cliente remarca sozinho',
    texto: 'Ele recebe um link para remarcar ou cancelar sem falar com você. Menos mensagem, menos trabalho.',
  },
  {
    emoji: '👥',
    titulo: 'Vários profissionais',
    texto: 'Cada profissional com a própria agenda e horários. Ideal para clínicas e salões com equipe.',
  },
  {
    emoji: '📊',
    titulo: 'Financeiro e resumo do dia',
    texto: 'Veja o que já entrou, quantos atendimentos tem hoje e como está o mês — sem planilha.',
  },
]

const passos = [
  { n: '1', titulo: 'Cadastre seus serviços', texto: 'Nome, duração e preço. Leva poucos minutos e já fica no ar.' },
  { n: '2', titulo: 'Compartilhe seu link', texto: 'Cole no Instagram, na bio e no WhatsApp. Pronto para receber marcações.' },
  { n: '3', titulo: 'Receba agendamentos', texto: 'O cliente marca sozinho e cai direto na sua agenda, sem você digitar nada.' },
]

const verticais = ['Clínicas', 'Salões de beleza', 'Barbearias', 'Estética', 'Consultórios', 'Studios']

const faqs = [
  {
    q: 'Preciso instalar alguma coisa?',
    a: 'Não. É tudo online, funciona no celular e no computador. Você e seus clientes só precisam de um navegador.',
  },
  {
    q: 'Meus clientes precisam criar conta?',
    a: 'Não. Eles abrem seu link, escolhem o serviço e o horário, e pronto. Sem cadastro, sem senha, sem app.',
  },
  {
    q: 'Como funciona o teste grátis?',
    a: 'São 7 dias com tudo liberado e sem cartão. Se gostar, assina; se não, é só não continuar.',
  },
  {
    q: 'Serve para o meu tipo de negócio?',
    a: 'Se você atende com hora marcada — clínica, salão, barbearia, estética, consultório — o Agenda Fácil foi feito pra você.',
  },
]

const faqAberta = ref<number | null>(0)
function toggleFaq(i: number) {
  faqAberta.value = faqAberta.value === i ? null : i
}
</script>

<template>
  <div class="min-h-screen bg-bg text-text">
    <!-- ===== Header ===== -->
    <header class="sticky top-0 z-20 border-b border-border bg-bg/85 backdrop-blur">
      <div class="mx-auto flex max-w-6xl items-center justify-between px-4 py-3">
        <span class="font-display text-h2 font-bold text-text">Agenda Fácil</span>
        <nav class="flex items-center gap-3">
          <RouterLink :to="{ name: 'login' }" class="hidden text-small font-medium text-text-muted hover:text-text sm:inline">
            Entrar
          </RouterLink>
          <RouterLink
            :to="{ name: 'comecar' }"
            class="min-h-touch inline-flex items-center rounded-pill bg-accent px-5 text-small font-semibold text-on-accent shadow-glow transition-colors hover:bg-accent-hover"
            @click="trackLead('header')"
          >
            Começar grátis
          </RouterLink>
        </nav>
      </div>
    </header>

    <!-- ===== Hero ===== -->
    <section class="relative overflow-hidden px-4">
      <div class="pointer-events-none absolute left-1/2 top-0 h-96 w-96 -translate-x-1/2 -translate-y-1/3 rounded-full bg-accent opacity-[0.10] blur-[130px]" aria-hidden="true" />
      <div class="anim-fade-up mx-auto grid max-w-6xl items-center gap-6 py-8 lg:grid-cols-2 lg:gap-8 lg:py-16">
        <div class="text-center lg:text-left">
          <p class="eyebrow mb-3">Agendamento online</p>
          <h1 class="mb-4 font-display text-display-lg leading-tight text-text sm:text-[2.75rem] sm:leading-[1.1]">
            Sua agenda online, cheia — sem responder WhatsApp o dia todo.
          </h1>
          <p class="mb-6 text-body text-text-muted sm:text-lg">
            O Agenda Fácil dá ao seu cliente um link para marcar, remarcar e cancelar sozinho.
            Você recebe o agendamento pronto e reduz as faltas. Feito para clínicas, salões e consultórios.
          </p>
          <div class="flex flex-col items-center gap-3 sm:flex-row lg:justify-start">
            <RouterLink
              :to="{ name: 'comecar' }"
              class="min-h-touch inline-flex w-full items-center justify-center rounded-pill bg-accent px-7 text-body font-semibold text-on-accent shadow-glow transition-colors hover:bg-accent-hover sm:w-auto"
              @click="trackLead('hero')"
            >
              Começar grátis por 7 dias
            </RouterLink>
            <RouterLink :to="{ name: 'login' }" class="text-small font-medium text-text-muted underline hover:text-text">
              Já tenho conta
            </RouterLink>
          </div>
          <div class="mt-5 flex flex-wrap items-center justify-center gap-x-5 gap-y-1 text-caption text-text-muted lg:justify-start">
            <span class="flex items-center gap-1"><span class="text-success" aria-hidden="true">✓</span> 7 dias grátis</span>
            <span class="flex items-center gap-1"><span class="text-success" aria-hidden="true">✓</span> Sem cartão</span>
            <span class="flex items-center gap-1"><span class="text-success" aria-hidden="true">✓</span> Cancele quando quiser</span>
          </div>
        </div>
        <div class="mx-auto w-full max-w-md lg:max-w-none">
          <img
            src="/agenda-opengraph.jpg"
            alt="Agenda Fácil — agenda online para clínicas, salões e consultórios"
            width="1200"
            height="800"
            class="w-full rounded-2xl border border-border shadow-lg"
          />
        </div>
      </div>
    </section>

    <!-- ===== Problema ===== -->
    <section class="border-t border-border bg-surface px-4 py-8 lg:py-14">
      <div class="mx-auto max-w-3xl text-center">
        <h2 class="mb-4 font-display text-h1 text-text sm:text-[1.75rem]">
          Cansado de agendar tudo na mão?
        </h2>
        <p class="text-body text-text-muted">
          WhatsApp que não para, cliente que esquece o horário, caderno bagunçado e aquele
          jogo de "que dia fica bom pra você?" que se arrasta por dez mensagens.
          Enquanto isso, você perde tempo e perde atendimento.
        </p>
      </div>
    </section>

    <!-- ===== Como funciona ===== -->
    <section class="px-4 py-8 lg:py-14">
      <div class="mx-auto max-w-6xl">
        <div class="mb-7 text-center">
          <p class="eyebrow mb-2">Como funciona</p>
          <h2 class="font-display text-h1 text-text sm:text-[1.75rem]">Em minutos você está recebendo marcações</h2>
        </div>
        <ol class="grid gap-4 sm:grid-cols-3">
          <li v-for="p in passos" :key="p.n" class="rounded-xl border border-border bg-surface p-5 shadow-sm">
            <span class="mb-3 flex h-10 w-10 items-center justify-center rounded-pill bg-accent-soft font-display text-h3 font-bold text-accent">
              {{ p.n }}
            </span>
            <h3 class="mb-1 text-h3 font-semibold text-text">{{ p.titulo }}</h3>
            <p class="text-small text-text-muted">{{ p.texto }}</p>
          </li>
        </ol>
      </div>
    </section>

    <!-- ===== Recursos ===== -->
    <section class="border-t border-border bg-surface px-4 py-8 lg:py-14">
      <div class="mx-auto max-w-6xl">
        <div class="mb-7 text-center">
          <p class="eyebrow mb-2">Tudo o que você precisa</p>
          <h2 class="font-display text-h1 text-text sm:text-[1.75rem]">Uma agenda que trabalha por você</h2>
        </div>
        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <div v-for="r in recursos" :key="r.titulo" class="rounded-xl border border-border bg-bg p-5">
            <span class="mb-3 flex h-11 w-11 items-center justify-center rounded-lg bg-accent-soft text-2xl" aria-hidden="true">
              {{ r.emoji }}
            </span>
            <h3 class="mb-1 text-h3 font-semibold text-text">{{ r.titulo }}</h3>
            <p class="text-small text-text-muted">{{ r.texto }}</p>
          </div>
        </div>
      </div>
    </section>

    <!-- ===== Para quem ===== -->
    <section class="px-4 py-8 lg:py-12">
      <div class="mx-auto max-w-4xl text-center">
        <p class="eyebrow mb-3">Feito para quem atende com hora marcada</p>
        <div class="flex flex-wrap justify-center gap-2">
          <span
            v-for="v in verticais"
            :key="v"
            class="rounded-pill border border-border bg-surface px-4 py-2 text-small font-medium text-text"
          >
            {{ v }}
          </span>
        </div>
      </div>
    </section>

    <!-- ===== Preço ===== -->
    <section class="border-t border-border bg-surface px-4 py-8 lg:py-14">
      <div class="mx-auto max-w-md">
        <div class="rounded-2xl border border-accent-border bg-bg p-6 text-center shadow-lg" style="border-color: var(--accent)">
          <p class="eyebrow mb-2">Plano único, sem pegadinha</p>
          <p class="font-display text-display-lg font-bold text-text">
            {{ PRECO }}<span class="text-body font-normal text-text-muted">/mês</span>
          </p>
          <p class="mt-1 text-small text-text-muted">Todos os recursos incluídos. Sem taxa por agendamento.</p>
          <ul class="mx-auto mt-5 grid max-w-xs gap-2 text-left text-small text-text">
            <li class="flex items-start gap-2"><span class="text-success" aria-hidden="true">✓</span> Agendamentos ilimitados</li>
            <li class="flex items-start gap-2"><span class="text-success" aria-hidden="true">✓</span> Vários profissionais e serviços</li>
            <li class="flex items-start gap-2"><span class="text-success" aria-hidden="true">✓</span> Seu link exclusivo e lembretes</li>
            <li class="flex items-start gap-2"><span class="text-success" aria-hidden="true">✓</span> Suporte quando precisar</li>
          </ul>
          <RouterLink
            :to="{ name: 'comecar' }"
            class="min-h-touch mt-6 inline-flex w-full items-center justify-center rounded-pill bg-accent px-7 text-body font-semibold text-on-accent shadow-glow transition-colors hover:bg-accent-hover"
            @click="trackLead('preco')"
          >
            Começar grátis
          </RouterLink>
          <p class="mt-3 text-caption text-text-muted">7 dias grátis · sem cartão · cancele quando quiser</p>
        </div>
      </div>
    </section>

    <!-- ===== FAQ ===== -->
    <section class="px-4 py-8 lg:py-14">
      <div class="mx-auto max-w-2xl">
        <h2 class="mb-6 text-center font-display text-h1 text-text sm:text-[1.75rem]">Perguntas frequentes</h2>
        <div class="flex flex-col gap-3">
          <div v-for="(f, i) in faqs" :key="i" class="rounded-xl border border-border bg-surface">
            <button
              type="button"
              class="flex min-h-touch w-full items-center justify-between gap-3 px-5 py-4 text-left"
              :aria-expanded="faqAberta === i"
              @click="toggleFaq(i)"
            >
              <span class="text-h3 font-semibold text-text">{{ f.q }}</span>
              <span class="text-text-muted transition-transform" :class="faqAberta === i ? 'rotate-45' : ''" aria-hidden="true">+</span>
            </button>
            <p v-if="faqAberta === i" class="px-5 pb-4 text-small text-text-muted">{{ f.a }}</p>
          </div>
        </div>
      </div>
    </section>

    <!-- ===== CTA final ===== -->
    <section class="relative overflow-hidden border-t border-border bg-surface px-4 py-10 lg:py-16">
      <div class="pointer-events-none absolute left-1/2 top-1/2 h-80 w-80 -translate-x-1/2 -translate-y-1/2 rounded-full bg-accent opacity-[0.10] blur-[120px]" aria-hidden="true" />
      <div class="relative mx-auto max-w-2xl text-center">
        <h2 class="mb-3 font-display text-h1 text-text sm:text-[1.75rem]">Comece a receber agendamentos hoje</h2>
        <p class="mb-6 text-body text-text-muted">Crie sua agenda em minutos e teste 7 dias grátis, sem cartão.</p>
        <RouterLink
          :to="{ name: 'comecar' }"
          class="min-h-touch inline-flex items-center justify-center rounded-pill bg-accent px-8 text-body font-semibold text-on-accent shadow-glow transition-colors hover:bg-accent-hover"
          @click="trackLead('cta_final')"
        >
          Criar minha agenda grátis
        </RouterLink>
      </div>
    </section>

    <!-- ===== Footer ===== -->
    <footer class="border-t border-border bg-bg px-4 py-6">
      <div class="mx-auto flex max-w-6xl flex-col items-center justify-between gap-3 text-caption text-text-muted sm:flex-row">
        <span class="font-display text-small font-bold text-text">Agenda Fácil</span>
        <div class="flex items-center gap-4">
          <RouterLink :to="{ name: 'login' }" class="hover:text-text">Entrar</RouterLink>
          <RouterLink :to="{ name: 'comecar' }" class="hover:text-text">Começar grátis</RouterLink>
        </div>
        <span>© {{ new Date().getFullYear() }} Agenda Fácil</span>
      </div>
    </footer>
  </div>
</template>
