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

async function newGame(b, vp) {
  const host = await player(b, 'Host', U + '/', vp); const code = await text(host, '#room-code')
  const bob = await player(b, 'Bob', `${U}/room/${code}`, vp); const cara = await player(b, 'Cara', `${U}/room/${code}`, vp)
  const all = [host, bob, cara]
  await wait(700); await click(bob, "I'M READY"); await click(cara, "I'M READY")
  await until(() => host.$eval('#start-button', e => !e.disabled)); await click(host, 'START GAME')
  await until(async () => (await Promise.all(all.map(p => p.$('#board')))).every(Boolean), 10000); await wait(400)
  return all
}
const penHolder = async all => all[(await Promise.all(all.map(myTurn))).indexOf(true)]
const rowInk = (p, y, xs) => Promise.all(xs.map(x => inked(p, x, y)))

;(async () => {
  const b = await launch()
  const shots = process.argv[2]

  console.log('=== A. the turn runs out in the middle of a stroke')
  {
    const all = await newGame(b, { width: 1200, height: 950 })
    const drawer = await penHolder(all); const others = all.filter(p => p !== drawer)
    const r = await drawer.$eval('#board', e => { const b = e.getBoundingClientRect(); return { x: b.x, y: b.y, w: b.width, h: b.height } })
    const at = (nx, ny) => [r.x + nx * r.w, r.y + ny * r.h]
    await drawer.mouse.move(...at(0.1, 0.9)); await drawer.mouse.down()
    for (let i = 1; i <= 9; i++) { await drawer.mouse.move(...at(0.1 + 0.1 * i, 0.9), { steps: 4 }); await wait(1000) }
    const sawTurnEnd = !(await myTurn(drawer))
    await drawer.mouse.up(); await wait(1500)
    ok('the turn did end while the pen was still down', sawTurnEnd)
    const xs = Array.from({ length: 17 }, (_, i) => 0.1 + 0.05 * i)
    const mine = await rowInk(drawer, 0.9, xs); const theirs = await Promise.all(others.map(p => rowInk(p, 0.9, xs)))
    ok('the start of the line is there for everyone', mine[0] && theirs.every(t => t[0]))
    ok('the end of the line (drawn after time ran out) is on nobody\'s screen', !mine[16] && theirs.every(t => !t[16]), JSON.stringify({ mine: mine.map(Number).join(''), theirs: theirs.map(t => t.map(Number).join('')) }))
    ok('the drawer\'s screen shows exactly what everyone else sees', theirs.every(t => t.join() === mine.join()))
    const nextDrawer = await penHolder(all)
    ok('someone else has the pen now', !!nextDrawer && nextDrawer !== drawer)
    await nextDrawer.mouse.move(100, 100)
    const r2 = await nextDrawer.$eval('#board', e => { const b = e.getBoundingClientRect(); return { x: b.x, y: b.y, w: b.width, h: b.height } })
    await nextDrawer.mouse.move(r2.x + r2.w * 0.2, r2.y + r2.h * 0.2); await nextDrawer.mouse.down(); await nextDrawer.mouse.move(r2.x + r2.w * 0.6, r2.y + r2.h * 0.2, { steps: 8 }); await nextDrawer.mouse.up(); await wait(500)
    ok('and they can draw normally', (await Promise.all(all.map(p => inked(p, 0.4, 0.2)))).every(Boolean))
    for (const p of all) await p.close().catch(() => {})
  }

  console.log('=== B. the drawer closes their tab')
  {
    const all = await newGame(b, { width: 1200, height: 950 })
    const drawer = await penHolder(all); const rest = all.filter(p => p !== drawer)
    const name = drawer.name; const t0 = Date.now()
    await drawer.close()
    ok('the pen moves on without waiting out the whole turn', await until(async () => (await Promise.all(rest.map(async p => (await text(p, '#turn-text')) !== `${name} is drawing`))).every(Boolean), 20000), `after ${Date.now() - t0}ms`)
    const now = await penHolder(rest)
    ok('exactly one of the remaining players has the pen', !!now)
    ok('the absent player is marked away', (await rest[0].$eval(`#turn-order li[data-player="${name}"]`, e => /away/.test(e.textContent))))
    for (const p of rest) await p.close().catch(() => {})
  }

  console.log('=== C. phones')
  {
    const phone = { width: 390, height: 844, deviceScaleFactor: 2, hasTouch: true, isMobile: true }
    const all = await newGame(b, phone)
    const drawer = await penHolder(all); const others = all.filter(p => p !== drawer)
    const fits = await Promise.all(all.map(fitsScreen))
    ok('nothing sticks out sideways on a phone (all three)', fits.every(f => f.ok), fits.flatMap(f => f.offenders).join(', '))
    const r = await drawer.$eval('#board', e => { const b = e.getBoundingClientRect(); return { x: b.x, y: b.y, w: b.width, h: b.height } })
    ok('the canvas fits the screen width', r.w <= 390 && r.w > 300, `${r.w}x${r.h}`)
    ok('the canvas is on screen (no scrolling needed to draw)', r.y >= 0 && r.y + r.h <= 844, `y=${r.y} bottom=${r.y + r.h}`)
    const at = (nx, ny) => [r.x + nx * r.w, r.y + ny * r.h]
    await drawer.touchscreen.touchStart(...at(0.2, 0.3))
    for (let i = 1; i <= 10; i++) await drawer.touchscreen.touchMove(...at(0.2 + 0.06 * i, 0.3 + 0.04 * i))
    await drawer.touchscreen.touchEnd(); await wait(600)
    ok('a finger can draw, and everyone sees it', (await Promise.all(all.map(p => inked(p, 0.5, 0.5)))).every(Boolean))
    ok('the drawing is not scrolled/zoomed by the gesture', await drawer.evaluate(() => scrollY === 0 && visualViewport.scale === 1))
    await drawer.screenshot({ path: shots + '/dr-phone-drawer.png' }); await others[0].screenshot({ path: shots + '/dr-phone-spectator.png' })
    ok('the toolbar buttons are big enough to tap (>= 40px)', await drawer.evaluate(() => [...document.querySelectorAll('#toolbar button')].every(b => { const r = b.getBoundingClientRect(); return r.height >= 40 && r.width >= 40 })))
  }

  console.log(fails ? `\n${fails} FAILED` : '\nALL PASSED'); await b.close()
})().catch(e => { console.log('CRASH', e.stack); process.exit(1) })
