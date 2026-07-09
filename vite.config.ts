import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath, URL } from 'node:url'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [vue()],
  server: {
    // Escuta em IPv4 e IPv6 (host: true → 0.0.0.0 + [::]). Sem isto o Vite fica
    // só em [::1] no Windows e http://127.0.0.1 é recusado (ERR_CONNECTION_REFUSED).
    host: true,
    port: 5173,
    strictPort: true,
  },
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
})
