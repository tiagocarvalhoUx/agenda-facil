// Tema por tenant (ADENDO §13.1 + §18).
// Injeta UM --accent vindo do registro do tenant, com fallback por vertical.
// White-label livre: a cor escolhida é aplicada exatamente como está, sem
// escurecimento automático — incluindo tons claros.

type Vertical = 'clinica' | 'salao' | 'outro' | null | undefined

const FALLBACK: Record<string, string> = {
  clinica: '#1E6FB8', // azul confiança
  salao: '#C84B6B', // rosa/coral
  outro: '#0E9F9A', // teal (default do sistema)
}

interface RGB {
  r: number
  g: number
  b: number
}

function hexToRgb(hex: string): RGB | null {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex.trim())
  if (!m) return null
  const n = parseInt(m[1], 16)
  return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 }
}

function rgbToHex({ r, g, b }: RGB): string {
  const h = (v: number) => Math.round(v).toString(16).padStart(2, '0')
  return `#${h(r)}${h(g)}${h(b)}`
}

function darken(rgb: RGB, factor: number): RGB {
  return { r: rgb.r * factor, g: rgb.g * factor, b: rgb.b * factor }
}

function channelLum(c: number): number {
  const s = c / 255
  return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4)
}

function luminance({ r, g, b }: RGB): number {
  return 0.2126 * channelLum(r) + 0.7152 * channelLum(g) + 0.0722 * channelLum(b)
}

// Cor do texto/ícone sobre o accent: escolhe entre branco e um quase-preto
// pelo que tiver maior contraste — mantém legibilidade mesmo com accent claro.
const INK = '#101418'
function foregroundOn(rgb: RGB): string {
  const l = luminance(rgb)
  const contrastWhite = (1.0 + 0.05) / (l + 0.05)
  const contrastInk = (l + 0.05) / (luminance(hexToRgb(INK)!) + 0.05)
  return contrastWhite >= contrastInk ? '#ffffff' : INK
}

export function resolveAccent(color: string | null | undefined, vertical: Vertical): string {
  const base = (color && hexToRgb(color)) || hexToRgb(FALLBACK[vertical ?? 'outro'])!
  return rgbToHex(base)
}

// Aplica o accent ao :root. A cor da marca é usada como está, sem
// escurecimento — white-label livre, inclusive em tons claros.
export function applyAccent(color: string | null | undefined, vertical: Vertical): void {
  const baseHex = resolveAccent(color, vertical)
  const base = hexToRgb(baseHex)!
  const hover = darken(base, 0.88)

  const root = document.documentElement.style
  root.setProperty('--accent', rgbToHex(base))
  root.setProperty('--accent-hover', rgbToHex(hover))
  // texto/ícone sobre o accent: branco ou escuro conforme a luminosidade
  const fg = foregroundOn(base)
  root.setProperty('--on-accent', fg)
  // borda sutil só quando o accent é claro (fg escuro) — destaca o contorno do
  // botão sobre fundos claros; transparente para accents escuros.
  root.setProperty('--accent-border', fg === INK ? 'rgba(0, 0, 0, 0.16)' : 'transparent')
  // fundo suave: mistura clara da marca (10% sobre branco)
  root.setProperty(
    '--accent-soft',
    rgbToHex({
      r: 255 - (255 - base.r) * 0.1,
      g: 255 - (255 - base.g) * 0.1,
      b: 255 - (255 - base.b) * 0.1,
    }),
  )
}
