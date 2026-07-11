import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'
import { initTheme } from '@/composables/useTheme'
import './style.css'

// Tema do painel (dark/claro) antes do mount — sem flash do tema errado.
initTheme()

const app = createApp(App)
app.use(createPinia())
app.use(router)
app.mount('#app')

// Service Worker do PWA: habilita Web Push (notificação de novo agendamento
// mesmo com o app fechado). Registro silencioso — se falhar, o app segue normal.
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch(() => {
      /* sem SW o painel funciona; só não recebe push offline */
    })
  })
}
