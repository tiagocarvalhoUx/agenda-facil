<script setup lang="ts">
import { computed } from 'vue'
import { themeOf, linkTitle, linkHref, linkIsReady, type BioPage } from '@/lib/biolinks'
import { MessageCircle, Camera, Link2, MapPin } from '@lucide/vue'

// Render do conteúdo da bio (avatar + nome + bio + botões de link), usando o
// tema como cores inline. Reaproveitado no preview do editor e na página
// pública. `interactive` liga os cliques (na página pública); no preview fica
// desligado para não navegar ao editar.
const props = withDefaults(defineProps<{ page: BioPage; interactive?: boolean }>(), {
  interactive: false,
})

const t = computed(() => themeOf(props.page.theme))
const inicial = computed(() => (props.page.display_name || '?').replace(/^@/, '').charAt(0).toUpperCase())
const links = computed(() => props.page.links.filter(linkIsReady))

const ICONS = { whatsapp: MessageCircle, instagram: Camera, custom: Link2, location: MapPin } as const
</script>

<template>
  <div class="flex w-full flex-col items-center px-5 py-8" :style="{ backgroundColor: t.page, color: t.text }">
    <!-- Avatar -->
    <div
      class="flex h-24 w-24 items-center justify-center overflow-hidden rounded-full text-3xl font-semibold"
      :style="{ backgroundColor: t.card, color: t.cardText }"
    >
      <img v-if="page.avatar_url" :src="page.avatar_url" alt="" class="h-full w-full object-cover" />
      <span v-else>{{ inicial }}</span>
    </div>

    <p class="mt-3 text-center text-lg font-bold" :style="{ color: t.text }">
      {{ page.display_name || '@suamarca' }}
    </p>
    <p v-if="page.bio" class="mt-1 max-w-[16rem] text-center text-sm" :style="{ color: t.subtext }">
      {{ page.bio }}
    </p>

    <!-- Links -->
    <div class="mt-5 flex w-full max-w-sm flex-col gap-3">
      <template v-for="l in links" :key="l.id">
        <!-- Banner (imagem) -->
        <component
          :is="interactive && l.url ? 'a' : 'div'"
          v-if="l.type === 'banner'"
          :href="interactive && l.url ? l.url : undefined"
          :target="interactive ? '_blank' : undefined"
          rel="noopener"
          class="block overflow-hidden rounded-xl"
        >
          <img :src="l.image_url" alt="" class="h-auto w-full object-cover" />
        </component>

        <!-- Botão de link -->
        <component
          :is="interactive ? 'a' : 'div'"
          v-else
          :href="interactive ? linkHref(l) : undefined"
          :target="interactive ? '_blank' : undefined"
          rel="noopener"
          class="flex items-center gap-3 rounded-xl px-4 py-3 text-sm font-medium transition-opacity"
          :class="interactive ? 'hover:opacity-90' : ''"
          :style="{ backgroundColor: t.card, color: t.cardText }"
        >
          <component :is="ICONS[l.type]" class="h-4 w-4 shrink-0" :stroke-width="2" :style="{ color: t.icon }" />
          <span class="truncate">{{ linkTitle(l) }}</span>
        </component>
      </template>
    </div>
  </div>
</template>
