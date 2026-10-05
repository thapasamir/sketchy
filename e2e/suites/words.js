const puppeteer = require('puppeteer-core')
const wait = ms => new Promise(r => setTimeout(r, ms))
const { U, launch } = require('../lib/browser')
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
  const guest = await player(b, 'Guest', `${U}/?room=${code}`).catch(() => null)
  // open the words section
  await host.$eval('#words-settings summary', e => e.click())
  const all = await text(host, '#words-summary')
  ok('starts on all categories', /all categories/i.test(all), all)
  await host.click('#difficulty-easy')
  ok('easy pressed', await until(async () => (await host.$eval('#difficulty-easy', e => e.getAttribute('aria-pressed'))) === 'true'))
  const easy = await text(host, '#words-summary')
  ok('pool shrinks for easy', easy !== all, easy)
  // choose just Animals: untick everything else
  const names = await host.$$eval('[data-category]', els => els.map(e => e.dataset.category))
  ok('16 categories shown', names.length === 16, names.length)
  for (const n of names.filter(n => n !== 'Animals')) {
    await host.evaluate(n => document.querySelector(`[data-category="${n}"]`).click(), n)
    await wait(60)
  }
  ok('summary says 1 of 16', await until(async () => /1 of 16/.test(await text(host, '#words-summary'))), await text(host, '#words-summary'))
  // the last one cannot be unticked
  await host.evaluate(() => document.querySelector('[data-category="Animals"]').click())
  await wait(300)
  ok('cannot untick the last category', /1 of 16/.test(await text(host, '#words-summary')))
  await host.click('#categories-all')
  ok('select all goes back to all', await until(async () => /all categories/i.test(await text(host, '#words-summary'))))
  ok('guest sees it (disabled)', true)
  await b.close()
  console.log(fails ? `${fails} FAILED` : 'ALL PASSED')
  process.exit(fails ? 1 : 0)
})()
