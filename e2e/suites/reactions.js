const puppeteer = require('puppeteer-core')
const wait = ms => new Promise(r => setTimeout(r, ms))
const { U, launch } = require('../lib/browser')
const click = (p, t) => p.evaluate(t => { const b=[...document.querySelectorAll('button')].find(x => x.textContent.trim()===t); if(!b) throw new Error('no button "'+t+'"'); b.click() }, t)
const text = (p, sel) => p.$eval(sel, e => e.textContent.trim().replace(/\s+/g,' ')).catch(() => null)
let fails = 0
const ok = (n, c, x='') => { if(!c) fails++; console.log(c ? 'PASS' : 'FAIL', n, x) }
async function until(fn, ms=8000) { const t=Date.now(); while(Date.now()-t<ms){ try{ if(await fn()) return true }catch{} await wait(100) } return false }
async function player(b, name, url=U+'/', vp={ width: 1200, height: 950 }) {
  const ctx = await b.createBrowserContext(); const p = await ctx.newPage(); await p.setViewport(vp)
  p.errs = []; p.on('pageerror', e => p.errs.push(e.message))
  p.frames = []; const cdp = await p.createCDPSession(); await cdp.send('Network.enable')
  cdp.on('Network.webSocketFrameReceived', e => p.frames.push(e.response.payloadData))
  await p.evaluateOnNewDocument(() => localStorage.setItem('sketchy:seen-how-to-play', 'true'))
  await p.goto(url, { waitUntil: 'networkidle0' })
  await click(p, 'Play as Guest'); await p.waitForSelector('#name'); await p.type('#name', name); await p.keyboard.press('Enter')
  await p.waitForSelector('#room-code'); p.name = name; return p
}
const myTurn = p => p.$eval('#turn-banner', e => e.dataset.myTurn === 'true').catch(() => false)
const pixel = (p, nx, ny) => p.evaluate((nx, ny) => { const c = document.querySelector('#board'); const d = c.getContext('2d').getImageData(Math.round(nx*c.width), Math.round(ny*c.height), 1, 1).data; return [...d] }, nx, ny)
const inked = async (p, nx, ny) => (await pixel(p, nx, ny))[3] > 200
const rgb = c => c.match(/\d+/g).slice(0, 3).map(Number)
const close = (a, b, t=14) => b.every((v, i) => Math.abs(a[i] - v) <= t)
async function stroke(p, pts) {
  const r = await p.$eval('#board', e => { const b = e.getBoundingClientRect(); return { x: b.x, y: b.y, w: b.width, h: b.height } })
  const at = ([nx, ny]) => [r.x + nx * r.w, r.y + ny * r.h]
  await p.mouse.move(...at(pts[0])); await p.mouse.down()
  for (const pt of pts.slice(1)) await p.mouse.move(...at(pt), { steps: 12 })
  await p.mouse.up()
}

const allText = p => p.evaluate(() => document.body.innerText)
async function newGame(b) {
  const host = await player(b, 'Host'); const code = await text(host, '#room-code')
  const bob = await player(b, 'Bob', `${U}/room/${code}`); const cara = await player(b, 'Cara', `${U}/room/${code}`)
  const all = [host, bob, cara]
  await wait(700); await click(bob, "I'M READY"); await click(cara, "I'M READY")
  await until(() => host.$eval('#start-button', e => !e.disabled)); await click(host, 'START GAME')
  await until(async () => (await Promise.all(all.map(p => p.$('#board')))).every(Boolean), 10000)
  return all
}
const vote = (p, name) => p.click(`[data-vote="${name}"]`)
const floating = p => p.$$eval('[data-reaction]', els => els.map(e => e.textContent.trim().replace(/\s+/g, ' ')))

;(async () => {
  const b = await launch()
  const all = await newGame(b)
  await wait(500)
  const turns = await Promise.all(all.map(myTurn)); const di = turns.indexOf(true)
  const drawer = all[di]; const others = all.filter((_, i) => i !== di)
  ok('the drawer has no reaction bar', !(await drawer.$('#reaction-bar')))
  ok('watchers have one with 6 buttons', (await others[0].$$('#reaction-bar [data-react]')).length === 6)

  await others[0].click('[data-react="fire"]')
  ok('everyone sees it float, with the sender', await until(async () => (await Promise.all(all.map(floating))).every(l => l.some(t => t.includes('🔥') && t.includes(others[0].name)))), JSON.stringify(await floating(drawer)))
  ok('it does not block the drawing (pointer-events none)', await drawer.$eval('[data-reactions]', e => getComputedStyle(e).pointerEvents === 'none'))
  ok('and is hidden from screen readers', await drawer.$eval('[data-reactions]', e => e.getAttribute('aria-hidden') === 'true'))

  // quick taps are paced, not errors
  for (let i = 0; i < 5; i++) { await others[1].click('[data-react="laugh"]') }
  await wait(300)
  ok('a flurry of taps shows fewer than 5', (await floating(drawer)).filter(t => t.includes('😂')).length < 5)

  await wait(2800)
  ok('they fade away', (await floating(drawer)).length === 0, JSON.stringify(await floating(drawer)))

  // the vote: bar is there too
  ok('drawing over', await (async () => { for (let i = 0; i < 12; i++) { const t = await Promise.all(all.map(myTurn)); const x = t.indexOf(true); if (x < 0) { if (await until(async () => (await Promise.all(all.map(p => p.$('#vote-panel')))).every(Boolean), 800)) return true; continue } await click(all[x], "I'm done"); await wait(300) } return false })())
  await wait(300)
  ok('reaction bar in the vote', !!(await all[0].$('#reaction-bar')))
  await all[1].click('[data-react="sus"]')
  ok('shown to all in the vote', await until(async () => (await Promise.all(all.map(floating))).every(l => l.some(t => t.includes('🤨')))))
  ok('no page errors', all.every(p => p.errs.length === 0), all.flatMap(p => p.errs).join('|'))

  // reduced motion still shows it
  const rm = await b.createBrowserContext(); const page = await rm.newPage()
  await page.emulateMediaFeatures([{ name: 'prefers-reduced-motion', value: 'reduce' }])
  await page.evaluateOnNewDocument(() => localStorage.setItem('sketchy:seen-how-to-play', 'true'))
  await b.close()
  console.log(fails ? `${fails} FAILED` : 'ALL PASSED'); process.exit(fails ? 1 : 0)
})()
