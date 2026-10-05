const puppeteer = require('puppeteer-core')
const wait = ms => new Promise(r => setTimeout(r, ms))
const { U, launch } = require('../lib/browser')
const { fitsScreen } = require('../lib/layout')
const { setSetting, openSettings } = require('../lib/lobby')
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


const hint = p => text(p, '#laps-hint')
// which laps setting a player is shown (the summary shows it to everyone, host included)
const pressed = async (p, v) => (await text(p, '#laps-value')) === (v === 'auto' ? 'Auto' : String(v))
const setLaps = (host, v) => setSetting(host, 'laps', v)
const bannerLabel = p => p.$eval('#turn-banner .font-stamp', e => e.textContent.replace(/\s+/g, ' ').trim()).catch(() => '')

// play a drawing out turn by turn; returns what the banner said at each turn
async function playDrawing(all) {
  const labels = []
  for (let i = 0; i < 20; i++) {
    if (await all[0].$('#vote-panel')) break
    const turns = await Promise.all(all.map(myTurn)); const idx = turns.indexOf(true)
    if (idx < 0) { await wait(200); continue }
    labels.push(await bannerLabel(all[0]))
    await click(all[idx], "I'm done"); await wait(350)
  }
  await until(async () => (await Promise.all(all.map(p => p.$('#vote-panel')))).every(Boolean), 4000)
  return labels
}
async function startGame(all) {
  const [host, ...guests] = all
  for (const g of guests) await click(g, "I'M READY").catch(() => {})
  await until(() => host.$eval('#start-button', e => !e.disabled), 4000); await click(host, 'START GAME')
  await until(async () => (await Promise.all(all.map(p => p.$('#board')))).every(Boolean), 12000); await wait(300)
}

;(async () => {
  const b = await launch()
  const shots = process.argv[2]
  const host = await player(b, 'Host'); const code = await text(host, '#room-code')
  const bob = await player(b, 'Bob', `${U}/room/${code}`); const cara = await player(b, 'Cara', `${U}/room/${code}`)
  const all = [host, bob, cara]; await wait(700)

  console.log('=== the lobby control')
  ok('Auto is the default', await pressed(host, 'auto') && !(await pressed(host, 1)) && !(await pressed(host, 2)))
  ok('with 3 players it says 2 laps and 6 turns', /Auto: 2 laps with 3 players, so 6 turns per word/.test(await hint(host)), await hint(host))
  ok('guests see the same, as a summary with nothing to change', /Auto: 2 laps/.test(await hint(bob)) && !(await bob.$('#laps-1')) && (await text(bob, '#laps-value')) === 'Auto')
  await click(bob, "I'M READY"); await click(cara, "I'M READY")
  await setLaps(host, 1)
  ok('the host picks 1 lap: everyone sees it chosen', (await Promise.all(all.map(p => pressed(p, 1)))).every(Boolean))
  ok('and the hint says once, 3 turns', /Everyone draws once per word, so 3 turns/.test(await hint(bob)), await hint(bob))
  ok('changing it clears everyone\'s "ready" (they agreed to something else)', !(await host.evaluate(() => /\(ready\)/.test(document.querySelector('#player-list').innerText))))
  await setLaps(host, 2)
  ok('2 laps: "twice, 6 turns"', /twice per word, so 6 turns/.test(await hint(cara)), await hint(cara))
  await setLaps(host, 'auto')
  ok('back to Auto', await pressed(host, 'auto') && /Auto: 2 laps/.test(await hint(host)))
  await host.screenshot({ path: shots + '/lp-lobby.png' })

  console.log('=== auto follows the group size')
  const dan = await player(b, 'Dan', `${U}/room/${code}`); await wait(600)
  ok('4 players: still 2 laps, 8 turns', /Auto: 2 laps with 4 players, so 8 turns/.test(await hint(host)), await hint(host))
  const eve = await player(b, 'Eve', `${U}/room/${code}`); await wait(600)
  ok('5 players: Auto drops to 1 lap, 5 turns', /Auto: 1 lap with 5 players, so 5 turns/.test(await hint(host)), await hint(host))
  ok('...and everyone sees it change as people join', /Auto: 1 lap with 5 players/.test(await hint(dan)))
  await setLaps(host, 2)
  ok('the host can still force 2 laps with 5 players (10 turns)', /twice per word, so 10 turns/.test(await hint(host)), await hint(host))
  for (const p of [dan, eve]) await p.close().catch(() => {})
  await wait(800)
  await setLaps(host, 'auto'); await wait(300)

  console.log('=== a game with 1 lap: 3 turns')
  await setLaps(host, 1)
  await startGame(all)
  let labels = await playDrawing(all)
  ok('exactly 3 turns, one each', labels.length === 3, JSON.stringify(labels))
  ok('and the banner never mentions laps', labels.every(l => !/Lap/.test(l)), JSON.stringify(labels))

  console.log('=== then Auto with 3 players: 2 laps, 6 turns')
  // finish this round quickly (nobody votes in time), wait for round 2, which uses the same setting
  await wait(500)
  ok('the result comes (nobody voted)', await until(async () => !!(await host.$('#reveal-card')), 9000))
  await click(host, 'Next round now').catch(() => host.click('#next-round-button'))
  await until(async () => (await Promise.all(all.map(p => p.$('#board')))).every(Boolean), 12000); await wait(300)
  labels = await playDrawing(all)
  ok('exactly 3 more turns (the setting is still 1 lap)', labels.length === 3, JSON.stringify(labels))
  for (const p of all) await p.close().catch(() => {})

  // a fresh room on Auto
  const h2 = await player(b, 'Ann'); const code2 = await text(h2, '#room-code')
  const b2 = await player(b, 'Ben', `${U}/room/${code2}`); const c2 = await player(b, 'Cy', `${U}/room/${code2}`)
  const all2 = [h2, b2, c2]; await wait(600)
  await startGame(all2)
  labels = await playDrawing(all2)
  ok('Auto with 3 players: 6 turns', labels.length === 6, JSON.stringify(labels))
  ok('the banner counts the laps: Lap 1 of 2 three times, then Lap 2 of 2 three times', labels.slice(0, 3).every(l => /Lap 1 of 2/.test(l)) && labels.slice(3).every(l => /Lap 2 of 2/.test(l)), JSON.stringify(labels))
  ok('the banner also keeps the round: "Round 1 of 3"', labels.every(l => /Round 1 of 3/.test(l)))
  await h2.screenshot({ path: shots + '/lp-vote.png' })
  const errs = [...all, ...all2].flatMap(p => p.errs || []); ok('no page errors', errs.length === 0, errs.join('|'))

  console.log('=== a phone')
  const ph = await player(b, 'Phone', U + '/', { vp: { width: 390, height: 844, deviceScaleFactor: 2, hasTouch: true, isMobile: true } })
  const fit = await fitsScreen(ph)
  ok('the settings summary fits a phone', fit.ok, fit.offenders.join(', '))
  await openSettings(ph)
  const dialogFit = await fitsScreen(ph)
  ok('and so does the settings dialog, with the laps control', dialogFit.ok, dialogFit.offenders.join(', '))
  ok('and the three buttons are big enough to tap', await ph.$$eval('#laps-auto, #laps-1, #laps-2', els => els.every(e => e.getBoundingClientRect().height >= 44)))
  await ph.evaluate(() => document.querySelector('#laps-label').scrollIntoView({ block: 'center' })); await ph.screenshot({ path: shots + '/lp-phone.png' })

  console.log(fails ? `\n${fails} FAILED` : '\nALL PASSED'); await b.close()
})().catch(e => { console.log('CRASH', e.stack); process.exit(1) })
