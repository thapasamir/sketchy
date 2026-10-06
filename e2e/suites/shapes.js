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

;(async () => {
  const b = await launch()
  const all = await newGame(b)
  await wait(500)
  const turns = await Promise.all(all.map(myTurn)); const di = turns.indexOf(true)
  const drawer = all[di]
  console.log('--- more brush sizes, and shapes')
  ok('there are five brush sizes and four tools', (await drawer.$$('[data-brush]')).length === 5 && (await drawer.$$('[data-tool]')).length === 4)
  await drawer.click('[data-brush="5"]')
  await stroke(drawer, [[0.2, 0.9], [0.8, 0.9]]); await wait(400)
  ok('the biggest brush draws a very wide line for everyone', (await Promise.all(all.map(async p => (await inked(p, 0.5, 0.9)) && (await inked(p, 0.5, 0.9 + 0.032)) && (await inked(p, 0.5, 0.9 - 0.032))))).every(Boolean))
  await drawer.click('#undo-button'); await wait(500)
  await drawer.click('[data-brush="2"]'); await drawer.click('[data-tool="circle"]')
  ok('the circle tool shows as chosen', (await drawer.$eval('[data-tool="circle"]', e => e.getAttribute('aria-pressed'))) === 'true')
  await stroke(drawer, [[0.6, 0.05], [0.9, 0.35]]); await wait(500)
  ok('a circle appears for everyone: ring drawn, middle empty', (await Promise.all(all.map(async p => (await inked(p, 0.75, 0.05)) && (await inked(p, 0.9, 0.2)) && !(await inked(p, 0.75, 0.2))))).every(Boolean))
  await drawer.click('#undo-button'); await wait(500)
  ok('undo takes the whole circle away in one go', (await Promise.all(all.map(p => inked(p, 0.75, 0.05)))).every(v => !v))
  await drawer.click('[data-tool="box"]')
  await stroke(drawer, [[0.6, 0.05], [0.9, 0.35]]); await wait(500)
  ok('a box has its corner and its sides, and is empty inside', (await Promise.all(all.map(async p => (await inked(p, 0.6, 0.05)) && (await inked(p, 0.9, 0.35)) && (await inked(p, 0.75, 0.35)) && !(await inked(p, 0.75, 0.2))))).every(Boolean))
  await drawer.click('#undo-button'); await wait(500)
  await drawer.click('[data-tool="line"]')
  await stroke(drawer, [[0.1, 0.05], [0.4, 0.05]]); await wait(500)
  ok('a line is straight from end to end', (await Promise.all(all.map(async p => (await inked(p, 0.15, 0.05)) && (await inked(p, 0.35, 0.05))))).every(Boolean))
  await drawer.click('#undo-button'); await wait(500)
  await drawer.click('[data-tool="pen"]')
  ok('no page errors from the new tools', all.every(p => p.errs.length === 0), all.flatMap(p => p.errs).join('|'))

  await b.close()
  console.log(fails ? `${fails} FAILED` : 'ALL PASSED'); process.exit(fails ? 1 : 0)
})()
