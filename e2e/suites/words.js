// The host choosing which words come up, in the settings dialog; and what a guest sees of it.
const wait = ms => new Promise(r => setTimeout(r, ms))
const { U, launch } = require('../lib/browser')
const { openSettings, closeSettings } = require('../lib/lobby')
const click = (p, t) => p.evaluate(t => { const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === t); if (!b) throw new Error('no button "' + t + '"'); b.click() }, t)
const text = (p, sel) => p.$eval(sel, e => e.textContent.trim().replace(/\s+/g, ' ')).catch(() => null)
let fails = 0
const ok = (n, c, x = '') => { if (!c) fails++; console.log(c ? 'PASS' : 'FAIL', n, x) }
async function until(fn, ms = 6000) { const t = Date.now(); while (Date.now() - t < ms) { try { if (await fn()) return true } catch {} await wait(100) } return false }

async function player(b, name, url = U + '/') {
  const ctx = await b.createBrowserContext(); const p = await ctx.newPage(); await p.setViewport({ width: 1200, height: 950 })
  p.errs = []; p.on('pageerror', e => p.errs.push(e.message))
  await p.evaluateOnNewDocument(() => localStorage.setItem('sketchy:seen-how-to-play', 'true'))
  await p.goto(url, { waitUntil: 'networkidle0' })
  await click(p, 'Play as Guest'); await p.waitForSelector('#name'); await p.type('#name', name); await p.keyboard.press('Enter')
  await p.waitForSelector('#room-code'); return p
}

;(async () => {
  const b = await launch()
  const host = await player(b, 'Host')
  const code = await text(host, '#room-code')
  const guest = await player(b, 'Guest', `${U}/room/${code}`)

  console.log('--- the dialog')
  ok('the host has a button for the settings and a guest has none', !!(await host.$('#edit-settings')) && !(await guest.$('#edit-settings')))
  ok('the dialog is not open until asked for', !(await host.$('#settings-dialog')))
  await openSettings(host)
  ok('it opens as a dialog', await host.$eval('#settings-dialog', e => e.getAttribute('role') === 'dialog' && e.getAttribute('aria-modal') === 'true'))
  await host.keyboard.press('Escape')
  ok('Escape closes it', await until(async () => !(await host.$('#settings-dialog'))))
  await openSettings(host)

  console.log('--- how hard, and which categories')
  const pool = () => host.$eval('#words-pool', e => Number(e.dataset.pool))
  const all = await text(host, '#words-pool')
  const allPool = await pool()
  ok('starts on all categories', /all categories/i.test(all), all)
  ok('and no word count is shown', !/\d+ words/.test(await host.evaluate(() => document.body.innerText)))
  await host.click('#difficulty-easy')
  ok('easy pressed', await until(async () => (await host.$eval('#difficulty-easy', e => e.getAttribute('aria-pressed'))) === 'true'))
  ok('the pool of words shrinks for easy', await until(async () => (await pool()) < allPool), `${await pool()} of ${allPool}`)
  const names =await host.$$eval('[data-category]', els => els.map(e => e.dataset.category))
  ok('16 categories shown', names.length === 16, names.length)
  ok('"select all" is not offered while everything is chosen', !(await host.$('#categories-all')))

  // tapping one while everything is chosen means "just this one"
  await host.click('[data-category="Animals"]')
  ok('tapping one picks only that one', await until(async () => /1 of 16/.test(await text(host, '#words-pool'))), await text(host, '#words-pool'))
  ok('and it is the one that is marked', (await host.$eval('[data-category="Animals"]', e => e.getAttribute('aria-pressed'))) === 'true' && (await host.$eval('[data-category="Food"]', e => e.getAttribute('aria-pressed'))) === 'false')
  // after that, tapping adds
  await host.click('[data-category="Food"]')
  ok('tapping another adds it', await until(async () => /2 of 16/.test(await text(host, '#words-pool'))))

  console.log('--- what a guest sees')
  const guestSees = async () => guest.$$eval('[data-chosen-category]', els => els.map(e => e.dataset.chosenCategory).sort().join(','))
  ok('which categories were chosen', await until(async () => (await guestSees()) === 'Animals,Food'), await guestSees())
  ok('with no controls to change anything', !(await guest.$('[data-category]')) && !(await guest.$('#difficulty-easy')) && !(await guest.$('#rounds-3')) && !(await guest.$('#laps-1')))
  ok('and who decides', /Host/.test(await text(guest, '#host-decides')), await text(guest, '#host-decides'))
  ok('and how hard the words are', /Easy only/.test(await text(guest, '#words-value')), await text(guest, '#words-value'))
  ok('the host\'s own summary behind the dialog agrees', (await host.$$eval('[data-chosen-category]', els => els.length)) === 2)

  // removing one is fine; the last one cannot be removed
  await host.click('[data-category="Food"]')
  ok('tapping a chosen one removes it', await until(async () => /1 of 16/.test(await text(host, '#words-pool'))))
  await host.click('[data-category="Animals"]'); await wait(300)
  ok('the last category cannot be removed', /1 of 16/.test(await text(host, '#words-pool')))
  await host.click('#categories-all')
  ok('select all goes back to all', await until(async () => /all categories/i.test(await text(host, '#words-pool'))))
  ok('and the guest sees all categories again', await until(async () => /All categories/.test(await text(guest, '#words-summary'))))

  await closeSettings(host)
  ok('Done closes the dialog', !(await host.$('#settings-dialog')))
  ok('and no page errors', [host, guest].every(p => p.errs.length === 0), [host, guest].flatMap(p => p.errs).join('|'))
  await b.close()
  console.log(fails ? `${fails} FAILED` : 'ALL PASSED')
  process.exit(fails ? 1 : 0)
})()
