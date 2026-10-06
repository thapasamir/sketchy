const puppeteer = require('puppeteer-core')
const wait = ms => new Promise(r => setTimeout(r, ms))
const { U, launch } = require('../lib/browser')
const { fitsScreen } = require('../lib/layout')
const click = (p, t) => p.evaluate(t => { const b=[...document.querySelectorAll('button')].find(x => x.textContent.trim()===t); if(!b) throw new Error('no button "'+t+'"'); b.click() }, t)
const text = (p, sel) => p.$eval(sel, e => e.textContent.trim().replace(/\s+/g,' ')).catch(() => null)
let fails = 0
const ok = (n, c, x='') => { if(!c) fails++; console.log(c ? 'PASS' : 'FAIL', n, x) }
async function until(fn, ms=8000) { const t=Date.now(); while(Date.now()-t<ms){ try{ if(await fn()) return true }catch{} await wait(100) } return false }
async function player(b, name, url=U+'/', vp={ width: 390, height: 844, deviceScaleFactor: 2, hasTouch: true, isMobile: true }) {
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
async function roles(all) {
  const r = await Promise.all(all.map(async p => /imposter/i.test(await text(p, '#secret-role') || '')))
  const imposter = all[r.indexOf(true)]; const crew = all.filter(p => p !== imposter)
  const word = await text(crew[0], '#secret-word')
  return { imposter, crew, word }
}
// scroll to the button and let the page settle first: the panel rises in, and a click that lands
// mid-animation can miss
const vote = async (p, name) => { await p.$eval(`[data-vote="${name}"]`, e => e.scrollIntoView({ block: 'center' })); await wait(250); await p.click(`[data-vote="${name}"]`) }
const scores = p => p.$$eval('#scoreboard li', els => Object.fromEntries(els.map(e => [e.dataset.player, Number(e.dataset.score)])))
const title = p => text(p, '#turn-text')
const SECRET_VOTE = /"vote":"/


;(async () => {
  const b = await launch()
  const all = await newGame(b); const { imposter, crew, word } = await roles(all)
  await drawingOver(all)
  const votingFits = await Promise.all(all.map(fitsScreen))
  ok('nothing sticks out sideways while voting', votingFits.every(f => f.ok), votingFits.flatMap(f => f.offenders).join(', '))
  const r = await crew[0].$eval('#vote-panel', e => { const b = e.getBoundingClientRect(); return { top: b.top, bottom: b.bottom } })
  ok('the vote panel is reachable without a long scroll', r.top < 844, JSON.stringify(r))
  // the vote is pinned to the bottom of the screen, so the picture stays in view while you choose
  // (the page has room under it, so scrolling the picture up to the top of the screen clears the dock)
  await crew[0].evaluate(() => document.querySelector('#board').scrollIntoView({ block: 'start' })); await wait(300)
  const dock = await crew[0].evaluate(() => { const d = document.querySelector('#vote-dock'); const b = d.getBoundingClientRect(); const board = document.querySelector('#board').getBoundingClientRect(); return { pos: getComputedStyle(d).position, top: b.top, bottom: b.bottom, vh: innerHeight, boardTop: board.top, boardBottom: board.bottom } })
  ok('on a phone the vote is pinned to the bottom of the screen', dock.pos === 'fixed' && Math.abs(dock.bottom - dock.vh) < 2, JSON.stringify(dock))
  ok('and the whole picture is still in view above it', dock.boardTop >= 0 && dock.boardBottom <= dock.top + 2, JSON.stringify(dock))
  const buttons = () => crew[0].$$eval('#vote-dock [data-vote]', els => els.map(e => e.getBoundingClientRect().height))
  await crew[0].tap('#vote-dock-toggle'); await wait(250)
  ok('it can be folded down to see more of the picture', (await buttons()).every(h => h === 0) && /0 of 3 voted/.test(await text(crew[0], '#vote-dock')))
  await crew[0].tap('#vote-dock-toggle'); await wait(250)
  ok('and opened again', (await buttons()).length === 2 && (await buttons()).every(h => h > 0))
  // the chat is further down: say when someone has written
  await crew[0].evaluate(() => window.scrollTo(0, 0)); await wait(300)
  ok('nothing new in the chat yet, so nothing is said', !(await crew[0].$('#vote-dock-chat')))
  await crew[1].type('#chat-input', 'it was you'); await crew[1].tap('#chat-send')
  ok('when someone writes while the chat is out of view, the dock says so', await until(async () => /1 new in chat/.test(await text(crew[0], '#vote-dock-chat') || ''), 4000), await text(crew[0], '#vote-dock-chat'))
  await crew[0].tap('#vote-dock-chat'); await wait(1200)
  ok('tapping it brings the chat into view, and the note goes', await until(async () => !(await crew[0].$('#vote-dock-chat')), 4000) && await crew[0].evaluate(() => { const r = document.querySelector('#chat-panel').getBoundingClientRect(); return r.top < innerHeight && r.bottom > 0 }))
  await crew[0].evaluate(() => document.querySelector('#board').scrollIntoView({ block: 'start' })); await wait(300)
  ok('the sound and help buttons are not hidden behind it', await crew[0].evaluate(() => { const c = document.querySelector('#sound-toggle').getBoundingClientRect(); const d = document.querySelector('#vote-dock').getBoundingClientRect(); return c.bottom <= d.top + 1 }))
  ok('vote buttons are big enough to tap', await crew[0].evaluate(() => [...document.querySelectorAll('[data-vote]')].every(b => b.getBoundingClientRect().height >= 44)))
  await crew[0].evaluate(() => document.querySelector('#vote-panel').scrollIntoView({ block: 'center' })); await wait(200)
  await wait(2000); await crew[0].screenshot({ path: process.argv[2] + "/vt-phone-voting.png" })
  await crew[0].tap(`[data-vote="${imposter.name}"]`); await wait(300)
  ok('tapping votes', await crew[0].$eval(`[data-vote="${imposter.name}"]`, e => e.getAttribute('aria-pressed') === 'true'))
  await vote(crew[1], imposter.name); await vote(imposter, crew[0].name); await wait(500)
  ok('the imposter\'s guess box is on screen on a phone', await imposter.evaluate(() => { document.querySelector('#guess-input').scrollIntoView({ block: 'center' }); const r = document.querySelector('#guess-input').getBoundingClientRect(); return r.top >= 0 && r.bottom <= innerHeight }))
  await imposter.screenshot({ path: process.argv[2] + '/vt-phone-guess.png' })
  await imposter.type('#guess-input', word); await imposter.tap('#guess-button'); await wait(800)
  await crew[0].evaluate(() => window.scrollTo(0, 0)); await crew[0].screenshot({ path: process.argv[2] + '/vt-phone-result.png', fullPage: true })
  const resultFits = await Promise.all(all.map(fitsScreen))
  ok('nothing sticks out sideways on the result', resultFits.every(f => f.ok), resultFits.flatMap(f => f.offenders).join(', '))
  console.log(fails ? `\n${fails} FAILED` : '\nALL PASSED'); await b.close()
})().catch(e => { console.log('CRASH', e.stack); process.exit(1) })
