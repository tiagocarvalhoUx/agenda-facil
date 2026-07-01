// Meus Links Públicos (link-in-bio): temas, tipos de link e helpers de render.
// As páginas de bio têm tema PRÓPRIO (independente do accent do painel); por
// isso as cores vêm daqui como hex e são aplicadas via style inline, tanto no
// preview do editor quanto na página pública.

export type BioTheme = 'creme' | 'marrom' | 'azul' | 'preto_ouro' | 'rosa'

export interface ThemePalette {
  id: BioTheme
  label: string
  page: string // fundo da página
  card: string // fundo do botão de link
  cardText: string // texto do botão
  text: string // nome de exibição / texto forte
  subtext: string // bio / texto secundário
  icon: string // cor do ícone no botão
  swatches: [string, string, string]
}

export const THEMES: ThemePalette[] = [
  { id: 'creme', label: 'Creme', page: '#F3ECE0', card: '#E5D9C6', cardText: '#4A3F35', text: '#3B322A', subtext: '#7A6E60', icon: '#6B5E50', swatches: ['#F3ECE0', '#C9B79C', '#4A3F35'] },
  { id: 'marrom', label: 'Marrom', page: '#EFE7DD', card: '#8B6B4E', cardText: '#FBF6EF', text: '#3A2A1C', subtext: '#7A6552', icon: '#FBF6EF', swatches: ['#4A3524', '#8B6B4E', '#D9C4AC'] },
  { id: 'azul', label: 'Azul', page: '#EAF1FB', card: '#D6E2F3', cardText: '#1E3A5F', text: '#16304F', subtext: '#55688A', icon: '#2C4A73', swatches: ['#DCE8F7', '#5A8FD6', '#1E3A5F'] },
  { id: 'preto_ouro', label: 'Preto & Ouro', page: '#121212', card: '#1F1F1F', cardText: '#E8C874', text: '#F5F0E6', subtext: '#B8AE97', icon: '#E8C874', swatches: ['#121212', '#3A3A3A', '#E8C874'] },
  { id: 'rosa', label: 'Rosa', page: '#FBEFF3', card: '#F3D9E2', cardText: '#7A2E4A', text: '#6A2340', subtext: '#A96C82', icon: '#B24A6C', swatches: ['#F7D9E4', '#E48BAE', '#8E2C50'] },
]

export function themeOf(id: string): ThemePalette {
  return THEMES.find((t) => t.id === id) ?? THEMES[0]
}

export type LinkType = 'whatsapp' | 'instagram' | 'custom' | 'location' | 'banner'

// Todos os campos editáveis são strings (default '') para casar com o v-model
// dos inputs e simplificar o type-check. Só os relevantes ao tipo são usados.
export interface BioLink {
  id: string
  type: LinkType
  label: string // texto do botão (custom)
  url: string // custom / location / banner (destino)
  phone: string // whatsapp
  username: string // instagram
  image_url: string // banner
}

export function newLink(type: LinkType = 'custom'): BioLink {
  return { id: randomId(), type, label: '', url: '', phone: '', username: '', image_url: '' }
}

// Normaliza um link vindo do banco (jsonb) garantindo todos os campos string.
export function normalizeLink(raw: Partial<BioLink> & { type: LinkType }): BioLink {
  return {
    id: raw.id ?? randomId(),
    type: raw.type,
    label: raw.label ?? '',
    url: raw.url ?? '',
    phone: raw.phone ?? '',
    username: raw.username ?? '',
    image_url: raw.image_url ?? '',
  }
}

export const LINK_TYPES: { value: LinkType; label: string }[] = [
  { value: 'whatsapp', label: 'WhatsApp' },
  { value: 'instagram', label: 'Instagram' },
  { value: 'custom', label: 'Personalizado' },
  { value: 'location', label: 'Localização' },
  { value: 'banner', label: 'Banner (imagem)' },
]

export interface BioPage {
  username: string
  display_name: string
  bio: string
  theme: BioTheme
  avatar_url: string | null
  links: BioLink[]
}

export const USERNAME_RE = /^[a-z0-9][a-z0-9._-]{1,38}$/

// Sanitiza o handle enquanto o dono digita: minúsculo, espaços viram '-',
// mantém só [a-z0-9._-] e limita a 39 chars.
export function sanitizeUsername(v: string): string {
  return (v || '')
    .toLowerCase()
    .replace(/\s+/g, '-')
    .replace(/[^a-z0-9._-]/g, '')
    .slice(0, 39)
}

export function randomId(): string {
  return Math.random().toString(36).slice(2, 10)
}

function onlyDigits(v: string): string {
  return (v || '').replace(/\D/g, '')
}

// Título exibido no botão do link.
export function linkTitle(l: BioLink): string {
  switch (l.type) {
    case 'whatsapp':
      return 'WhatsApp'
    case 'instagram':
      return 'Instagram'
    case 'location':
      return 'Localização'
    case 'custom':
      return l.label?.trim() || 'Link'
    case 'banner':
      return l.label?.trim() || 'Banner'
  }
}

// URL de destino do link na página pública.
export function linkHref(l: BioLink): string {
  switch (l.type) {
    case 'whatsapp': {
      let d = onlyDigits(l.phone || '')
      if (d.length === 10 || d.length === 11) d = '55' + d
      return d ? `https://wa.me/${d}` : '#'
    }
    case 'instagram': {
      const u = (l.username || '').trim().replace(/^@/, '')
      return u ? `https://instagram.com/${u}` : '#'
    }
    case 'location':
    case 'custom':
    case 'banner':
      return l.url?.trim() || '#'
  }
}

// Um link é "completo" (renderiza na página pública) quando tem o essencial.
export function linkIsReady(l: BioLink): boolean {
  switch (l.type) {
    case 'whatsapp':
      return onlyDigits(l.phone || '').length >= 10
    case 'instagram':
      return !!(l.username || '').trim()
    case 'location':
    case 'custom':
      return !!(l.url || '').trim()
    case 'banner':
      return !!(l.image_url || '').trim()
  }
}
