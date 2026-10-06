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
// everyone hands the pen on until the drawing is over
async function drawingOver(all) {
  for (let i = 0; i < 12; i++) {
    const turns = await Promise.all(all.map(myTurn)); const idx = turns.indexOf(true)
    if (idx < 0) { if (await until(async () => (await Promise.all(all.map(p => p.$('#vote-panel')))).every(Boolean), 800)) break; continue }
    await click(all[idx], "I'm done"); await wait(300)
  }
  return until(async () => (await Promise.all(all.map(p => p.$('#vote-panel')))).every(Boolean), 5000)
}
const vote = (p, name) => p.click(`[data-vote="${name}"]`)

const Y = { Host: 0.25, Bob: 0.5, Cara: 0.75 }
async function drawAll(all) {
  for (let i = 0; i < 12; i++) {
    const turns = await Promise.all(all.map(myTurn)); const idx = turns.indexOf(true)
    if (idx < 0) { if (await until(async () => (await Promise.all(all.map(p => p.$('#vote-panel')))).every(Boolean), 800)) break; continue }
    const p = all[idx]
    if (await inked(p, 0.5, Y[p.name])) { await click(p, "I'm done"); await wait(300); continue } // already drew a line on lap 1
    await stroke(p, [[0.2, Y[p.name]], [0.8, Y[p.name]]]); await wait(300)
    await click(p, "I'm done"); await wait(300)
  }
  return until(async () => (await Promise.all(all.map(p => p.$('#vote-panel')))).every(Boolean), 5000)
}
const alpha = async (p, name) => (await pixel(p, 0.5, Y[name]))[3]
const pressed = (p, name) => p.$eval(`[data-highlight="${name}"]`, e => e.getAttribute('aria-pressed'))

;(async () => {
  const b = await launch()
  const all = await newGame(b); const [host, bob, cara] = all
  ok('drawing finished, vote open', await drawAll(all))
  await wait(400)
  // during the vote, looking and voting are both done from the vote list: a name to look at, and a Vote button
  ok('the vote list has a name to look at for each other player', (await host.$$('#vote-panel [data-highlight]')).length === 2)
  ok('and no separate legend under the picture while voting', !(await host.$('#highlight-legend')))
  ok('each has a Vote button', (await host.$$('#vote-panel [data-vote]')).length === 2)
  const shapes = await host.$$eval('#vote-panel [data-highlight] [data-marker]', els => els.map(e => e.dataset.marker))
  ok('each name has its own shape', new Set(shapes).size === 2, shapes.join(','))
  const faced = await host.$$eval('#vote-panel [data-highlight] [data-marker]', els => els.map(e => e.getAttribute('data-faced')))
  ok('and shows their face, so you know who is who', faced.length === 2 && faced.every(f => f === 'true'), faced.join(','))
  ok('the steps are spelled out above the list', /Tap a name.*Press Vote/s.test(await host.$eval('#vote-steps', e => e.textContent)))
  ok('all three lines clear at first', (await alpha(host, 'Host')) > 200 && (await alpha(host, 'Bob')) > 200 && (await alpha(host, 'Cara')) > 200)

  await host.click('[data-highlight="Bob"]'); await wait(250)
  ok('Bob chip pressed', (await pressed(host, 'Bob')) === 'true')
  ok("Bob's line stays clear", (await alpha(host, 'Bob')) > 200)
  const dim = await alpha(host, 'Cara')
  ok("others fade (not gone)", dim > 5 && dim < 80, dim)
  ok('it is local: Cara still sees all', (await alpha(cara, 'Host')) > 200)
  await host.click('[data-highlight="Bob"]'); await wait(250)
  ok('tap again restores', (await alpha(host, 'Cara')) > 200)

  // tap a line on the canvas
  const r = await host.$eval('#board', e => { const b = e.getBoundingClientRect(); return { x: b.x, y: b.y, w: b.width, h: b.height } })
  await host.mouse.click(r.x + 0.6 * r.w, r.y + (Y.Cara + 0.01) * r.h); await wait(250)
  ok('tapping a line picks its owner', (await pressed(host, 'Cara')) === 'true' && (await alpha(host, 'Bob')) < 80)
  await host.mouse.click(r.x + 0.5 * r.w, r.y + 0.95 * r.h); await wait(250)
  ok('tapping empty paper clears it', (await pressed(host, 'Cara')) === 'false' && (await alpha(host, 'Bob')) > 200)

  // voting still works while a name is highlighted
  await host.click('[data-highlight="Bob"]'); await wait(150)
  ok('looking at a drawing is not a vote', (await host.$eval('[data-vote="Bob"]', e => e.getAttribute('aria-pressed'))) === 'false' && /0 of 3 voted/.test(await host.$eval('#vote-count', e => e.textContent)))
  await vote(host, 'Bob'); await wait(300)
  ok('can still vote', (await host.$eval('[data-vote="Bob"]', e => e.getAttribute('aria-pressed'))) === 'true')
  ok('the button says so', /Voted/.test(await host.$eval('[data-vote="Bob"]', e => e.textContent)))
  ok('and who the vote is still waiting for is named', /Waiting for .*Bob.*Cara|Waiting for .*Cara.*Bob/.test(await host.$eval('#vote-waiting', e => e.textContent)), await host.$eval('#vote-waiting', e => e.textContent))
  ok('no page errors', all.every(p => p.errs.length === 0), all.flatMap(p => p.errs).join('|'))
  await b.close()
  console.log(fails ? `${fails} FAILED` : 'ALL PASSED'); process.exit(fails ? 1 : 0)
})()
