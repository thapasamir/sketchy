const puppeteer = require('puppeteer-core')
const wait = ms => new Promise(r => setTimeout(r, ms))
const { U, launch } = require('../lib/browser')
const { setSetting } = require('../lib/lobby')
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


async function strokeOn(p, pts) {
  const r = await p.$eval('#board', e => { const b = e.getBoundingClientRect(); return { x: b.x, y: b.y, w: b.width, h: b.height } })
  const at = ([nx, ny]) => [r.x + nx * r.w, r.y + ny * r.h]
  await p.mouse.move(...at(pts[0])); await p.mouse.down()
  for (const pt of pts.slice(1)) await p.mouse.move(...at(pt), { steps: 8 })
  await p.mouse.up()
}
const pixelInked = (p, nx, ny) => p.evaluate((nx, ny) => { const c = document.querySelector('#board'); return c.getContext('2d').getImageData(Math.round(nx*c.width), Math.round(ny*c.height), 1, 1).data[3] > 200 }, nx, ny)
const wrongAccusation = async (all, imposter, crew) => { await vote(crew[0], crew[1].name); await vote(crew[1], crew[0].name); await vote(imposter, crew[0].name) }

;(async () => {
  const b = await launch()
  const shots = process.argv[2]

  // --- the lobby: a two-round game
  const host = await player(b, 'Host'); const code = await text(host, '#room-code')
  const bob = await player(b, 'Bob', `${U}/room/${code}`); const cara = await player(b, 'Cara', `${U}/room/${code}`)
  const all = [host, bob, cara]
  await wait(600)
  await setSetting(host, 'rounds', 2)
  ok('the host sets the game to 2 rounds', (await text(host, '#rounds-value')) === '2')
  ok('...and everyone sees it', (await text(bob, '#rounds-value')) === '2')
  ok('the setting is called "Rounds"', /Rounds/i.test(await text(host, 'dl')))
  await click(bob, "I'M READY"); await click(cara, "I'M READY")
  await until(() => host.$eval('#start-button', e => !e.disabled)); await click(host, 'START GAME')

  console.log('=== round 1')
  ok('the reveal says Round 1 of 2', await until(async () => /Round 1 of 2/.test(await text(host, '#secret-card') || '')), 4000)
  await until(async () => (await Promise.all(all.map(p => p.$('#board')))).every(Boolean), 10000)
  const r1 = await roles(all); const word1 = r1.word
  ok('the drawing banner says Round 1 of 2', /Round 1 of 2/.test(await text(host, '#turn-banner')))
  // whoever has the pen draws a line that we will look for (and not find) in round 2
  const pen1 = all[(await Promise.all(all.map(myTurn))).indexOf(true)]
  await strokeOn(pen1, [[0.15, 0.2], [0.85, 0.2]]); await wait(400)
  ok('everyone sees the round-1 line', (await Promise.all(all.map(p => pixelInked(p, 0.5, 0.2)))).every(Boolean))
  ok('voting opens', await drawingOver(all))
  await wrongAccusation(all, r1.imposter, r1.crew)
  ok('the result appears', await until(async () => (await Promise.all(all.map(p => p.$('#reveal-card')))).every(Boolean), 3000))
  ok('it says the next round is coming', (await Promise.all(all.map(async p => /Round 2 of 2 is next/.test(await text(p, '#next-text')))) ).every(Boolean))
  ok('only the host has a skip button', !!(await host.$('#next-round-button')) && !(await bob.$('#next-round-button')) && !(await cara.$('#next-round-button')))
  ok('there is a countdown to the next round', parseInt(await text(bob, '#turn-timer')) > 0)
  await host.screenshot({ path: shots + '/rd-result.png' })
  let s = await scores(host)
  ok('round 1 scored: imposter 2, others 0', s[r1.imposter.name] === 2 && r1.crew.every(p => s[p.name] === 0), JSON.stringify(s))

  console.log('=== the next round starts by itself')
  const t0 = Date.now()
  ok('round 2 begins on its own', await until(async () => (await Promise.all(all.map(async p => /Round 2 of 2/.test(await text(p, '#secret-card') || '')))).every(Boolean), 9000), `after ${Date.now() - t0}ms`)
  ok('a new reveal: every player has a card', (await Promise.all(all.map(p => p.$('#secret-role')))).every(Boolean))
  await until(async () => (await Promise.all(all.map(p => p.$('#board')))).every(Boolean), 10000)
  const r2 = await roles(all); const word2 = r2.word
  ok('a different word', word2 !== word1, `${word1} -> ${word2}`)
  ok('a different imposter (never the same player twice running)', r2.imposter !== r1.imposter, `${r1.imposter.name} -> ${r2.imposter.name}`)
  ok('the drawing banner says Round 2 of 2', /Round 2 of 2/.test(await text(host, '#turn-banner')))
  ok('the canvas is empty again, on every screen', (await Promise.all(all.map(p => pixelInked(p, 0.5, 0.2)))).every(v => !v))
  ok('the vote is fresh: nobody has voted', await (async () => { await drawingOver(all); return (await Promise.all(all.map(async p => /0 of 3 voted/.test(await text(p, '#vote-count'))))).every(Boolean) })())
  await wrongAccusation(all, r2.imposter, r2.crew)
  ok('round 2 result appears', await until(async () => (await Promise.all(all.map(p => p.$('#reveal-card')))).every(Boolean), 3000))
  s = await scores(host)
  ok('scores carried over: both imposters have 2, the other player 0', s[r1.imposter.name] === 2 && s[r2.imposter.name] === 2, JSON.stringify(s))
  ok('the last round says the final scores are next', (await Promise.all(all.map(async p => /last round/.test(await text(p, '#next-text'))))).every(Boolean))
  ok('the host\'s button now says "Final scores now"', (await text(host, '#next-round-button')) === 'Final scores now')

  console.log('=== the final')
  await host.click('#next-round-button')
  ok('everyone sees the final screen', await until(async () => (await Promise.all(all.map(p => p.$('#final-headline')))).every(Boolean), 3000))
  const headline = await text(host, '#final-headline')
  ok('a tie is announced as a tie', /^A tie: /.test(headline) && headline.includes(r1.imposter.name) && headline.includes(r2.imposter.name), headline)
  ok('the board shows 2 winners, highlighted', (await host.$$eval('#final-scores li[data-winner="true"]', e => e.length)) === 2)
  ok('and the correct totals', await host.$$eval('#final-scores li', els => els.map(e => Number(e.dataset.score)).sort().join(',')) === '0,2,2')
  ok('it says how many rounds were played', /after 2 rounds/.test(await text(host, '#final-banner')))
  // the story of the game
  const recapLines = await host.$$eval('#final-recap li', els => els.map(e => e.textContent.replace(/\s+/g, ' ').trim()))
  ok('the recap has a line per round', recapLines.length === 2, recapLines.join(' | '))
  ok('each says who the imposter was, the word, and how it went', recapLines[0].includes(r1.imposter.name) && recapLines[0].includes(word1) && /Got away/.test(recapLines[0]) && recapLines[1].includes(r2.imposter.name) && recapLines[1].includes(word2), recapLines.join(' | '))
  const disguise = await host.$eval('[data-award="disguise"]', e => e.textContent.replace(/\s+/g, ' ')).catch(() => '')
  ok('"Master of disguise" is shared by the two who got away', disguise.includes(r1.imposter.name) && disguise.includes(r2.imposter.name), disguise)
  ok('everyone sees the same recap', (await Promise.all(all.map(p => p.$$eval('#final-recap li', e => e.length)))).every(n => n === 2))
  ok('faces, not initials, beside the scores', (await host.$$eval('#final-scores [data-marker]', els => els.every(e => e.getAttribute('data-faced') === 'true'))))

  // sharing the results as a picture
  await host.evaluate(() => { window.__shared = null; navigator.canShare = () => true; navigator.share = async d => { const f = d.files[0]; window.__shared = { type: f.type, size: f.size, name: f.name, text: d.text } } })
  await host.click('#share-results')
  ok('where the phone can share files, the picture goes to its share sheet', await until(() => host.evaluate(() => !!window.__shared), 5000))
  const shared = await host.evaluate(() => window.__shared)
  ok('as a real PNG, with the result in the text', shared.type === 'image/png' && shared.size > 5000 && /Play Sketchy/.test(shared.text) && shared.text.includes(headline), JSON.stringify(shared))
  ok('and says so', await until(async () => /Shared/.test(await text(host, '#share-note') || ''), 2000))
  await bob.evaluate(() => { navigator.canShare = () => false })
  await bob.click('#share-results')
  ok('where it can\'t, the picture is saved instead', await until(async () => /Saved as a picture/.test(await text(bob, '#share-note') || ''), 5000), await text(bob, '#share-note'))
  await host.screenshot({ path: shots + '/rd-final-recap.png', fullPage: true })

  ok('only the host can start again', !!(await host.$('#play-again-button')) && !(await bob.$('#play-again-button')) && !!(await bob.$('#final-wait')))
  ok('the others are told who they are waiting for', /Waiting for Host/.test(await text(bob, '#final-wait')))
  ok('no game controls are left on the final screen', (await Promise.all(all.map(async p => !(await p.$('#board')) && !(await p.$('[data-vote]')) && !(await p.$('#guess-input'))))).every(Boolean))
  await host.screenshot({ path: shots + '/rd-final.png' }); await bob.screenshot({ path: shots + '/rd-final-guest.png' })

  console.log('--- secrecy over the whole game')
  const idxResult2 = (() => { let n = 0; return r2.imposter.frames.findIndex(f => /"phase":"result"/.test(f) && ++n === 2) })()
  ok('the round-2 imposter\'s connection never carried round 2\'s word before its result', idxResult2 > 0 && !r2.imposter.frames.slice(0, idxResult2).join('\n').toLowerCase().includes(word2.toLowerCase()), `second result at frame ${idxResult2}/${r2.imposter.frames.length}`)

  console.log('=== play again')
  await host.click('#play-again-button')
  ok('everyone is back in the lobby', await until(async () => (await Promise.all(all.map(p => p.$('#room-code')))).every(Boolean) && (await Promise.all(all.map(p => p.$('#final-headline')))).every(x => !x), 3000))
  ok('with the same 3 players', (await host.$$eval('#player-list li', e => e.length)) === 3)
  ok('the settings are back (2 rounds kept)', (await text(host, '#rounds-value')) === '2')
  ok('players are still ready, so the host can start at once', await until(() => host.$eval('#start-button', e => !e.disabled), 3000))
  await click(host, 'START GAME')
  ok('a new game starts at Round 1 of 2', await until(async () => (await Promise.all(all.map(async p => /Round 1 of 2/.test(await text(p, '#secret-card') || '')))).every(Boolean), 5000))
  ok('with a fresh card for everyone', (await Promise.all(all.map(p => p.$('#secret-role')))).every(Boolean))
  await until(async () => (await Promise.all(all.map(p => p.$('#board')))).every(Boolean), 10000)
  ok('and a clean canvas', (await Promise.all(all.map(p => pixelInked(p, 0.5, 0.2)))).every(v => !v))
  await drawingOver(all)
  await wrongAccusation(all, (await roles(all)).imposter, (await roles(all)).crew)
  await until(async () => (await Promise.all(all.map(p => p.$('#scoreboard')))).every(Boolean), 3000)
  s = await scores(host)
  ok('scores started again from zero (this game\'s first round only)', Object.values(s).sort().join(',') === '0,0,2', JSON.stringify(s))

  const errs = all.flatMap(p => p.errs); ok('no page errors', errs.length === 0, errs.join('|'))
  console.log(fails ? `\n${fails} FAILED` : '\nALL PASSED'); await b.close()
})().catch(e => { console.log('CRASH', e.stack); process.exit(1) })
