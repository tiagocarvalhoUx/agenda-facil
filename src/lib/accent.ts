// Tema por tenant (ADENDO §13.1 + §18).
// Injeta UM --accent vindo do registro do tenant, com fallback por vertical.
// Valida contraste AA (≥ 4.5:1 sobre branco); se falhar, escurece o tom até
// passar — garantindo legibilidade do texto/CTA sem travar o white-label.

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

function channelLum(c: number): number {
  const s = c / 255
  return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4)
}

function luminance({ r, g, b }: RGB): number {
  return 0.2126 * channelLum(r) + 0.7152 * channelLum(g) + 0.0722 * channelLum(b)
}

// Razão de contraste vs branco (#fff).
function contrastOnWhite(rgb: RGB): number {
  const l = luminance(rgb)
  return (1.0 + 0.05) / (l + 0.05)
}

function darken(rgb: RGB, factor: number): RGB {
  return { r: rgb.r * factor, g: rgb.g * factor, b: rgb.b * factor }
}

// Retorna um tom do accent que atinge contraste >= 4.5:1 sobre branco.
function ensureAA(rgb: RGB): RGB {
  let out = rgb
  let factor = 0.92
  let guard = 0
  while (contrastOnWhite(out) < 4.5 && guard < 20) {
    out = darken(rgb, factor)
    factor -= 0.06
    guard++
  }
  return out
}

export function resolveAccent(color: string | null | undefined, vertical: Vertical): string {
  const base = (color && hexToRgb(color)) || hexToRgb(FALLBACK[vertical ?? 'outro'])!
  return rgbToHex(base)
}

// Aplica o accent ao :root. `--accent` mantém a cor da marca para fundos
// suaves; `--accent` usado em texto/CTA é o tom validado (escurecido se preciso).
export function applyAccent(color: string | null | undefined, vertical: Vertical): void {
  const baseHex = resolveAccent(color, vertical)
  const base = hexToRgb(baseHex)!
  const accessible = ensureAA(base)
  const hover = darken(accessible, 0.88)

  const root = document.documentElement.style
  root.setProperty('--accent', rgbToHex(accessible))
  root.setProperty('--accent-hover', rgbToHex(hover))
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

// Validação reutilizável na tela de Configurações (avisa o dono ao salvar a cor).
export function accentPassesAA(color: string): boolean {
  const rgb = hexToRgb(color)
  return rgb ? contrastOnWhite(rgb) >= 4.5 : false
}
