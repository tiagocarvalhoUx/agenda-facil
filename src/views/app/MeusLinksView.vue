<script setup lang="ts">
import { ref, reactive, computed, watch, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { useToast } from '@/composables/useToast'
import {
  THEMES,
  LINK_TYPES,
  USERNAME_RE,
  sanitizeUsername,
  newLink,
  normalizeLink,
  type BioPage,
  type BioLink,
  type LinkType,
  type BioTheme,
} from '@/lib/biolinks'
import PageHeader from '@/components/app/PageHeader.vue'
import BaseButton from '@/components/ui/BaseButton.vue'
import BaseInput from '@/components/ui/BaseInput.vue'
import BioPreview from '@/components/bio/BioPreview.vue'
import {
  Copy,
  ExternalLink,
  Save,
  Upload,
  Plus,
  Trash2,
  ChevronUp,
  ChevronDown,
  Check,
  Loader2,
} from '@lucide/vue'

// Editor da página de link-in-bio (§Meus Links). Uma página por tenant
// (bio_pages, unique tenant_id). Imagens no bucket 'bio'. A página pública é
// servida por RPC em /bio/:username.
const auth = useAuthStore()
const toast = useToast()

const MAX_LINKS = 5
const BIO_MAX = 80

const page = reactive<BioPage>({
  username: '',
  display_name: '',
  bio: '',
  theme: 'creme',
  avatar_url: null,
  links: [],
})

const loading = ref(true)
const saving = ref(false)
const usernameOriginal = ref('')

const origin = typeof window !== 'undefined' ? window.location.origin : ''
const publicUrl = computed(() => `${origin}/bio/${page.username || ''}`)

// ---------- Carregar / semear ----------
onMounted(async () => {
  if (!auth.tenant) return
  const { data, error } = await supabase
    .from('bio_pages')
    .select('username, display_name, bio, theme, avatar_url, links')
    .eq('tenant_id', auth.tenant.id)
    .maybeSingle()

  if (!error && data) {
    Object.assign(page, {
      username: data.username,
      display_name: data.display_name,
      bio: data.bio,
      theme: data.theme as BioTheme,
      avatar_url: data.avatar_url,
      links: ((data.links as BioLink[]) ?? []).map(normalizeLink),
    })
    usernameOriginal.value = data.username
  } else {
    // Página nova: pré-preenche com dados do estabelecimento e alguns links úteis.
    page.username = sanitizeUsername(auth.tenant.slug ?? '')
    page.display_name = auth.tenant.nome ?? ''
    page.bio = ''
    page.theme = 'creme'
    page.links = [
      newLink('whatsapp'),
      newLink('instagram'),
      { ...newLink('custom'), label: 'Agendar horário', url: `${origin}/${auth.tenant.slug ?? ''}` },
    ]
  }
  loading.value = false
})

// ---------- Username: sanitização + disponibilidade ----------
const usernameStatus = ref<'idle' | 'checking' | 'ok' | 'taken' | 'invalid'>('idle')
let checkTimer: number | undefined

watch(
  () => page.username,
  (v) => {
    const clean = sanitizeUsername(v)
    if (clean !== v) {
      page.username = clean
      return
    }
    if (clean === usernameOriginal.value) {
      usernameStatus.value = 'idle'
      return
    }
    if (!USERNAME_RE.test(clean)) {
      usernameStatus.value = 'invalid'
      return
    }
    usernameStatus.value = 'checking'
    window.clearTimeout(checkTimer)
    checkTimer = window.setTimeout(async () => {
      const { data, error } = await supabase.rpc('bio_username_available', {
        p_username: clean,
        p_tenant: auth.tenant!.id,
      })
      if (error) {
        usernameStatus.value = 'idle'
        return
      }
      usernameStatus.value = data ? 'ok' : 'taken'
    }, 450)
  },
)

// ---------- Links ----------
function addLink() {
  if (page.links.length >= MAX_LINKS) return
  page.links.push(newLink('custom'))
}
function removeLink(i: number) {
  page.links.splice(i, 1)
}
function move(i: number, dir: -1 | 1) {
  const j = i + dir
  if (j < 0 || j >= page.links.length) return
  const [item] = page.links.splice(i, 1)
  page.links.splice(j, 0, item)
}
function onTypeChange(l: BioLink, type: LinkType) {
  // Limpa os campos não usados pelo novo tipo, preservando id.
  l.type = type
  if (type !== 'custom') l.label = ''
  if (!['custom', 'location', 'banner'].includes(type)) l.url = ''
  if (type !== 'whatsapp') l.phone = ''
  if (type !== 'instagram') l.username = ''
  if (type !== 'banner') l.image_url = ''
}

// ---------- Upload de imagens (bucket 'bio') ----------
const uploadingAvatar = ref(false)
const uploadingBanner = ref<string | null>(null)

async function uploadTo(file: File, kind: 'avatar' | 'banner'): Promise<string | null> {
  const okTypes = ['image/jpeg', 'image/png', 'image/webp']
  if (!okTypes.includes(file.type)) {
    toast.error('Envie uma imagem JPG, PNG ou WebP.')
    return null
  }
  if (file.size > 5 * 1024 * 1024) {
    toast.error('A imagem deve ter no máximo 5MB.')
    return null
  }
  const ext = file.name.split('.').pop()?.toLowerCase() || 'jpg'
  const path = `${auth.tenant!.id}/${kind}-${Date.now()}.${ext}`
  const { error } = await supabase.storage.from('bio').upload(path, file, { cacheControl: '3600', upsert: true })
  if (error) {
    toast.error('Falha no upload da imagem.')
    return null
  }
  return supabase.storage.from('bio').getPublicUrl(path).data.publicUrl
}

async function onAvatarChange(e: Event) {
  const file = (e.target as HTMLInputElement).files?.[0]
  if (!file) return
  uploadingAvatar.value = true
  const url = await uploadTo(file, 'avatar')
  if (url) page.avatar_url = url
  uploadingAvatar.value = false
}

async function onBannerChange(e: Event, l: BioLink) {
  const file = (e.target as HTMLInputElement).files?.[0]
  if (!file) return
  uploadingBanner.value = l.id
  const url = await uploadTo(file, 'banner')
  if (url) l.image_url = url
  uploadingBanner.value = null
}

// ---------- Salvar ----------
async function salvar() {
  if (!USERNAME_RE.test(page.username)) {
    toast.error('Escolha um username válido (letras, números, ponto, hífen).')
    return
  }
  if (usernameStatus.value === 'taken') {
    toast.error('Este username já está em uso.')
    return
  }
  if (page.bio.length > BIO_MAX) {
    toast.error(`A bio deve ter até ${BIO_MAX} caracteres.`)
    return
  }
  saving.value = true
  const { error } = await supabase.from('bio_pages').upsert(
    {
      tenant_id: auth.tenant!.id,
      username: page.username,
      display_name: page.display_name.trim(),
      bio: page.bio.trim(),
      theme: page.theme,
      avatar_url: page.avatar_url,
      links: page.links,
    },
    { onConflict: 'tenant_id' },
  )
  saving.value = false
  if (error) {
    if (error.code === '23505') toast.error('Este username já está em uso.')
    else toast.error('Não foi possível salvar as alterações.')
    return
  }
  usernameOriginal.value = page.username
  usernameStatus.value = 'idle'
  toast.success('Alterações salvas.')
}

async function copiarLink() {
  try {
    await navigator.clipboard.writeText(publicUrl.value)
    toast.success('Link copiado.')
  } catch {
    toast.error('Não foi possível copiar.')
  }
}
function verPagina() {
  window.open(publicUrl.value, '_blank', 'noopener')
}

const bioCount = computed(() => page.bio.length)
</script>

<template>
  <div class="mx-auto max-w-6xl p-4 sm:p-5">
    <PageHeader eyebrow="Links" title="Meus Links" subtitle="Crie sua página de link-in-bio profissional">
      <template #actions>
        <div class="flex flex-wrap items-center gap-2">
          <BaseButton variant="secondary" @click="copiarLink"><Copy class="h-4 w-4" :stroke-width="2" /> Copiar link</BaseButton>
          <BaseButton variant="secondary" @click="verPagina"><ExternalLink class="h-4 w-4" :stroke-width="2" /> Ver página</BaseButton>
          <BaseButton :loading="saving" @click="salvar"><Save class="h-4 w-4" :stroke-width="2" /> Salvar alterações</BaseButton>
        </div>
      </template>
    </PageHeader>

    <!-- URL pública -->
    <div class="mb-5 flex items-center gap-2 rounded-2xl border border-accent-border bg-accent-soft p-3 text-small">
      <ExternalLink class="h-4 w-4 shrink-0 text-accent" :stroke-width="2" />
      <span class="text-text-muted">Sua página pública:</span>
      <a :href="publicUrl" target="_blank" rel="noopener" class="truncate font-semibold text-accent underline underline-offset-2">{{ publicUrl }}</a>
    </div>

    <div v-if="loading" class="text-small text-text-muted">Carregando…</div>

    <div v-else class="grid gap-5 lg:grid-cols-[1fr_360px]">
      <!-- ===================== Coluna do editor ===================== -->
      <div class="flex flex-col gap-5">
        <!-- PERFIL -->
        <section class="rounded-2xl border border-border bg-surface p-5 shadow-card">
          <h2 class="eyebrow mb-4">Perfil</h2>
          <div class="flex items-center gap-4">
            <div class="flex h-20 w-20 shrink-0 items-center justify-center overflow-hidden rounded-full bg-surface-2 text-2xl font-semibold text-text-muted">
              <img v-if="page.avatar_url" :src="page.avatar_url" alt="Avatar" class="h-full w-full object-cover" />
              <span v-else>{{ (page.display_name || '?').charAt(0).toUpperCase() }}</span>
            </div>
            <div>
              <label class="inline-flex cursor-pointer items-center gap-2 rounded-lg border border-border bg-surface px-3 py-2 text-small font-medium text-text transition-colors hover:bg-surface-2">
                <component :is="uploadingAvatar ? Loader2 : Upload" class="h-4 w-4" :class="uploadingAvatar ? 'animate-spin' : ''" :stroke-width="2" />
                Trocar foto
                <input type="file" accept="image/jpeg,image/png,image/webp" class="hidden" @change="onAvatarChange" />
              </label>
              <p class="mt-1 text-caption text-text-muted">JPG, PNG ou WebP — máx 5MB</p>
            </div>
          </div>

          <div class="mt-4 flex flex-col gap-4">
            <div class="flex flex-col gap-1">
              <label class="text-small font-medium text-text">Username (URL pública)</label>
              <div class="flex items-center overflow-hidden rounded-lg border border-border bg-surface-2 focus-within:border-accent">
                <span class="whitespace-nowrap py-2 pl-3 text-small text-text-muted">{{ origin.replace(/^https?:\/\//, '') }}/bio/</span>
                <input
                  v-model="page.username"
                  class="min-w-0 flex-1 bg-transparent py-2 pr-3 text-small font-medium text-text outline-none"
                  spellcheck="false"
                  autocapitalize="off"
                />
                <span class="pr-3">
                  <Check v-if="usernameStatus === 'ok'" class="h-4 w-4 text-success" :stroke-width="2.5" />
                  <Loader2 v-else-if="usernameStatus === 'checking'" class="h-4 w-4 animate-spin text-text-muted" :stroke-width="2" />
                </span>
              </div>
              <p v-if="usernameStatus === 'taken'" class="text-caption text-danger">Este username já está em uso.</p>
              <p v-else-if="usernameStatus === 'invalid'" class="text-caption text-danger">Use 2 a 39 caracteres: letras, números, ponto ou hífen.</p>
              <p v-else-if="usernameStatus === 'ok'" class="text-caption text-success">Disponível!</p>
            </div>

            <BaseInput v-model="page.display_name" label="Nome de exibição" placeholder="@suamarca" maxlength="40" />

            <div class="flex flex-col gap-1">
              <div class="flex items-center justify-between">
                <label class="text-small font-medium text-text">Bio</label>
                <span class="text-caption tabular" :class="bioCount > BIO_MAX ? 'text-danger' : 'text-text-muted'">{{ bioCount }}/{{ BIO_MAX }}</span>
              </div>
              <textarea
                v-model="page.bio"
                rows="2"
                :maxlength="BIO_MAX"
                class="w-full resize-y rounded-lg border border-border bg-surface-2 p-3 text-small text-text outline-none focus:border-accent"
                placeholder="Beleza e estética · Agende seu horário"
              />
            </div>
          </div>
        </section>

        <!-- TEMA -->
        <section class="rounded-2xl border border-border bg-surface p-5 shadow-card">
          <h2 class="eyebrow mb-4">Tema de cores</h2>
          <div class="flex flex-wrap gap-3">
            <button
              v-for="th in THEMES"
              :key="th.id"
              class="flex flex-col items-center gap-1.5"
              @click="page.theme = th.id"
            >
              <span
                class="flex h-14 w-14 items-center justify-center overflow-hidden rounded-xl border-2 transition-all"
                :class="page.theme === th.id ? 'border-accent ring-2 ring-accent-border' : 'border-border'"
              >
                <span class="flex h-full w-full">
                  <span class="flex-1" :style="{ backgroundColor: th.swatches[0] }" />
                  <span class="flex-1" :style="{ backgroundColor: th.swatches[1] }" />
                  <span class="flex-1" :style="{ backgroundColor: th.swatches[2] }" />
                </span>
              </span>
              <span class="text-caption" :class="page.theme === th.id ? 'font-semibold text-accent' : 'text-text-muted'">{{ th.label }}</span>
            </button>
          </div>
        </section>

        <!-- LINKS -->
        <section class="rounded-2xl border border-border bg-surface p-5 shadow-card">
          <div class="mb-4 flex items-center justify-between">
            <h2 class="eyebrow">Links ({{ page.links.length }}/{{ MAX_LINKS }})</h2>
            <BaseButton variant="secondary" :disabled="page.links.length >= MAX_LINKS" @click="addLink">
              <Plus class="h-4 w-4" :stroke-width="2" /> Adicionar
            </BaseButton>
          </div>

          <p v-if="page.links.length === 0" class="text-small text-text-muted">Nenhum link ainda. Clique em “Adicionar”.</p>

          <div class="flex flex-col gap-3">
            <div v-for="(l, i) in page.links" :key="l.id" class="rounded-xl border border-border bg-surface-2 p-3">
              <div class="flex items-center gap-2">
                <select
                  :value="l.type"
                  class="min-w-0 flex-1 rounded-lg border border-border bg-surface px-2 py-2 text-small text-text outline-none focus:border-accent"
                  @change="onTypeChange(l, ($event.target as HTMLSelectElement).value as LinkType)"
                >
                  <option v-for="opt in LINK_TYPES" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
                </select>
                <button class="rounded-lg p-2 text-text-muted transition-colors hover:bg-surface hover:text-text disabled:opacity-30" :disabled="i === 0" @click="move(i, -1)"><ChevronUp class="h-4 w-4" :stroke-width="2" /></button>
                <button class="rounded-lg p-2 text-text-muted transition-colors hover:bg-surface hover:text-text disabled:opacity-30" :disabled="i === page.links.length - 1" @click="move(i, 1)"><ChevronDown class="h-4 w-4" :stroke-width="2" /></button>
                <button class="rounded-lg p-2 text-danger transition-colors hover:bg-danger/10" @click="removeLink(i)"><Trash2 class="h-4 w-4" :stroke-width="2" /></button>
              </div>

              <!-- Campos por tipo -->
              <div class="mt-3">
                <template v-if="l.type === 'whatsapp'">
                  <BaseInput v-model="l.phone" label="Número de telefone" inputmode="numeric" placeholder="Ex.: 11987654321" />
                </template>

                <template v-else-if="l.type === 'instagram'">
                  <label class="text-small font-medium text-text">Username</label>
                  <div class="mt-1 flex items-center overflow-hidden rounded-lg border border-border bg-surface focus-within:border-accent">
                    <span class="whitespace-nowrap py-2 pl-3 text-small text-text-muted">https://www.instagram.com/</span>
                    <input v-model="l.username" class="min-w-0 flex-1 bg-transparent py-2 pr-3 text-small text-text outline-none" placeholder="seu_perfil" spellcheck="false" autocapitalize="off" />
                  </div>
                </template>

                <template v-else-if="l.type === 'custom'">
                  <BaseInput v-model="l.label" label="Texto do botão" placeholder="Agendar horário" />
                  <div class="mt-3"><BaseInput v-model="l.url" label="URL" placeholder="https://..." /></div>
                </template>

                <template v-else-if="l.type === 'location'">
                  <BaseInput v-model="l.url" label="Link do Google Maps" placeholder="https://maps.google.com/..." />
                </template>

                <template v-else-if="l.type === 'banner'">
                  <BaseInput v-model="l.url" label="URL de destino (ao clicar)" placeholder="https://..." />
                  <div class="mt-3">
                    <label class="text-small font-medium text-text">Imagem do banner</label>
                    <label class="mt-1 flex cursor-pointer flex-col items-center justify-center gap-1 rounded-lg border border-dashed border-border bg-surface py-6 text-center transition-colors hover:border-accent">
                      <img v-if="l.image_url" :src="l.image_url" alt="Banner" class="max-h-28 rounded-md object-contain" />
                      <template v-else>
                        <component :is="uploadingBanner === l.id ? Loader2 : Upload" class="h-5 w-5 text-text-muted" :class="uploadingBanner === l.id ? 'animate-spin' : ''" :stroke-width="2" />
                        <span class="text-small text-text-muted">Enviar imagem do banner</span>
                        <span class="text-caption text-text-muted">JPG, PNG, WebP — máx 5MB</span>
                      </template>
                      <input type="file" accept="image/jpeg,image/png,image/webp" class="hidden" @change="onBannerChange($event, l)" />
                    </label>
                  </div>
                </template>
              </div>
            </div>
          </div>
        </section>
      </div>

      <!-- ===================== Preview ===================== -->
      <div class="lg:sticky lg:top-5 lg:self-start">
        <p class="eyebrow mb-3 text-center">Preview em tempo real</p>
        <div class="mx-auto w-full max-w-[300px] overflow-hidden rounded-[2.2rem] border-[6px] border-ink bg-ink shadow-card">
          <div class="max-h-[560px] overflow-y-auto rounded-[1.7rem]">
            <BioPreview :page="page" />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
