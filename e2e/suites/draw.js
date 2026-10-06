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
;(async () => {
  const b = await launch()
  const shots = process.argv[2]
  const host = await player(b, 'Host'); const code = await text(host, '#room-code')
  const bob = await player(b, 'Bob', `${U}/room/${code}`); const cara = await player(b, 'Cara', `${U}/room/${code}`)
  const all = [host, bob, cara]
  await wait(700); await click(bob, "I'M READY"); await click(cara, "I'M READY")
  await until(() => host.$eval('#start-button', e => !e.disabled)); await click(host, 'START GAME')

  console.log('--- the pen')
  ok('everyone reaches the drawing screen after the reveal', await until(async () => (await Promise.all(all.map(p => p.$('#board')))).every(Boolean), 10000))
  await wait(400)
  let turns = await Promise.all(all.map(myTurn))
  ok('exactly one player has the pen', turns.filter(Boolean).length === 1, JSON.stringify(turns))
  let drawer = all[turns.indexOf(true)]; let spectators = all.filter(p => p !== drawer)
  ok('only the drawer\'s canvas accepts drawing', (await drawer.$eval('#board', e => e.dataset.canDraw)) === 'true' && (await Promise.all(spectators.map(p => p.$eval('#board', e => e.dataset.canDraw)))).every(v => v === 'false'))
  ok('only the drawer sees the toolbar buttons', !!(await drawer.$('#done-button')) && (await Promise.all(spectators.map(p => p.$('#done-button')))).every(x => !x))
  const names = await Promise.all(spectators.map(p => text(p, '#turn-text')))
  ok('spectators are told who is drawing', names.every(t => t === `${drawer.name} is drawing`), names.join(' | '))
  ok('the drawer is told it is their turn', (await text(drawer, '#turn-text')) === 'Your turn. Draw!')
  const t0 = parseInt(await text(drawer, '#turn-timer'))
  ok('a countdown is running', t0 > 0 && t0 <= 8, 'seconds=' + t0)
  const color = rgb(await drawer.$eval('#turn-order li[data-drawing="true"] [data-marker] path[fill]:not([opacity]), #turn-order li[data-drawing="true"] [data-marker] polygon, #turn-order li[data-drawing="true"] [data-marker] circle', e => getComputedStyle(e).fill))

  console.log('--- drawing live')
  ok('canvas starts empty on every screen', (await Promise.all(all.map(p => inked(p, 0.5, 0.5)))).every(v => !v))
  // a diagonal line from (0.2,0.3) to (0.8,0.7) passes through (0.5,0.5)
  await stroke(drawer, [[0.2, 0.3], [0.5, 0.5], [0.8, 0.7]]); await wait(500)
  for (const p of all) {
    ok(`${p.name}'s canvas shows the line`, (await inked(p, 0.35, 0.4)) && (await inked(p, 0.5, 0.5)) && (await inked(p, 0.65, 0.6)))
    ok(`${p.name}'s line is in the drawer's colour`, close(await pixel(p, 0.5, 0.5), color), JSON.stringify(await pixel(p, 0.5, 0.5)) + ' vs ' + color)
    ok(`${p.name}'s canvas is clean away from the line`, !(await inked(p, 0.8, 0.2)) && !(await inked(p, 0.2, 0.8)))
  }
  await drawer.screenshot({ path: shots + '/dr-drawer.png' }); await spectators[0].screenshot({ path: shots + '/dr-spectator.png' })

  console.log('--- a spectator cannot draw')
  await stroke(spectators[0], [[0.1, 0.8], [0.9, 0.9]]); await wait(400)
  ok('nothing appears for anyone', (await Promise.all(all.map(p => inked(p, 0.5, 0.85)))).every(v => !v))

  console.log('--- brush sizes, undo')
  await drawer.click('[data-brush="3"]')
  await stroke(drawer, [[0.2, 0.8], [0.8, 0.8]]); await wait(400)
  ok('a thick line is drawn for everyone', (await Promise.all(all.map(async p => (await inked(p, 0.5, 0.8)) && (await inked(p, 0.5, 0.8 + 0.012)))) ).every(Boolean))
  await drawer.click('#undo-button'); await wait(500)
  ok('undo removes the last stroke on every screen', (await Promise.all(all.map(p => inked(p, 0.5, 0.8)))).every(v => !v))
  ok('...and keeps the earlier one', (await Promise.all(all.map(p => inked(p, 0.5, 0.5)))).every(Boolean))
  await drawer.keyboard.down('Control'); await stroke(drawer, [[0.1, 0.1], [0.3, 0.1]]); await drawer.keyboard.up('Control'); await wait(300)
  ok('a stroke can be drawn then undone with Ctrl+Z', await inked(spectators[0], 0.2, 0.1))
  await drawer.keyboard.down('Control'); await drawer.keyboard.press('z'); await drawer.keyboard.up('Control'); await wait(400)
  ok('Ctrl+Z took it back', (await Promise.all(all.map(p => inked(p, 0.2, 0.1)))).every(v => !v))

  console.log('--- a refresh keeps the picture')
  const refreshed = spectators[1]
  await refreshed.reload({ waitUntil: 'networkidle0' }); await refreshed.waitForSelector('#board'); await wait(600)
  ok('the refreshed player sees the line so far', (await inked(refreshed, 0.5, 0.5)) && (await inked(refreshed, 0.35, 0.4)))
  ok('...and still sees whose turn it is', (await text(refreshed, '#turn-text')) === `${drawer.name} is drawing`)

  console.log('--- passing the pen')
  await click(drawer, "I'm done"); await wait(500)
  turns = await Promise.all(all.map(myTurn))
  ok('the pen moved to a different single player', turns.filter(Boolean).length === 1 && !turns[all.indexOf(drawer)], JSON.stringify(turns))
  const prev = drawer; drawer = all[turns.indexOf(true)]; spectators = all.filter(p => p !== drawer)
  ok('the new drawer sees the earlier line, drawn by the first player', await inked(drawer, 0.5, 0.5))
  ok('the old drawer can no longer draw', (await prev.$eval('#board', e => e.dataset.canDraw)) === 'false')
  const color2 = rgb(await drawer.$eval('#turn-order li[data-drawing="true"] [data-marker] path[fill]:not([opacity]), #turn-order li[data-drawing="true"] [data-marker] polygon, #turn-order li[data-drawing="true"] [data-marker] circle', e => getComputedStyle(e).fill))
  ok('the players have different colours', !close(color, color2, 30), JSON.stringify([color, color2]))
  await stroke(drawer, [[0.3, 0.8], [0.7, 0.8]]); await wait(400)
  ok('the second player\'s line is in THEIR colour on every screen', (await Promise.all(all.map(async p => close(await pixel(p, 0.5, 0.8), color2)))).every(Boolean))
  ok('and the first line is still in the first colour', (await Promise.all(all.map(async p => close(await pixel(p, 0.5, 0.5), color)))).every(Boolean))
  await spectators[0].screenshot({ path: shots + '/dr-two-strokes.png' })

  console.log('--- the timer passes the pen by itself')
  const who = async () => { const t = await Promise.all(all.map(myTurn)); return t.indexOf(true) }
  const before = await who()
  ok('the turn passes when the time runs out', await until(async () => (await who()) !== before, 12000))

  console.log('--- the secret never leaks into drawing traffic')
  const imposters = []; for (const p of all) if (/imposter/i.test(await text(p, '#secret-role') || '')) imposters.push(p)
  const word = await text(all.find(p => !imposters.includes(p)), '#secret-word')
  ok('exactly one imposter', imposters.length === 1)
  ok('the imposter still has a hint and no word', !!(await text(imposters[0], '#secret-hint')) && !(await imposters[0].evaluate(() => document.body.innerText)).toLowerCase().includes(word.toLowerCase()))
  ok(`the imposter's connection never carried "${word}" (${imposters[0].frames.length} frames)`, !imposters[0].frames.join('\n').toLowerCase().includes(word.toLowerCase()))
  ok('no connection carries the imposter id or turn queue', all.every(p => !/imposter_id|"queue"|used_words|turn_order/.test(p.frames.join('\n'))))
  ok('the card can be hidden', await (async () => { await all[0].click('#secret-toggle'); const t = await all[0].evaluate(() => document.querySelector('#secret-card').innerText); await all[0].click('#secret-toggle'); return /hidden/i.test(t) })())

  console.log('--- to the end')
  for (let i = 0; i < 20; i++) {
    const idx = await who(); if (idx < 0) break
    await click(all[idx], "I'm done"); await wait(350)
  }
  ok('after every turn the room moves to voting', await until(async () => (await Promise.all(all.map(p => text(p, '#turn-text')))).every(t => t === 'Who was faking it?'), 5000))
  ok('nobody can draw any more', (await Promise.all(all.map(p => p.$eval('#board', e => e.dataset.canDraw)))).every(v => v === 'false'))
  ok('the whole picture is still on screen for everyone', (await Promise.all(all.map(async p => (await inked(p, 0.5, 0.5)) && (await inked(p, 0.5, 0.8))))).every(Boolean))
  await all[0].screenshot({ path: shots + '/dr-voting.png' })

  const errs = all.flatMap(p => p.errs); ok('no page errors', errs.length === 0, errs.join('|'))
  console.log(fails ? `\n${fails} FAILED` : '\nALL PASSED')
  // closing Chrome sometimes never returns: say so and leave rather than hang the whole run
  await Promise.race([b.close(), wait(5000)])
  process.exit(fails ? 1 : 0)
})().catch(e => { console.log('CRASH', e.stack); process.exit(1) })
