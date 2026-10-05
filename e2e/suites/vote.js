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

;(async () => {
  const b = await launch()
  const shots = process.argv[2]

  console.log('=== 1. catch the imposter; they guess the word (with a typo)')
  {
    const all = await newGame(b); const { imposter, crew, word } = await roles(all)
    ok('the drawing ends and everyone is asked to vote', await drawingOver(all))
    ok('the drawing is still on screen', (await Promise.all(all.map(p => p.$('#board')))).every(Boolean))
    ok('the banner asks who was faking it, with a countdown', (await Promise.all(all.map(async p => (await title(p)) === 'Who was faking it?' && parseInt(await text(p, '#turn-timer')) > 0))).every(Boolean))
    for (const p of all) {
      const names = await p.$$eval('[data-vote]', els => els.map(e => e.dataset.vote))
      ok(`${p.name} can pick the two OTHER players, not themselves`, names.length === 2 && !names.includes(p.name), names.join(','))
    }
    ok('nobody has voted yet', (await Promise.all(all.map(async p => /0 of 3 voted/.test(await text(p, '#vote-count'))))).every(Boolean))
    await crew[0].screenshot({ path: shots + '/vt-voting.png' })

    // the first crew member picks the wrong person, then changes their mind
    await vote(crew[0], crew[1].name); await wait(300)
    ok('a vote is highlighted for the voter', await crew[0].$eval(`[data-vote="${crew[1].name}"]`, e => e.getAttribute('aria-pressed') === 'true'))
    ok('everyone sees that ONE person has voted', (await Promise.all(all.map(async p => /1 of 3 voted/.test(await text(p, '#vote-count'))))).every(Boolean))
    ok('and who it was, in the player list', await crew[1].$eval(`[data-vote="${crew[0].name}"] [data-voted]`, () => true).catch(() => false))
    await vote(crew[0], imposter.name); await wait(300)
    ok('changing the vote moves the highlight', await crew[0].$eval(`[data-vote="${imposter.name}"]`, e => e.getAttribute('aria-pressed') === 'true') && await crew[0].$eval(`[data-vote="${crew[1].name}"]`, e => e.getAttribute('aria-pressed') === 'false'))
    ok('...without counting twice', (await Promise.all(all.map(async p => /1 of 3 voted/.test(await text(p, '#vote-count'))))).every(Boolean))
    ok('nobody else\'s connection was told whom they voted for', [crew[1], imposter].every(p => !p.frames.some(f => SECRET_VOTE.test(f))))
    ok('a refresh remembers my vote', await (async () => { await crew[0].reload({ waitUntil: 'networkidle0' }); await crew[0].waitForSelector('#vote-panel'); await wait(500); return crew[0].$eval(`[data-vote="${imposter.name}"]`, e => e.getAttribute('aria-pressed') === 'true') })())

    await vote(crew[1], imposter.name); await wait(150)
    ok('the vote has not closed while someone still has to vote', (await title(imposter)) === 'Who was faking it?')
    await vote(imposter, crew[0].name)
    ok('the moment everyone has voted, the imposter is caught', await until(async () => (await Promise.all(all.map(p => p.$('#guess-panel')))).every(Boolean), 3000))
    ok('the imposter is given a box to guess in', !!(await imposter.$('#guess-input')))
    ok('the crew are told to wait, with no box', (await Promise.all(crew.map(async p => !(await p.$('#guess-input')) && !!(await p.$('#guess-wait'))))).every(Boolean))
    ok('the banner names the caught player', (await title(crew[0])) === `${imposter.name} was caught!` && (await title(imposter)) === 'You were caught!')
    await imposter.screenshot({ path: shots + '/vt-guess.png' })
    ok('nobody can vote any more', (await Promise.all(all.map(p => p.$('#vote-panel')))).every(x => !x))

    ok('the word has NOT been sent to the imposter yet', !imposter.frames.join('\n').toLowerCase().includes(word.toLowerCase()))
    const typo = word.toLowerCase().slice(0, -1) + (word.length > 5 ? '' : 'x')
    await imposter.type('#guess-input', word.length >= 5 ? word.toLowerCase().replace(/(.)$/, '') : word.toLowerCase())
    await imposter.click('#guess-button')
    ok('the result appears for everyone', await until(async () => (await Promise.all(all.map(p => p.$('#reveal-card')))).every(Boolean), 3000))
    ok('it reveals who the imposter was', (await Promise.all(all.map(async p => (await text(p, '#reveal-imposter')).endsWith(imposter.name)))).every(Boolean))
    ok('it reveals the word', (await Promise.all(all.map(async p => (await text(p, '#reveal-word')) === word))).every(Boolean), word)
    ok('the forgiving guess counted', (await title(crew[0])) === 'Caught, but they guessed the word!' && (await title(imposter)) === 'Caught, but you guessed the word!', `${await title(crew[0])} | typed for "${word}"`)
    const s = await scores(crew[0])
    ok('scores: crew 1 each, imposter 1', crew.every(p => s[p.name] === 1) && s[imposter.name] === 1, JSON.stringify(s))
    ok('everyone sees the same scores', (await Promise.all(all.map(async p => JSON.stringify(await scores(p)) === JSON.stringify(s)))).every(Boolean))
    ok('the votes are shown: who voted for whom', await crew[0].$$eval('#scoreboard [data-voter]', els => els.length === 3))
    ok('the imposter\'s guess is shown', /guessed/.test(await text(crew[0], '#reveal-guess') || ''))
    await crew[0].screenshot({ path: shots + '/vt-result-caught.png' }); await imposter.screenshot({ path: shots + '/vt-result-imposter.png' })
    ok('no vote buttons are left, and a countdown to the next round runs', (await Promise.all(all.map(async p => !(await p.$('[data-vote]')) && !!(await p.$('#turn-timer'))))).every(Boolean))
    console.log('--- secrecy over the wire')
    const frames = imposter.frames; const firstResult = frames.findIndex(f => /"phase":"result"/.test(f))
    ok('the imposter\'s connection carried the word only once the round was over', firstResult > 0 && !frames.slice(0, firstResult).join('\n').toLowerCase().includes(word.toLowerCase()), `result at frame ${firstResult}/${frames.length}`)
    for (const p of all) await p.close().catch(() => {})
  }

  console.log('=== 2. the crew accuses an innocent player')
  {
    const all = await newGame(b); const { imposter, crew } = await roles(all)
    ok('voting opens', await drawingOver(all))
    await vote(crew[0], crew[1].name); await vote(crew[1], crew[0].name); await vote(imposter, crew[0].name)
    ok('the round ends at once, with no guess', await until(async () => (await Promise.all(all.map(p => p.$('#reveal-card')))).every(Boolean), 3000))
    ok('"innocent... the imposter got away" for the crew', /innocent. The imposter got away/.test(await title(crew[0])), await title(crew[0]))
    ok('"you got away with it" for the imposter', (await title(imposter)) === 'You got away with it!')
    const s = await scores(crew[0])
    ok('scores: imposter 2, crew 0', s[imposter.name] === 2 && crew.every(p => s[p.name] === 0), JSON.stringify(s))
    await imposter.screenshot({ path: shots + '/vt-result-escaped.png' })
    for (const p of all) await p.close().catch(() => {})
  }

  console.log('=== 3. nobody votes in time; then, a caught imposter who does not guess')
  {
    const all = await newGame(b); const { imposter } = await roles(all)
    ok('voting opens', await drawingOver(all))
    const t0 = Date.now()
    ok('the vote closes by itself', await until(async () => (await Promise.all(all.map(p => p.$('#reveal-card')))).every(Boolean), 12000), `after ${Date.now() - t0}ms`)
    ok('"no majority, the imposter got away"', /No majority/.test(await title(all.find(p => p !== imposter))), await title(all[0]))
    const s = await scores(all[0]); ok('imposter 2', s[imposter.name] === 2, JSON.stringify(s))
    for (const p of all) await p.close().catch(() => {})
  }
  {
    const all = await newGame(b); const { imposter, crew } = await roles(all)
    await drawingOver(all)
    await vote(crew[0], imposter.name); await vote(crew[1], imposter.name); await vote(imposter, crew[0].name)
    ok('caught', await until(async () => !!(await imposter.$('#guess-input')), 3000))
    const t0 = Date.now()
    ok('the guess time runs out by itself', await until(async () => (await Promise.all(all.map(p => p.$('#reveal-card')))).every(Boolean), 9000), `after ${Date.now() - t0}ms`)
    ok('"you caught the imposter" / "you were caught"', (await title(crew[0])) === 'You caught the imposter!' && (await title(imposter)) === 'You were caught!')
    const s = await scores(crew[0]); ok('crew 1 each, imposter 0', crew.every(p => s[p.name] === 1) && s[imposter.name] === 0, JSON.stringify(s))
    ok('no guess is shown', !(await crew[0].$('#reveal-guess')))
    for (const p of all) await p.close().catch(() => {})
  }

  console.log(fails ? `\n${fails} FAILED` : '\nALL PASSED'); await b.close()
})().catch(e => { console.log('CRASH', e.stack); process.exit(1) })
