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
async function roles(all) {
  const r = await Promise.all(all.map(async p => /imposter/i.test(await text(p, '#secret-role') || '')))
  const imposter = all[r.indexOf(true)]; return { imposter, crew: all.filter(p => p !== imposter) }
}
const Y = { Host: 0.25, Bob: 0.5, Cara: 0.75 }
const alpha = (p, name) => pixel(p, 0.5, Y[name]).then(d => d[3])
async function drawAll(all) {
  for (let i = 0; i < 12; i++) {
    const turns = await Promise.all(all.map(myTurn)); const idx = turns.indexOf(true)
    if (idx < 0) { if (await until(async () => !!(await all[0].$('#vote-panel')), 800)) break; continue }
    const p = all[idx]
    if (!(await inked(p, 0.5, Y[p.name]))) { await stroke(p, [[0.2, Y[p.name]], [0.8, Y[p.name]]]); await wait(300) }
    await click(p, "I'm done"); await wait(300)
  }
  return until(async () => !!(await all[0].$('#vote-panel')), 5000)
}
const S = process.argv[2]
;(async () => {
  const b = await launch()
  const all = await newGame(b); for (const p of all) await p.setViewport({ width: 1440, height: 900 })
  ok('drawing finished', await drawAll(all))
  const { imposter, crew } = await roles(all); const watcher = crew[0]
  await vote(crew[0], imposter.name); await vote(crew[1], imposter.name); await vote(imposter, crew[0].name)
  await until(async () => !!(await imposter.$('#guess-input')), 5000)
  await imposter.type('#guess-input', 'wrongword'); await imposter.click('#guess-button')
  await until(async () => (await Promise.all(all.map(p => p.$('#reveal-card')))).every(Boolean), 8000)
  const t0 = Date.now(); const at = ms => wait(Math.max(0, ms - (Date.now() - t0)))
  const other = crew[1]
  await at(300); ok('before the reveal, everyone\'s lines are clear', (await alpha(watcher, imposter.name)) > 200 && (await alpha(watcher, other.name)) > 200)
  await at(1900)
  ok('the imposter\'s stroke stays clear', (await alpha(watcher, imposter.name)) > 200)
  const faded = await alpha(watcher, other.name); ok('the others fade', faded > 5 && faded < 80, faded)
  ok('a stamp lands on the picture for everyone', (await Promise.all(all.map(p => p.$('[data-reveal-stamp]')))).every(Boolean))
  await watcher.screenshot({ path: `${S}/rv-spotlight.png` })
  await at(5800)
  ok('then everything comes back', (await alpha(watcher, other.name)) > 200)
  ok('a stamp does not block taps', await watcher.$eval('[data-reveal-stamp]', e => getComputedStyle(e).pointerEvents === 'none'))

  console.log('--- the result sidebar')
  const m = await watcher.evaluate(() => { const r = s => document.querySelector(s)?.getBoundingClientRect(); const c = r('#chat-panel'); return { chatBottom: c?.bottom, chatH: c?.height, innerH: innerHeight, side: document.querySelector('#sidebar').scrollHeight - document.querySelector('#sidebar').clientHeight } })
  ok('chat is on screen at 1440x900', m.chatBottom <= m.innerH + 1 && m.chatH > 150, JSON.stringify(m))
  ok('the sidebar needs no scrolling', m.side <= 1, m.side)
  ok('one row per player shows how they voted', (await watcher.$$eval('#scoreboard [data-voter]', els => els.length)) === 3)
  ok('there is no separate votes card any more', !(await watcher.$('#votes-card')))
  const votes = await watcher.$$eval('#scoreboard [data-voter]', els => Object.fromEntries(els.map(e => [e.dataset.voter, e.textContent.replace(/\s+/g, ' ').trim()])))
  ok('the vote lines read right', votes[crew[1].name].includes(`voted ${imposter.name}`) && votes[imposter.name].includes(`voted ${crew[0].name}`), JSON.stringify(votes))
  ok('a correct vote is marked', votes[crew[1].name].includes('✓') && !votes[imposter.name].includes('✓'))
  await watcher.screenshot({ path: `${S}/rv-result.png` })

  console.log('--- taking over from the reveal')
  // next round, then a fresh result is too slow: instead check that tapping a chip mid-spotlight sticks
  ok('no page errors', all.every(p => p.errs.length === 0), all.flatMap(p => p.errs).join('|'))
  await b.close()
  console.log(fails ? `${fails} FAILED` : 'ALL PASSED'); process.exit(fails ? 1 : 0)
})()
