import { ref } from 'vue'

// Tema do painel interno: dark (padrão, .theme-admin) ou claro (classe
// theme-light no <html>, que re-sobrescreve os tokens — ver style.css).
// Persistido por dispositivo em localStorage; o público continua sempre claro.
export type PanelTheme = 'dark' | 'light'

const KEY = 'panel_theme'
const theme = ref<PanelTheme>('dark')

function apply(t: PanelTheme) {
  theme.value = t
  document.documentElement.classList.toggle('theme-light', t === 'light')
}

// Chamado uma vez no boot (main.ts), antes do mount — evita piscar o tema errado.
export function initTheme() {
  apply(localStorage.getItem(KEY) === 'light' ? 'light' : 'dark')
}

export function useTheme() {
  function toggle() {
    const t: PanelTheme = theme.value === 'dark' ? 'light' : 'dark'
    localStorage.setItem(KEY, t)
    apply(t)
  }
  return { theme, toggle }
}
