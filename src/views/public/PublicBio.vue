<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '@/lib/supabase'
import { themeOf, normalizeLink, type BioPage, type BioLink } from '@/lib/biolinks'
import BioPreview from '@/components/bio/BioPreview.vue'

// Página pública de link-in-bio (/bio/:username). Dados só via RPC pública
// get_public_bio — nenhum acesso direto a tabela. SSR-friendly o suficiente
// para um SPA: carrega no mount e reage à troca de username.
const route = useRoute()
const page = ref<BioPage | null>(null)
const loading = ref(true)

const bg = computed(() => (page.value ? themeOf(page.value.theme).page : '#0f1115'))

async function load() {
  loading.value = true
  page.value = null
  const username = String(route.params.username || '')
  const { data, error } = await supabase.rpc('get_public_bio', { p_username: username })
  if (!error && data) {
    const raw = data as {
      username: string
      display_name: string
      bio: string
      theme: string
      avatar_url: string | null
      links: BioLink[]
    }
    page.value = {
      username: raw.username,
      display_name: raw.display_name,
      bio: raw.bio,
      theme: raw.theme as BioPage['theme'],
      avatar_url: raw.avatar_url,
      links: (raw.links ?? []).map(normalizeLink),
    }
    document.title = `${raw.display_name || raw.username} · Links`
  }
  loading.value = false
}

onMounted(load)
watch(() => route.params.username, load)
</script>

<template>
  <div class="min-h-screen w-full" :style="{ backgroundColor: bg }">
    <div class="mx-auto flex min-h-screen max-w-md flex-col">
      <div v-if="loading" class="flex flex-1 items-center justify-center text-sm text-white/70">Carregando…</div>

      <BioPreview v-else-if="page" :page="page" interactive class="flex-1" />

      <div v-else class="flex flex-1 flex-col items-center justify-center gap-2 px-6 text-center text-white">
        <p class="text-2xl font-bold">Página não encontrada</p>
        <p class="text-sm text-white/70">Este endereço de links não existe ou não está publicado.</p>
      </div>

      <footer v-if="page" class="px-5 py-6 text-center">
        <a href="/" class="text-xs opacity-60 hover:opacity-100" :style="{ color: themeOf(page.theme).subtext }">
          Criado com Agenda Fácil
        </a>
      </footer>
    </div>
  </div>
</template>
