const puppeteer = require('puppeteer-core')
const wait = ms => new Promise(r => setTimeout(r, ms))
const { U, launch } = require('../lib/browser')
const click = (p, t) => p.evaluate(t => { const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === t); if (!b) throw new Error('no button "' + t + '"'); b.click() }, t)
const text = (p, sel) => p.$eval(sel, e => e.textContent.trim().replace(/\s+/g, ' ')).catch(() => null)
let fails = 0
const ok = (n, c, x = '') => { if (!c) fails++; console.log(c ? 'PASS' : 'FAIL', n, x) }
async function until(fn, ms = 8000) { const t = Date.now(); while (Date.now() - t < ms) { try { if (await fn()) return true } catch {} await wait(100) } return false }

// `late`: arriving after the game began, there is no lobby to wait for
async function player(b, name, url = U + '/', late = false) {
  const ctx = await b.createBrowserContext(); const p = await ctx.newPage(); await p.setViewport({ width: 1200, height: 950 })
  p.errs = []; p.on('pageerror', e => p.errs.push(e.message))
  p.frames = []; const cdp = await p.createCDPSession(); await cdp.send('Network.enable')
  cdp.on('Network.webSocketFrameReceived', e => p.frames.push(e.response.payloadData))
  await p.evaluateOnNewDocument(() => localStorage.setItem('sketchy:seen-how-to-play', 'true'))
  await p.goto(url, { waitUntil: 'networkidle0' })
  await click(p, 'Play as Guest'); await p.waitForSelector('#name'); await p.type('#name', name); await p.keyboard.press('Enter')
  await p.waitForSelector(late ? '#turn-banner, #spectator-note, #vote-panel, #reveal-card' : '#room-code', { timeout: 10000 })
  p.name = name; return p
}

const myTurn = p => p.$eval('#turn-banner', e => e.dataset.myTurn === 'true').catch(() => false)
const lines = p => p.$$eval('#chat-log [data-chat-from]', els => els.map(e => ({ from: e.dataset.chatFrom, text: e.innerText.replace(/\s+/g, ' ').trim() }))).catch(() => [])
const notices = p => p.$$eval('#notices [data-notice]', els => els.map(e => e.textContent.trim().replace(/\s+/g, ' '))).catch(() => [])
const inked = (p, nx, ny) => p.evaluate((nx, ny) => { const c = document.querySelector('#board'); return c.getContext('2d').getImageData(Math.round(nx * c.width), Math.round(ny * c.height), 1, 1).data[3] > 200 }, nx, ny)
const vote = (p, name) => p.click(`[data-vote="${name}"]`)
async function roles(all) {
  const r = await Promise.all(all.map(async p => /imposter/i.test(await text(p, '#secret-role') || '')))
  const imposter = all[r.indexOf(true)]; const crew = all.filter(p => p !== imposter)
  return { imposter, crew, word: await text(crew[0], '#secret-word') }
}
async function stroke(p, pts) {
  const r = await p.$eval('#board', e => { const b = e.getBoundingClientRect(); return { x: b.x, y: b.y, w: b.width, h: b.height } })
  const at = ([nx, ny]) => [r.x + nx * r.w, r.y + ny * r.h]
  await p.mouse.move(...at(pts[0])); await p.mouse.down()
  for (const pt of pts.slice(1)) await p.mouse.move(...at(pt), { steps: 8 })
  await p.mouse.up()
}
async function startGame(all) {
  const [host, ...guests] = all
  for (const g of guests) await click(g, "I'M READY")
  await until(() => host.$eval('#start-button', e => !e.disabled), 4000); await click(host, 'START GAME')
  await until(async () => (await Promise.all(all.map(p => p.$('#board')))).every(Boolean), 12000); await wait(400)
}
async function newGame(b, names = ['Host', 'Bob', 'Cara']) {
  const host = await player(b, names[0]); const code = await text(host, '#room-code')
  const rest = []; for (const n of names.slice(1)) rest.push(await player(b, n, `${U}/room/${code}`))
  const all = [host, ...rest]; await wait(700); await startGame(all)
  return { all, code }
}

;(async () => {
  const b = await launch()
  const shots = process.argv[2]

  console.log('=== arriving mid-game: a spectator')
  {
    const { all, code } = await newGame(b)
    const r1 = await roles(all); const word = r1.word
    const pen = all[(await Promise.all(all.map(myTurn))).indexOf(true)]
    await stroke(pen, [[0.2, 0.3], [0.5, 0.5], [0.8, 0.7]]); await wait(400)

    const late = await player(b, 'Late', `${U}/room/${code}`, true)
    const everyone = [...all, late]
    ok('they can join after the game has started (no "game in progress" error)', !!(await late.$('#turn-banner')))
    ok('they are told they are watching, and until when', /You joined after the game began/.test(await text(late, '#spectator-note') || ''), await text(late, '#spectator-note'))
    ok('no card is dealt to them', !(await late.$('#secret-card')) && !(await late.$('#secret-bar')))
    ok('they are given the picture so far', await until(() => inked(late, 0.5, 0.5), 3000))
    ok('the others are told someone is watching', await until(async () => (await Promise.all(all.map(async p => (await notices(p)).some(n => /Late is watching/.test(n))))).every(Boolean), 3000), JSON.stringify(await notices(all[1])))
    ok('and see Late listed as watching', await until(async () => /Watching: Late/.test(await text(all[1], '#watchers') || ''), 3000))
    ok('Late is not in the drawing order (3 players, not 4)', (await late.$$eval('#turn-order li', e => e.length)) === 3 && !(await late.$('#turn-order li[data-player="Late"]')))
    ok('they cannot draw', (await late.$eval('#board', e => e.dataset.canDraw)) === 'false' && !(await late.$('#done-button')))
    await late.screenshot({ path: shots + '/sp-watching.png' })

    console.log('--- chat')
    ok('chat is closed while drawing, for them too', !(await late.$('#chat-panel')))

    console.log('--- the vote')
    for (let i = 0; i < 20; i++) {
      if (await all[0].$('#vote-panel')) break
      const t = await Promise.all(all.map(myTurn)); const idx = t.indexOf(true)
      if (idx < 0) { await wait(200); continue }
      await click(all[idx], "I'm done"); await wait(350)
    }
    ok('voting opens for everyone', await until(async () => (await Promise.all(everyone.map(p => p.$('#vote-panel')))).every(Boolean), 6000))
    ok('Late has no vote buttons, and is told why', (await late.$$('[data-vote]')).length === 0 && /watching this round/.test(await text(late, '#vote-watching') || ''))
    for (const p of all) {
      const names = await p.$$eval('[data-vote]', els => els.map(e => e.dataset.vote))
      ok(`${p.name} cannot vote for Late, and sees only the 2 others`, names.length === 2 && !names.includes('Late'), names.join(','))
    }
    ok('the vote counts the 3 players, not 4', /of 3 voted/.test(await text(all[0], '#vote-count') || ''))
    ok('chat is open for the vote, for Late as well', !!(await late.$('#chat-panel')))
    await wait(700)
    await late.click('#chat-input'); await late.type('#chat-input', 'just watching, but I think it is Bob'); await late.keyboard.press('Enter')
    ok('what Late says reaches the players', await until(async () => (await lines(all[1])).some(l => l.from === 'Late' && /think it is Bob/.test(l.text)), 3000))
    ok('Late\'s connection has never carried the secret word', !late.frames.join('\n').toLowerCase().includes(word.toLowerCase()), `${late.frames.length} frames`)

    await vote(r1.crew[0], r1.crew[1].name); await vote(r1.crew[1], r1.crew[0].name); await vote(r1.imposter, r1.crew[0].name)
    ok('the vote closes when the 3 players have voted: Late does not hold it up', await until(async () => !!(await all[0].$('#reveal-card')), 3000))
    ok('Late sees the result too', !!(await late.$('#reveal-card')))
    ok('the scoreboard has the 3 players, not Late', (await all[0].$$eval('#scoreboard li', e => e.length)) === 3 && !(await all[0].$('#scoreboard li[data-player="Late"]')))
    ok('Late gets no win/lose verdict, only the neutral outcome (no points)', (await late.$$eval('#scoreboard li', e => e.length)) === 3)

    console.log('--- the next round: Late is dealt in')
    ok('round 2 starts', await until(async () => (await Promise.all(everyone.map(async p => /Round 2 of/.test(await text(p, '#secret-card') || '') || /Round 2 of/.test(await text(p, '#turn-banner') || '')))).every(Boolean), 15000))
    ok('the others are told Late joins in', await until(async () => (await Promise.all(all.map(async p => (await notices(p)).some(n => /Late joins in this round/.test(n))))).every(Boolean), 3000))
    ok('Late now has a card', await until(async () => !!(await late.$('#secret-role')), 4000))
    ok('and is no longer "watching"', !(await late.$('#spectator-note')))
    await until(async () => (await Promise.all(everyone.map(p => p.$('#board')))).every(Boolean), 12000); await wait(400)
    ok('the drawing order now has 4 players, Late included', (await all[0].$$eval('#turn-order li', e => e.length)) === 4 && !!(await all[0].$('#turn-order li[data-player="Late"]')))
    const swatches = await all[0].$$eval('#turn-order li [data-marker]', els => els.map(e => e.querySelector('path[fill]:not([opacity]), polygon, circle').getAttribute('fill')))
    ok('with a colour of their own', new Set(swatches).size === 4, JSON.stringify(swatches))

    // go round until it is Late's turn, and let them draw
    let lateDrew = false
    for (let i = 0; i < 8 && !lateDrew; i++) {
      const t = await Promise.all(everyone.map(myTurn)); const idx = t.indexOf(true)
      if (idx < 0) { await wait(250); continue }
      if (everyone[idx] === late) {
        await stroke(late, [[0.1, 0.8], [0.9, 0.8]]); await wait(500)
        lateDrew = (await Promise.all(all.map(p => inked(p, 0.5, 0.8)))).every(Boolean)
      } else { await click(everyone[idx], "I'm done"); await wait(350) }
    }
    ok('Late takes a turn and everyone sees their stroke', lateDrew)
    const errs = everyone.flatMap(p => p.errs); ok('no page errors', errs.length === 0, errs.join('|'))
    for (const p of everyone) await p.close().catch(() => {})
  }

  console.log('=== coming and going: notices')
  {
    const host = await player(b, 'Host'); const code = await text(host, '#room-code')
    const bob = await player(b, 'Bob', `${U}/room/${code}`); const cara = await player(b, 'Cara', `${U}/room/${code}`)
    await wait(600)
    ok('a join is announced to the others', (await notices(host)).some(n => /Bob joined/.test(n)) && (await notices(host)).some(n => /Cara joined/.test(n)), JSON.stringify(await notices(host)))
    ok('and not to the person who joined', !(await notices(cara)).some(n => /Cara joined/.test(n)))
    await cara.reload({ waitUntil: 'networkidle0' })
    ok('someone who drops is reported', await until(async () => (await notices(host)).some(n => /Cara lost their connection/.test(n)), 4000), JSON.stringify(await notices(host)))
    ok('and when they are back', await until(async () => (await notices(host)).some(n => /Cara is back/.test(n)), 6000), JSON.stringify(await notices(host)))
    await click(bob, '← Leave')
    ok('someone who leaves is announced', await until(async () => (await notices(host)).some(n => /Bob left/.test(n)), 4000), JSON.stringify(await notices(host)))
    ok('the notices go away by themselves', await until(async () => (await notices(host)).length === 0, 8000))
    await host.screenshot({ path: shots + '/sp-notice.png' })
    for (const p of [host, bob, cara]) await p.close().catch(() => {})
  }

  console.log('=== the imposter leaves in the middle of the drawing')
  {
    const { all } = await newGame(b, ['Host', 'Bob', 'Cara', 'Dan'])
    const r = await roles(all)
    const witnesses = all.filter(p => p !== r.imposter)
    await click(r.imposter, '← Leave')
    ok('the round ends at once for everyone left', await until(async () => (await Promise.all(witnesses.map(p => p.$('#reveal-card')))).every(Boolean), 3000))
    ok('it says the imposter left, and the crew win', (await Promise.all(witnesses.map(async p => /imposter left/i.test(await text(p, '#turn-text') || '')))).every(Boolean), await text(witnesses[0], '#turn-text'))
    ok('everyone is told who left (and that they were the imposter)', (await Promise.all(witnesses.map(async p => (await notices(p)).some(n => new RegExp(r.imposter.name + ' left, and they were the imposter').test(n))))).every(Boolean), JSON.stringify(await notices(witnesses[0])))
    ok('the result reveals who it was', (await Promise.all(witnesses.map(async p => (await text(p, '#reveal-imposter')) === r.imposter.name))).every(Boolean))
    const scores = await witnesses[0].$$eval('#scoreboard li', els => Object.fromEntries(els.map(e => [e.dataset.player, Number(e.dataset.score)])))
    ok('the 3 crew get a point each', Object.values(scores).length === 3 && Object.values(scores).every(s => s === 1), JSON.stringify(scores))
    ok('no drawing board is left running: the drawing phase is over', await witnesses[0].$eval('#turn-banner', e => e.dataset.phase) === 'result')
    ok('and the game carries on to the next round with the 3 who are left', await until(async () => (await Promise.all(witnesses.map(async p => /Round 2 of/.test(await text(p, '#secret-card') || '')))).every(Boolean), 15000))
    await witnesses[0].screenshot({ path: shots + '/sp-imposter-left.png' })
    for (const p of all) await p.close().catch(() => {})
  }

  console.log('=== a crew member leaves: the round carries on')
  {
    const { all } = await newGame(b, ['Host', 'Bob', 'Cara', 'Dan'])
    const r = await roles(all)
    const leaver = r.crew.find(p => p.name !== 'Host') ?? r.crew[0]
    const stay = all.filter(p => p !== leaver)
    await click(leaver, '← Leave'); await wait(800)
    ok('the round is still on', (await Promise.all(stay.map(async p => (await p.$eval('#turn-banner', e => e.dataset.phase).catch(() => null)) === 'drawing'))).every(Boolean))
    ok('they are told who left, without being told they were not the imposter', (await Promise.all(stay.map(async p => (await notices(p)).some(n => new RegExp(leaver.name + ' left$').test(n))))).every(Boolean), JSON.stringify(await notices(stay[0])))
    for (const p of all) await p.close().catch(() => {})
  }

  console.log(fails ? `\n${fails} FAILED` : '\nALL PASSED'); await b.close()
})().catch(e => { console.log('CRASH', e.stack); process.exit(1) })
