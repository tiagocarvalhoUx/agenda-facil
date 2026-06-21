import puppeteer from 'puppeteer'
import { mkdirSync } from 'node:fs'

const BASE = 'http://localhost:5174'
const OUT = 'screenshots'
mkdirSync(OUT, { recursive: true })

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

async function clickText(page, text) {
  const handle = await page.evaluateHandle((t) => {
    const els = [...document.querySelectorAll('button, a')]
    return els.find((e) => e.textContent.trim().includes(t)) || null
  }, text)
  const el = handle.asElement()
  if (!el) throw new Error(`não achei elemento: ${text}`)
  await el.click()
}

const browser = await puppeteer.launch({ headless: 'new', args: ['--no-sandbox'] })
const page = await browser.newPage()

// ---- Público (mobile) ----
await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2 })
await page.goto(`${BASE}/studio-bem-estar`, { waitUntil: 'networkidle0' })
await sleep(600)
await page.screenshot({ path: `${OUT}/01-publico-servico.png` })

await clickText(page, 'Corte de cabelo')
await sleep(500)
await page.screenshot({ path: `${OUT}/02-publico-profissional.png` })

await clickText(page, 'Qualquer profissional')
await sleep(900)
// hoje pode ser fim de semana (sem expediente) — avança até aparecer slot
for (let i = 0; i < 4; i++) {
  const hasSlot = await page.$('[role="radio"]')
  if (hasSlot) break
  const next = await page.$('[aria-label="Próximo dia"]')
  if (next) await next.click()
  await sleep(900)
}
await page.screenshot({ path: `${OUT}/03-publico-horario.png` })

// seleciona primeiro slot e continua
const slot = await page.$('[role="radio"]')
if (slot) {
  await slot.click()
  await sleep(300)
  await clickText(page, 'Continuar')
  await sleep(500)
  await page.screenshot({ path: `${OUT}/04-publico-dados.png` })
}

// ---- Login (desktop) ----
await page.setViewport({ width: 1280, height: 800, deviceScaleFactor: 2 })
await page.goto(`${BASE}/login`, { waitUntil: 'networkidle0' })
await sleep(400)
await page.screenshot({ path: `${OUT}/05-login.png` })

await browser.close()
console.log('OK — screenshots em', OUT)
