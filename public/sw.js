// Service Worker — recebe Web Push e exibe a notificação nativa do sistema.
// Roda fora da aba (inclusive com o app fechado). Mantido minimalista de
// propósito: só lida com push e com o clique na notificação.

self.addEventListener('install', () => {
  // Ativa imediatamente a nova versão sem esperar abas antigas fecharem.
  self.skipWaiting()
})

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim())
})

self.addEventListener('push', (event) => {
  let data = {}
  try {
    data = event.data ? event.data.json() : {}
  } catch (_e) {
    data = { title: 'Novo agendamento', body: event.data ? event.data.text() : '' }
  }

  const title = data.title || 'Novo agendamento'
  const options = {
    body: data.body || '',
    icon: '/favicon-180.png',
    badge: '/favicon-32.png',
    tag: 'novo-agendamento',
    renotify: true,
    data: { url: data.url || '/app/agenda' },
  }
  event.waitUntil(self.registration.showNotification(title, options))
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const url = (event.notification.data && event.notification.data.url) || '/app/agenda'
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      // Se já houver uma aba do app aberta, foca nela; senão, abre uma nova.
      for (const client of clientList) {
        if ('focus' in client) {
          client.navigate(url)
          return client.focus()
        }
      }
      return self.clients.openWindow(url)
    }),
  )
})
