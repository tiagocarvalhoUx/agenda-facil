import puppeteer from 'puppeteer'
import { mkdirSync, readFileSync } from 'node:fs'
import { execSync } from 'node:child_process'

const BASE = process.env.BASE || 'http://localhost:5174'
const DB_CONTAINER = process.env.DB_CONTAINER || 'supabase_db_agenda-saas'
const OUT = 'screenshots'
mkdirSync(OUT, { recursive: true })
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const log = (...a) => console.log('•', ...a)

// Pré-requisito do teste do dono: owner + membership precisam existir. O
// seed.sql principal só cria dados públicos, então aplicamos o seed de owner
// (idempotente) antes de tudo. Roda via psql no container do Postgres local.
log('Aplicando seed de owner (dev_seed_owner.sql)…')
execSync(`docker exec -i ${DB_CONTAINER} psql -U postgres -d postgres -v ON_ERROR_STOP=1`, {
  input: readFileSync(new URL('./dev_seed_owner.sql', import.meta.url)),
  stdio: ['pipe', 'ignore', 'inherit'],
})

// telefone único por execução (evita rate-limit entre rodadas)
const phone = '11' + Math.floor(900000000 + Math.random() * 99999999)

async function clickText(page, text) {
  const h = await page.evaluateHandle((t) => {
    const els = [...document.querySelectorAll('button, a')]
    return els.find((e) => e.textContent.trim().includes(t)) || null
  }, text)
  const el = h.asElement()
  if (!el) throw new Error(`não achei: ${text}`)
  await el.click()
}

const browser = await puppeteer.launch({ headless: 'new', args: ['--no-sandbox'] })
const page = await browser.newPage()
await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2 })

// ====== CLIENTE FINAL AGENDA (fluxo público real) ======
log('Abrindo página pública…')
await page.goto(`${BASE}/studio-bem-estar`, { waitUntil: 'networkidle0' })
await sleep(500)

await clickText(page, 'Massagem relaxante')
await sleep(400)
await clickText(page, 'Qualquer profissional')
await sleep(900)

// avança até um dia com horários (hoje pode ser fim de semana) e conta quantos
// dias avançou, para reposicionar a agenda do dono no mesmo dia depois.
let daysAhead = 0
for (let i = 0; i < 8; i++) {
  if (await page.$('[role="radio"]')) break
  await (await page.$('[aria-label="Próximo dia"]')).click()
  daysAhead++
  await sleep(900)
}
const diaEscolhido = await page.$eval('h3, .capitalize', () => {
  const el = document.querySelector('.capitalize')
  return el ? el.textContent.trim() : ''
}).catch(() => '')

// seleciona o primeiro horário e lê o texto
const slotText = await page.$eval('[role="radio"]', (el) => el.textContent.trim())
await (await page.$('[role="radio"]')).click()
log(`Horário escolhido: ${slotText} (${diaEscolhido})`)
await sleep(300)
await clickText(page, 'Continuar')
await sleep(400)

// preenche dados + consentimento
await page.type('input[autocomplete="name"]', 'Joana Teste E2E')
await page.type('input[type="tel"]', phone)
await page.type('input[type="email"]', 'joana.e2e@exemplo.com')
await page.click('input[type="checkbox"]')
await sleep(200)
await page.screenshot({ path: `${OUT}/12-e2e-dados-preenchidos.png` })

log('Confirmando agendamento…')
await clickText(page, 'Confirmar agendamento')
await sleep(1500)
await page.screenshot({ path: `${OUT}/13-e2e-confirmacao.png` })
const confirmou = await page.evaluate(() => document.body.textContent.includes('confirmado'))
log('Tela de confirmação:', confirmou ? 'OK ✓' : 'NÃO apareceu ✗')

// ====== DONO VÊ O AGENDAMENTO NA AGENDA ======
const SR =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU'
const lr = await fetch('http://127.0.0.1:54321/auth/v1/admin/generate_link', {
  method: 'POST',
  headers: { apikey: SR, Authorization: `Bearer ${SR}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ type: 'magiclink', email: 'dono@studio.com' }),
})
const verifyUrl = (await lr.json()).action_link
const verify = await fetch(verifyUrl, { redirect: 'manual' })
const loc = verify.headers.get('location') || ''
const hash = loc.slice(loc.indexOf('#'))

await page.setViewport({ width: 1366, height: 900, deviceScaleFactor: 2 })
await page.goto(`${BASE}/app/agenda${hash}`, { waitUntil: 'networkidle0' })
await sleep(1500)

// Reposiciona a agenda no MESMO dia em que o cliente agendou: o navegador da
// agenda do dono também começa em "hoje", então basta avançar daysAhead dias.
// (busca de segurança: tenta alguns dias extras caso haja descasamento de fuso.)
const found = async () =>
  page.evaluate(() => document.body.textContent.includes('Joana Teste E2E'))
let apareceu = false
for (let i = 0; i < daysAhead + 3; i++) {
  if (await found()) { apareceu = true; break }
  await (await page.$('[aria-label="Próximo dia"]')).click()
  await sleep(700)
}
if (!apareceu) apareceu = await found()
await page.screenshot({ path: `${OUT}/14-e2e-agenda-dono.png` })
log('Agendamento do cliente visível na agenda do dono:', apareceu ? 'SIM ✓' : 'NÃO ✗')

await browser.close()
console.log('\nRESULTADO E2E:', confirmou && apareceu ? 'PASSOU ✅' : 'FALHOU ❌')
console.log('phone usado:', phone)
