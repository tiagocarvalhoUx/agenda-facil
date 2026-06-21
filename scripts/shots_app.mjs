import puppeteer from 'puppeteer'
import { mkdirSync } from 'node:fs'

const BASE = 'http://localhost:5174'
const SR =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU'
const OUT = 'screenshots'
mkdirSync(OUT, { recursive: true })
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

// 1) Gera magic link (admin) e extrai os tokens chamando o verify diretamente.
const linkRes = await fetch('http://127.0.0.1:54321/auth/v1/admin/generate_link', {
  method: 'POST',
  headers: { apikey: SR, Authorization: `Bearer ${SR}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ type: 'magiclink', email: 'dono@studio.com' }),
})
const link = await linkRes.json()
const verifyUrl = link.action_link

// Seguimos o verify SEM redirecionar para capturar os tokens do header Location.
const verify = await fetch(verifyUrl, { redirect: 'manual' })
const loc = verify.headers.get('location') || ''
const hash = loc.includes('#') ? loc.slice(loc.indexOf('#')) : ''
if (!hash.includes('access_token')) {
  console.error('Não consegui obter tokens. Location:', loc)
  process.exit(1)
}

const browser = await puppeteer.launch({ headless: 'new', args: ['--no-sandbox'] })
const page = await browser.newPage()
await page.setViewport({ width: 1366, height: 900, deviceScaleFactor: 2 })

// 2) Entrega o hash com tokens ao app (detectSessionInUrl estabelece a sessão).
await page.goto(`${BASE}/app/agenda${hash}`, { waitUntil: 'networkidle0' })
await sleep(1500)
await page.screenshot({ path: `${OUT}/06-app-agenda.png` })

const tour = [
  ['servicos', '07-app-servicos'],
  ['clientes', '08-app-clientes'],
  ['profissionais', '09-app-profissionais'],
  ['configuracoes', '10-app-config'],
]
for (const [route, name] of tour) {
  await page.goto(`${BASE}/app/${route}`, { waitUntil: 'networkidle0' })
  await sleep(900)
  await page.screenshot({ path: `${OUT}/${name}.png` })
}

// Agenda mobile (visão do profissional / bottom bar)
await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2 })
await page.goto(`${BASE}/app/agenda`, { waitUntil: 'networkidle0' })
await sleep(1000)
await page.screenshot({ path: `${OUT}/11-app-agenda-mobile.png` })

await browser.close()
console.log('OK — telas do painel em', OUT)
