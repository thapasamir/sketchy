const puppeteer = require('puppeteer-core')
const wait = ms => new Promise(r => setTimeout(r, ms))
const { U, launch } = require('../lib/browser')
const { fitsScreen } = require('../lib/layout')
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
async function roles(all) {
  const r = await Promise.all(all.map(async p => /imposter/i.test(await text(p, '#secret-role') || '')))
  const imposter = all[r.indexOf(true)]; return { imposter, crew: all.filter(p => p !== imposter) }
}
const S = process.argv[2]
async function fresh(b, vp, seen = false) {
  const c = await b.createBrowserContext(); const p = await c.newPage(); await p.setViewport(vp)
  p.errs = []; p.on('pageerror', e => p.errs.push(e.message))
  if (seen) await p.evaluateOnNewDocument(() => localStorage.setItem('sketchy:seen-how-to-play', 'true'))
  return p
}
;(async () => {
  const b = await launch()

  console.log('--- the home screen')
  for (const [label, vp] of [['desktop', { width: 1440, height: 900 }], ['phone', { width: 390, height: 844, isMobile: true, hasTouch: true }]]) {
    const p = await fresh(b, vp); await p.goto(U + '/', { waitUntil: 'networkidle0' })
    ok(`${label}: three steps are shown`, (await p.$$('#home-steps li')).length === 3)
    const fit = await fitsScreen(p)
    ok(`${label}: it fits the screen`, fit.ok, fit.offenders.join(', '))
    ok(`${label}: both buttons are still there`, !!(await p.$('button')) && /Play as Guest/.test(await p.evaluate(() => document.body.innerText)))
    await p.screenshot({ path: `${S}/p3-home-${label}.png` })
    console.log(`--- how to play (${label}, short window)`)
    await p.setViewport({ ...vp, height: 620 })
    await p.click('#home-how-to-play'); await p.waitForSelector('#how-to-play'); await wait(500)
    const m = await p.evaluate(() => { const d = document.querySelector('#how-to-play').getBoundingClientRect(); const b = document.querySelector('#how-to-play-done').getBoundingClientRect(); const body = document.querySelector('#how-to-play-body'); return { doneBottom: b.bottom, doneTop: b.top, inner: innerHeight, dialogBottom: d.bottom, scrolls: body.scrollHeight > body.clientHeight } })
    ok(`${label}: "Got it" is on screen in a 620px-tall window`, m.doneBottom <= m.inner && m.doneTop >= 0, JSON.stringify(m))
    ok(`${label}: the steps scroll inside, not the whole dialog`, m.scrolls)
    await p.screenshot({ path: `${S}/p3-rules-${label}.png` })
    await p.click('#how-to-play-done'); await wait(300)
    ok(`${label}: it closes`, !(await p.$('#how-to-play')))
  }

  console.log('--- notices stay out of the way (desktop)')
  const host = await fresh(b, { width: 1440, height: 900 }, true); await host.goto(U + '/', { waitUntil: 'networkidle0' })
  await click(host, 'Play as Guest'); await host.waitForSelector('#name'); await host.type('#name', 'Host'); await host.keyboard.press('Enter'); await host.waitForSelector('#room-code')
  const code = await text(host, '#room-code')
  const g = await fresh(b, { width: 1440, height: 900 }, true); await g.goto(`${U}/room/${code}`, { waitUntil: 'networkidle0' })
  await click(g, 'Play as Guest'); await g.waitForSelector('#name'); await g.type('#name', 'Bob'); await g.keyboard.press('Enter')
  await until(async () => !!(await host.$('[data-notice]')), 4000)
  const n = await host.$eval('#notices', e => { const r = e.getBoundingClientRect(); return { left: r.left, top: r.top, bottom: r.bottom, inner: innerHeight } })
  ok('on a wide screen the notes sit at the bottom left', n.left < 40 && n.bottom > n.inner - 40, JSON.stringify(n))
  await host.screenshot({ path: `${S}/p3-toast.png` })
  await host.setViewport({ width: 390, height: 844, isMobile: true, hasTouch: true }); await wait(300)
  const nn = await host.$eval('#notices', e => { const r = e.getBoundingClientRect(); return { top: r.top } })
  ok('on a phone they stay at the top', nn.top < 60, JSON.stringify(nn))

  console.log('--- the imposter\'s guess')
  const all = await newGame(b); for (const p of all) await p.setViewport({ width: 1440, height: 900 })
  for (let i = 0; i < 14; i++) { const t = await Promise.all(all.map(myTurn)); const x = t.indexOf(true); if (x < 0) { if (await until(async () => !!(await all[0].$('#vote-panel')), 800)) break; continue } await click(all[x], "I'm done"); await wait(250) }
  await until(async () => !!(await all[0].$('#vote-panel')), 5000)
  const { imposter, crew } = await roles(all)
  await vote(crew[0], imposter.name); await vote(crew[1], imposter.name); await vote(imposter, crew[0].name)
  await until(async () => !!(await imposter.$('#guess-input')), 5000); await wait(300)
  ok('the button says what to do while empty', (await text(imposter, '#guess-button')) === 'Type a guess')
  ok('and is disabled', await imposter.$eval('#guess-button', e => e.disabled))
  ok('the note explains the rules of the guess', /One try/.test(await text(imposter, '#guess-note')) && /spelling/.test(await text(imposter, '#guess-note')))
  await imposter.type('#guess-input', 'abc')
  ok('typing turns it into "Guess"', (await text(imposter, '#guess-button')) === 'Guess' && await imposter.$eval('#guess-button', e => !e.disabled))
  await imposter.screenshot({ path: `${S}/p3-guess.png` })
  await imposter.click('#guess-button'); await wait(300)
  ok('no page errors', all.every(p => p.errs.length === 0))
  await b.close()
  console.log(fails ? `${fails} FAILED` : 'ALL PASSED'); process.exit(fails ? 1 : 0)
})()
