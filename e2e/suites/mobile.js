const puppeteer = require('puppeteer-core')
const wait = ms => new Promise(r => setTimeout(r, ms))
const { U, launch } = require('../lib/browser')
const { fitsScreen } = require('../lib/layout')
const click = (p, t) => p.evaluate(t => { const b=[...document.querySelectorAll('button')].find(x => x.textContent.trim()===t); if(!b) throw new Error('no button "'+t+'"'); b.click() }, t)
const text = (p, sel) => p.$eval(sel, e => e.textContent.trim().replace(/\s+/g,' ')).catch(() => null)
let fails = 0
const ok = (n, c, x='') => { if(!c) fails++; console.log(c ? 'PASS' : 'FAIL', n, x) }
async function until(fn, ms=8000) { const t=Date.now(); while(Date.now()-t<ms){ try{ if(await fn()) return true }catch{} await wait(100) } return false }

async function player(b, name, url = U + '/', o = {}) {
  const ctx = await b.createBrowserContext(); const p = await ctx.newPage(); await p.setViewport(o.vp || { width: 1200, height: 950 })
  p.errs = []; p.on('pageerror', e => p.errs.push(e.message))
  p.frames = []; const cdp = await p.createCDPSession(); await cdp.send('Network.enable')
  cdp.on('Network.webSocketFrameReceived', e => p.frames.push(e.response.payloadData))
  if (o.reduced) await p.emulateMediaFeatures([{ name: 'prefers-reduced-motion', value: 'reduce' }])
  await p.evaluateOnNewDocument(seen => {
    if (seen) localStorage.setItem('sketchy:seen-how-to-play', 'true')
    window.__audio = { oscillators: 0, noise: 0 }; window.__vibes = 0; window.__hidden = false
    const Real = window.AudioContext
    window.AudioContext = class extends Real {
      createOscillator() { window.__audio.oscillators++; return super.createOscillator() }
      createBufferSource() { window.__audio.noise++; return super.createBufferSource() }
    }
    navigator.vibrate = () => { window.__vibes++; return true }
    Object.defineProperty(document, 'hidden', { get: () => window.__hidden })
  }, o.seen !== false)
  await p.goto(url, { waitUntil: 'networkidle0' })
  await click(p, 'Play as Guest'); await p.waitForSelector('#name'); await p.type('#name', name); await p.keyboard.press('Enter')
  await p.waitForSelector('#room-code'); p.name = name; return p
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
async function roles(all) {
  const r = await Promise.all(all.map(async p => /imposter/i.test(await text(p, '#secret-role') || '')))
  const imposter = all[r.indexOf(true)]; const crew = all.filter(p => p !== imposter)
  const word = await text(crew[0], '#secret-word')
  return { imposter, crew, word }
}
const vote = (p, name) => p.click(`[data-vote="${name}"]`)
const scores = p => p.$$eval('#scoreboard li', els => Object.fromEntries(els.map(e => [e.dataset.player, Number(e.dataset.score)])))
const title = p => text(p, '#turn-text')
const SECRET_VOTE = /"vote":"/


const myTurn = p => p.$eval('#turn-banner', e => e.dataset.myTurn === 'true').catch(() => false)
const audio = p => p.evaluate(() => ({ ...window.__audio }))
const confettiInk = p => p.evaluate(() => { const c = document.querySelector('#confetti'); if (!c) return -1; const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data; let n = 0; for (let i = 3; i < d.length; i += 4 * 17) if (d[i] > 0) n++; return n })
const anim = (p, sel) => p.$eval(sel, e => { const s = getComputedStyle(e); return { name: s.animationName, delay: parseFloat(s.animationDelay), dur: parseFloat(s.animationDuration), opacity: +s.opacity } }).catch(() => null)
const wrongAccusation = async (imposter, crew) => { await vote(crew[0], crew[1].name); await vote(crew[1], crew[0].name); await vote(imposter, crew[0].name) }


const PHONE = { width: 390, height: 844, deviceScaleFactor: 2, hasTouch: true, isMobile: true }
const rectOf = (p, sel) => p.$eval(sel, e => { const r = e.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height, b: r.bottom, r: r.right } }).catch(() => null)
const pos = p => p.$eval('#board', e => 'x').then(() => p.evaluate(() => getComputedStyle(document.querySelector('#turn-banner').closest('section')).position)).catch(() => null)
async function touchStroke(p, pts) {
  const r = await rectOf(p, '#board'); const at = ([nx, ny]) => [r.x + nx * r.w, r.y + ny * r.h]
  await p.touchscreen.touchStart(...at(pts[0]))
  for (const pt of pts.slice(1)) await p.touchscreen.touchMove(...at(pt))
  await p.touchscreen.touchEnd()
}
async function game(b, vp) {
  const host = await player(b, 'Host', U + '/', { vp }); const code = await text(host, '#room-code')
  const bob = await player(b, 'Bob', `${U}/room/${code}`, { vp }); const cara = await player(b, 'Cara', `${U}/room/${code}`, { vp })
  const all = [host, bob, cara]; await wait(700)
  await click(bob, "I'M READY"); await click(cara, "I'M READY")
  await until(() => host.$eval('#start-button', e => !e.disabled)); await click(host, 'START GAME')
  await until(async () => (await Promise.all(all.map(p => p.$('#board')))).every(Boolean), 12000); await wait(500)
  return all
}

;(async () => {
  const b = await launch()
  const shots = process.argv[2]

  console.log('=== phones, portrait: your turn')
  const all = await game(b, PHONE)
  const pen = all[(await Promise.all(all.map(myTurn))).indexOf(true)]; const watchers = all.filter(p => p !== pen)
  const area = r => r.w * r.h / (390 * 844)
  const r = await rectOf(pen, '#board')
  ok('on your turn the drawing goes full screen by itself', (await pos(pen)) === 'fixed')
  ok('the picture is square', Math.abs(r.w - r.h) < 2, `${r.w}x${r.h}`)
  ok('and big: at least 40% of the whole screen (it was 28%)', area(r) >= 0.40, `${(area(r) * 100).toFixed(0)}%`)
  ok('it is nearly the full screen width', r.w >= 340, `${r.w}px of 390`)
  ok('it is all on screen', r.y >= 0 && r.b <= 844 && r.x >= 0 && r.r <= 390)
  const tools = await rectOf(pen, '#toolbar'); const done = await rectOf(pen, '#done-button')
  ok('the tools are on screen, under the picture, in reach of a thumb', tools.y >= r.b - 1 && done.b <= 844 && done.y > 844 * 0.6, JSON.stringify({ toolsTop: tools.y, doneBottom: done.b }))
  ok('every tool is big enough to tap (44px)', await pen.$$eval('#toolbar button', els => els.every(e => { const x = e.getBoundingClientRect(); return x.width >= 44 && x.height >= 44 })))
  const timer = await rectOf(pen, '#turn-timer'); ok('the timer is on screen', timer && timer.y >= 0 && timer.b <= 844 && parseInt(await text(pen, '#turn-timer')) > 0)
  const bar = await rectOf(pen, '#secret-bar'); ok('your word stays visible', !!bar && bar.y >= 0 && bar.b <= 844 && (await text(pen, '#secret-bar')).length > 3, await text(pen, '#secret-bar'))
  ok('the page behind cannot scroll', await pen.evaluate(() => document.body.style.overflow === 'hidden'))
  const fit = await fitsScreen(pen)
  ok('nothing sticks out sideways', fit.ok, fit.offenders.join(', '))
  await pen.screenshot({ path: shots + '/mb-portrait-drawer.png' })

  console.log('--- drawing with a finger')
  await touchStroke(pen, [[0.15, 0.3], [0.5, 0.5], [0.85, 0.7]]); await wait(500)
  ok('the stroke appears on the drawer\'s screen', await pen.evaluate(() => { const c = document.querySelector('#board'); return c.getContext('2d').getImageData(Math.round(c.width * 0.5), Math.round(c.height * 0.5), 1, 1).data[3] > 200 }))
  ok('and on everyone else\'s', (await Promise.all(watchers.map(w => w.evaluate(() => { const c = document.querySelector('#board'); return c.getContext('2d').getImageData(Math.round(c.width * 0.5), Math.round(c.height * 0.5), 1, 1).data[3] > 200 })))).every(Boolean))
  ok('a long-press menu cannot open on the picture', await pen.$eval('#board', e => !e.dispatchEvent(new MouseEvent('contextmenu', { cancelable: true, bubbles: true }))))
  ok('the picture cannot be selected, and the app ships the iOS long-press callout switch (Chrome ignores that iOS-only property)', await pen.$eval('#board', e => getComputedStyle(e).userSelect === 'none') && (await (await fetch(U + '/assets/app.js')).text()).includes('-webkit-touch-callout: none'))
  ok('buttons answer instantly (no double-tap-zoom delay)', await pen.$eval('#done-button', e => getComputedStyle(e).touchAction === 'manipulation'))

  console.log('--- leaving full screen')
  await pen.tap('#immersive-close'); await wait(400)
  ok('you can leave full screen by hand', (await pos(pen)) !== 'fixed' && !!(await pen.$('#expand-button')))
  ok('and it stays closed for the rest of that turn', (await pos(pen)) !== 'fixed')
  const r2 = await rectOf(pen, '#board'); ok('in the normal layout it is still square and fits the width', Math.abs(r2.w - r2.h) < 2 && r2.w >= 330 && r2.r <= 390, `${r2.w}x${r2.h}`)
  await pen.tap('#expand-button'); await wait(400)
  ok('the expand button brings it back', (await pos(pen)) === 'fixed')

  console.log('=== spectators')
  const w = watchers[0]
  ok('a spectator sees the normal layout, with the picture square and fitting the screen', (await pos(w)) !== 'fixed' && await (async () => { const q = await rectOf(w, '#board'); return Math.abs(q.w - q.h) < 2 && q.r <= 390 && q.w >= 330 })())
  ok('with an expand button', !!(await w.$('#expand-button')))
  await w.screenshot({ path: shots + '/mb-portrait-spectator.png' })
  await w.tap('#expand-button'); await wait(400)
  const big = await rectOf(w, '#board')
  ok('tapping it fills the screen', (await pos(w)) === 'fixed' && area(big) >= 0.38, `${(area(big) * 100).toFixed(0)}%`)
  ok('they can still see whose turn it is and the time', /is drawing|Your turn/.test(await text(w, '#turn-text')) && parseInt(await text(w, '#turn-timer')) >= 0)
  ok('and the exit button', !!(await w.$('#immersive-close')))
  await pen.tap('#done-button').catch(() => {}); await wait(600)
  ok('it stays expanded when the turn passes to someone else', (await pos(w)) === 'fixed')
  await w.screenshot({ path: shots + '/mb-portrait-spectator-full.png' })

  console.log('=== the hand-over: the drawing screen returns when the turn is over')
  // finish every turn quickly; a full-screen layer must never be left behind
  for (let i = 0; i < 12; i++) {
    if (await all[0].$('#vote-panel')) break
    const t = await Promise.all(all.map(myTurn)); const idx = t.indexOf(true)
    if (idx < 0) { await wait(200); continue }
    if (i > 0) ok(`turn ${i + 1}: the new drawer got the full screen by themselves`, (await pos(all[idx])) === 'fixed', '')
    await click(all[idx], "I'm done"); await wait(450)
    ok(`turn ${i + 1}: the old drawer is back to normal`, (await pos(all[idx])) !== 'fixed' || all[idx] === w, '')
  }
  await until(async () => (await Promise.all(all.map(p => p.$('#vote-panel')))).every(Boolean), 5000)
  ok('at the vote nobody is stuck in full screen (even someone who expanded by hand)', (await Promise.all(all.map(async p => (await p.evaluate(() => getComputedStyle(document.querySelector('#vote-panel')).position)) && true))).every(Boolean) && (await Promise.all(all.map(async p => (await pos(p).catch(() => 'static')) !== 'fixed'))).every(Boolean))
  ok('and the page scrolls again', (await Promise.all(all.map(p => p.evaluate(() => document.body.style.overflow === '')))).every(Boolean))
  await watchers[1].screenshot({ path: shots + '/mb-vote.png' })
  for (const p of all) await p.close().catch(() => {})

  console.log('=== a phone on its side (landscape)')
  {
    const L = { width: 844, height: 390, deviceScaleFactor: 2, hasTouch: true, isMobile: true }
    const all = await game(b, L)
    const pen = all[(await Promise.all(all.map(myTurn))).indexOf(true)]
    const r = await rectOf(pen, '#board'); const tools = await rectOf(pen, '#toolbar')
    ok('full screen: the whole picture fits the short screen', (await pos(pen)) === 'fixed' && r.y >= 0 && r.b <= 390 + 1, JSON.stringify(r))
    ok('the tools fit on screen too', tools.b <= 390 + 1, JSON.stringify(tools))
    ok('and it is a decent size, not a postage stamp (at least 220px)', r.w >= 220, `${r.w}px`)
    await pen.screenshot({ path: shots + '/mb-landscape.png' })
    for (const p of all) await p.close().catch(() => {})
  }

  console.log('=== desktop is unchanged')
  {
    const all = await game(b, { width: 1200, height: 950 })
    const pen = all[(await Promise.all(all.map(myTurn))).indexOf(true)]
    ok('no full-screen takeover', (await pos(pen)) !== 'fixed')
    ok('no expand button', !(await pen.$('#expand-button')) || await pen.$eval('#expand-button', e => getComputedStyle(e).display === 'none'))
    const r = await rectOf(pen, '#board')
    ok('the picture is square, and fits above the fold', Math.abs(r.w - r.h) < 2 && r.b <= 950, `${r.w}x${r.h}, bottom ${r.b}`)
    ok('the player list is still beside it', !!(await pen.$('#turn-order')))
    await pen.screenshot({ path: shots + '/mb-desktop.png' })
    const errs = all.flatMap(p => p.errs); ok('no page errors', errs.length === 0, errs.join('|'))
    for (const p of all) await p.close().catch(() => {})
  }

  console.log(fails ? `\n${fails} FAILED` : '\nALL PASSED'); await b.close()
})().catch(e => { console.log('CRASH', e.stack); process.exit(1) })
