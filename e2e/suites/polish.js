const puppeteer = require('puppeteer-core')
const wait = ms => new Promise(r => setTimeout(r, ms))
const { U, launch } = require('../lib/browser')
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

;(async () => {
  const b = await launch()
  const shots = process.argv[2]

  console.log('=== how to play: on the home page')
  {
    const ctx = await b.createBrowserContext(); const p = await ctx.newPage(); await p.setViewport({ width: 1200, height: 900 })
    await p.goto(U + '/', { waitUntil: 'networkidle0' })
    ok('a "How to play" link is on the home page', !!(await p.$('#home-how-to-play')))
    ok('the "?" and sound buttons are always on screen', !!(await p.$('#help-button')) && !!(await p.$('#sound-toggle')))
    ok('the rules do NOT pop up on the home page by themselves', !(await p.$('#how-to-play')))
    await p.click('#home-how-to-play'); await p.waitForSelector('#how-to-play')
    ok('it opens as a proper dialog', await p.$eval('#how-to-play', e => e.getAttribute('role') === 'dialog' && e.getAttribute('aria-modal') === 'true' && !!document.getElementById(e.getAttribute('aria-labelledby'))))
    ok('with the title and all five steps', /How to play/.test(await text(p, '#how-to-play-title')) && (await p.$$eval('#how-to-play ol li', e => e.length)) === 5)
    ok('focus moves into the dialog (the close button)', await p.evaluate(() => document.activeElement?.getAttribute('aria-label') === 'Close'))
    ok('the page behind does not scroll', await p.evaluate(() => document.body.style.overflow === 'hidden'))
    let inside = true; for (let i = 0; i < 6; i++) { await p.keyboard.press('Tab'); inside = inside && await p.evaluate(() => !!document.activeElement.closest('#how-to-play')) }
    ok('Tab never leaves the dialog', inside)
    inside = true; for (let i = 0; i < 4; i++) { await p.keyboard.down('Shift'); await p.keyboard.press('Tab'); await p.keyboard.up('Shift'); inside = inside && await p.evaluate(() => !!document.activeElement.closest('#how-to-play')) }
    ok('nor does Shift+Tab', inside)
    await p.screenshot({ path: shots + '/po-howto.png' })
    await p.keyboard.press('Escape'); await wait(200)
    ok('Escape closes it', !(await p.$('#how-to-play')))
    ok('and focus goes back to what opened it', await p.evaluate(() => document.activeElement?.id === 'home-how-to-play'))
    ok('the page scrolls again', await p.evaluate(() => document.body.style.overflow === ''))
    await p.click('#help-button'); await p.waitForSelector('#how-to-play'); await p.mouse.click(8, 8); await wait(200)
    ok('clicking outside closes it', !(await p.$('#how-to-play')))
    await p.click('#help-button'); await p.waitForSelector('#how-to-play'); await p.click('#how-to-play-done'); await wait(200)
    ok('"Got it" closes it', !(await p.$('#how-to-play')))
    await ctx.close()
  }

  console.log('=== how to play: the first time someone sits down in a room')
  {
    const host = await player(b, 'Newbie', U + '/', { seen: false })
    ok('it opens by itself in the lobby for a first-timer', await until(async () => !!(await host.$('#how-to-play')), 2000))
    await host.click('#how-to-play-done'); await wait(300)
    ok('and goes away when they say "Got it"', !(await host.$('#how-to-play')))
    ok('it remembers they have seen it', await host.evaluate(() => localStorage.getItem('sketchy:seen-how-to-play') === 'true'))
    await host.reload({ waitUntil: 'networkidle0' }); await wait(500)
    ok('it does not come back after a refresh', !(await host.$('#how-to-play')))
    await host.click('#help-button'); await host.waitForSelector('#how-to-play')
    ok('but is one click away any time', !!(await host.$('#how-to-play')))
    await host.keyboard.press('Escape')
    const phone = await player(b, 'Phone', U + '/', { seen: false, vp: { width: 390, height: 844, deviceScaleFactor: 2, hasTouch: true, isMobile: true } })
    await phone.waitForSelector('#how-to-play')
    ok('on a phone: it fits the screen with no sideways scroll', await phone.evaluate(() => { const r = document.querySelector('#how-to-play').getBoundingClientRect(); return r.left >= 0 && r.right <= innerWidth && r.height <= innerHeight && document.documentElement.scrollWidth <= innerWidth }))
    ok('and the Got it button can be reached by scrolling inside it', await phone.evaluate(() => { const d = document.querySelector('#how-to-play'); d.scrollTop = d.scrollHeight; const r = document.querySelector('#how-to-play-done').getBoundingClientRect(); return r.bottom <= innerHeight + 1 && r.top >= 0 }))
    await phone.screenshot({ path: shots + '/po-howto-phone.png' })
  }

  console.log('=== sound on/off')
  {
    const host = await player(b, 'Host'); const code = await text(host, '#room-code')
    ok('sound starts on, and the button says so', (await host.$eval('#sound-toggle', e => e.getAttribute('aria-pressed'))) === 'false')
    const a0 = (await audio(host)).oscillators
    const bob = await player(b, 'Bob', `${U}/room/${code}`); await wait(700)
    ok('a player joining makes a sound', (await audio(host)).oscillators > a0, `${a0} -> ${(await audio(host)).oscillators}`)
    await host.click('#sound-toggle'); await wait(100)
    ok('muting is shown on the button and remembered', (await host.$eval('#sound-toggle', e => e.getAttribute('aria-pressed'))) === 'true' && await host.evaluate(() => localStorage.getItem('sketchy:muted') === 'true'))
    const a1 = await audio(host)
    const cara = await player(b, 'Cara', `${U}/room/${code}`); await wait(700)
    ok('while muted, a join is silent', (await audio(host)).oscillators === a1.oscillators)
    await host.reload({ waitUntil: 'networkidle0' }); await host.waitForSelector('#room-code')
    ok('the mute survives a refresh', (await host.$eval('#sound-toggle', e => e.getAttribute('aria-pressed'))) === 'true')
    await host.click('#sound-toggle'); await wait(100)
    ok('unmuting plays a little confirmation blip', (await audio(host)).oscillators > 0)
    for (const p of [host, bob, cara]) await p.close().catch(() => {})
  }

  console.log('=== a two-round game: sounds, animations, confetti')
  {
    const host = await player(b, 'Host'); const code = await text(host, '#room-code')
    const bob = await player(b, 'Bob', `${U}/room/${code}`, { reduced: true }); const cara = await player(b, 'Cara', `${U}/room/${code}`)
    const all = [host, bob, cara]
    for (const p of all) await p.evaluate(() => { window.__hidden = true })   // pretend every tab is in the background
    await wait(500)
    await host.$eval('#rounds', el => { el.value = '2'; el.dispatchEvent(new Event('input', { bubbles: true })); el.dispatchEvent(new Event('change', { bubbles: true })) }); await wait(300)
    await click(bob, "I'M READY"); await click(cara, "I'M READY")
    await until(() => host.$eval('#start-button', e => !e.disabled)); await click(host, 'START GAME')
    await until(async () => (await Promise.all(all.map(p => p.$('#secret-card')))).every(Boolean), 6000); await wait(250)

    const r1 = await roles(all)
    console.log('--- the reveal')
    const card = await anim(r1.crew[0], '#secret-card')
    ok('the card flips in', /flip-in/.test(card.name), JSON.stringify(card))
    ok('the imposter heading is stamped on, after a short delay (none for someone who asked for less motion)', await (async () => { const a = await anim(r1.imposter, '#secret-role'); const expected = r1.imposter === bob ? 0 : 0.45; return /stamp/.test(a.name) && Math.abs(a.delay - expected) < 0.02 })())
    ok('the crew\'s word pops in', /pop/.test((await anim(r1.crew[0], '#secret-word')).name))
    await r1.imposter.screenshot({ path: shots + '/po-reveal-imposter.png' })
    const aCrew = await audio(r1.crew[0]), aImp = await audio(r1.imposter)
    ok('everyone heard the card flip (a whoosh)', aCrew.noise >= 1 && aImp.noise >= 1, JSON.stringify({ crew: aCrew, imposter: aImp }))
    await wait(900)
    ok('the imposter also heard the stamp (a second noise burst)', (await audio(r1.imposter)).noise >= 2, JSON.stringify(await audio(r1.imposter)))
    ok('the reduced-motion player gets no animation time on the card', await (async () => { const a = await anim(bob, '#secret-card'); return a ? a.dur < 0.001 : true })())

    console.log('--- your turn: a buzz, and the tab title (the tab is "hidden")')
    await until(async () => (await Promise.all(all.map(p => p.$('#board')))).every(Boolean), 10000); await wait(300)
    const pen = all[(await Promise.all(all.map(myTurn))).indexOf(true)]
    ok('the drawer\'s tab title says it is their turn', /^Your turn!/.test(await pen.title()), await pen.title())
    ok('and their phone buzzed', (await pen.evaluate(() => window.__vibes)) >= 1)
    ok('the others\' titles are unchanged', (await Promise.all(all.filter(p => p !== pen).map(async p => !/^Your turn!/.test(await p.title())))).every(Boolean))
    await pen.evaluate(() => { window.__hidden = false; document.dispatchEvent(new Event('visibilitychange')) }); await wait(200)
    ok('coming back to the tab restores the title', !/^Your turn!/.test(await pen.title()), await pen.title())
    for (const p of all) await p.evaluate(() => { window.__hidden = false })
    ok('the turn banner pops in', /pop/.test((await anim(pen, '#turn-banner')).name))

    console.log('--- a round ends: the result is revealed in order')
    ok('voting opens', await drawingOver(all))
    await wrongAccusation(r1.imposter, r1.crew)
    await until(async () => !!(await host.$('#reveal-card')), 4000)
    const early = await anim(host, '#reveal-imposter > span'); await wait(250)
    ok('the imposter\'s name is hidden at first (suspense)', early.opacity < 0.2, `opacity ${early.opacity}`)
    await host.screenshot({ path: shots + '/po-result-early.png' })
    await wait(1300)
    await host.screenshot({ path: shots + '/po-result-mid.png' })
    ok('then it stamps in', (await anim(host, '#reveal-imposter > span')).opacity > 0.9)
    const gainer = await host.$eval('#scoreboard li[data-gained], #scoreboard li:has([data-gained])', e => e.dataset.player).catch(() => null)
    await wait(3300)
    ok('all scores have counted up to the real numbers', await host.$$eval('#scoreboard li', els => els.every(e => e.querySelector('.tabular-nums').textContent.trim() === e.dataset.score)))
    ok('points gained pop in', !!(await host.$('[data-gained]')))
    await host.screenshot({ path: shots + '/po-result-done.png' })
    const afterResult = await audio(r1.imposter)
    ok('the result had a sound for the imposter', afterResult.oscillators > aImp.oscillators)

    console.log('--- round 2, then the final')
    await until(async () => (await Promise.all(all.map(async p => /Round 2 of 2/.test(await text(p, '#secret-card') || '')))).every(Boolean), 12000)
    await until(async () => (await Promise.all(all.map(p => p.$('#board')))).every(Boolean), 10000)
    const r2 = await roles(all)
    ok('voting opens (round 2)', await drawingOver(all))
    await wrongAccusation(r2.imposter, r2.crew)
    await until(async () => !!(await host.$('#next-round-button')), 4000)
    await host.click('#next-round-button')
    ok('the final screen appears for everyone', await until(async () => (await Promise.all(all.map(p => p.$('#final-headline')))).every(Boolean), 4000))
    await wait(900)
    const isWinner = async p => p.evaluate(name => !!document.querySelector(`#final-scores li[data-player="${name}"][data-winner="true"]`), p.name)
    const results = []; for (const p of all) results.push({ name: p.name, win: await isWinner(p), ink: await confettiInk(p), reduced: p === bob })
    console.log('   ', JSON.stringify(results))
    ok('winners with normal motion see confetti', results.filter(r => r.win && !r.reduced).every(r => r.ink > 0))
    ok('winners who asked for reduced motion see none', results.filter(r => r.win && r.reduced).every(r => r.ink <= 0))
    ok('people who did not win see none', results.filter(r => !r.win).every(r => r.ink === -1))
    ok('at least one player got confetti (a tie of two winners)', results.some(r => r.ink > 0))
    ok('the headline is stamped on', /stamp/.test((await anim(host, '#final-headline')).name))
    const win = results.find(r => r.win && !r.reduced); const winPage = all.find(p => p.name === win.name)
    await winPage.screenshot({ path: shots + '/po-final-confetti.png' })
    await wait(3500)
    ok('the confetti clears itself', (await confettiInk(winPage)) <= 0)
    ok('the winner heard the fanfare, the others the soft ending', (await audio(winPage)).oscillators > 20)
    const errs = all.flatMap(p => p.errs); ok('no page errors', errs.length === 0, errs.join('|'))
  }

  console.log(fails ? `\n${fails} FAILED` : '\nALL PASSED'); await b.close()
})().catch(e => { console.log('CRASH', e.stack); process.exit(1) })
