const puppeteer = require('puppeteer-core')
const wait = ms => new Promise(r => setTimeout(r, ms))
const { U, launch } = require('../lib/browser')
const { fitsScreen } = require('../lib/layout')
const click = (p, t) => p.evaluate(t => { const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === t); if (!b) throw new Error('no button "' + t + '"'); b.click() }, t)
const text = (p, sel) => p.$eval(sel, e => e.textContent.trim().replace(/\s+/g, ' ')).catch(() => null)
let fails = 0
const ok = (n, c, x = '') => { if (!c) fails++; console.log(c ? 'PASS' : 'FAIL', n, x) }
async function until(fn, ms = 8000) { const t = Date.now(); while (Date.now() - t < ms) { try { if (await fn()) return true } catch {} await wait(100) } return false }

// a player whose browser is instrumented: counts the sounds it makes, and records what the server sends it
async function player(b, name, url = U + '/', vp = { width: 1200, height: 950 }) {
  const ctx = await b.createBrowserContext(); const p = await ctx.newPage(); await p.setViewport(vp)
  p.errs = []; p.on('pageerror', e => p.errs.push(e.message))
  p.frames = []; const cdp = await p.createCDPSession(); await cdp.send('Network.enable')
  cdp.on('Network.webSocketFrameReceived', e => p.frames.push(e.response.payloadData))
  await p.evaluateOnNewDocument(() => {
    localStorage.setItem('sketchy:seen-how-to-play', 'true')
    window.__audio = { oscillators: 0 }
    const Real = window.AudioContext
    window.AudioContext = class extends Real { createOscillator() { window.__audio.oscillators++; return super.createOscillator() } }
  })
  await p.goto(url, { waitUntil: 'networkidle0' })
  await click(p, 'Play as Guest'); await p.waitForSelector('#name'); await p.type('#name', name); await p.keyboard.press('Enter')
  await p.waitForSelector('#room-code'); p.name = name; return p
}

const oscillators = p => p.evaluate(() => window.__audio.oscillators)
const logText = p => p.$eval('#chat-log', e => e.innerText).catch(() => null)
const lines = p => p.$$eval('#chat-log [data-chat-from]', els => els.map(e => ({ from: e.dataset.chatFrom, text: e.innerText.replace(/\s+/g, ' ').trim() }))).catch(() => [])
const hasChat = p => p.$('#chat-panel').then(Boolean)
async function say(p, msg) { await p.click('#chat-input'); await p.type('#chat-input', msg); await p.keyboard.press('Enter') }
const myTurn = p => p.$eval('#turn-banner', e => e.dataset.myTurn === 'true').catch(() => false)
const vote = (p, name) => p.click(`[data-vote="${name}"]`)
async function roles(all) {
  const r = await Promise.all(all.map(async p => /imposter/i.test(await text(p, '#secret-role') || '')))
  const imposter = all[r.indexOf(true)]; const crew = all.filter(p => p !== imposter)
  return { imposter, crew, word: await text(crew[0], '#secret-word') }
}
async function drawingOver(all) {
  for (let i = 0; i < 20; i++) {
    if (await all[0].$('#vote-panel')) break
    const turns = await Promise.all(all.map(myTurn)); const idx = turns.indexOf(true)
    if (idx < 0) { await wait(200); continue }
    await click(all[idx], "I'm done"); await wait(300)
  }
  return until(async () => (await Promise.all(all.map(p => p.$('#vote-panel')))).every(Boolean), 5000)
}

;(async () => {
  const b = await launch()
  const shots = process.argv[2]

  console.log('=== the lobby')
  const host = await player(b, 'Host'); const code = await text(host, '#room-code')
  const bob = await player(b, 'Bob', `${U}/room/${code}`); const cara = await player(b, 'Cara', `${U}/room/${code}`)
  const all = [host, bob, cara]; await wait(700)
  ok('there is a chat in the lobby', (await Promise.all(all.map(hasChat))).every(Boolean))
  ok('it starts empty, with a friendly hint', /Say hi/.test(await logText(host)))
  ok('Send is disabled until there is something to send', await host.$eval('#chat-send', e => e.disabled))

  await say(host, 'hello everyone')
  ok('everyone sees what Host said, under Host\'s name', await until(async () => (await Promise.all([bob, cara].map(async p => (await lines(p)).some(l => l.from === 'Host' && /hello everyone/.test(l.text))))).every(Boolean), 3000))
  ok('Host sees it as "You"', await until(async () => /You\s+hello everyone/.test((await lines(host))[0]?.text || ''), 3000), JSON.stringify(await lines(host)))
  ok('and the box is cleared after sending', (await host.$eval('#chat-input', e => e.value)) === '')

  console.log('--- sounds')
  const h0 = await oscillators(host); const b0 = await oscillators(bob)
  await wait(750); await say(host, 'second one')   // (the server allows one message per 600ms per person)
  await until(async () => (await lines(bob)).length === 2, 3000)
  ok('other people hear a soft blip for a new message', (await oscillators(bob)) > b0)
  ok('you do not hear your own', (await oscillators(host)) === h0)

  console.log('--- limits')
  await wait(750)   // be outside the previous message's 600ms window, so "fast one" is accepted
  await host.click('#chat-input'); await host.type('#chat-input', 'fast one'); await host.keyboard.press('Enter')
  await host.type('#chat-input', 'fast two'); await host.keyboard.press('Enter'); await wait(300)
  ok('speaking too fast is refused politely', /Slow down/.test(await text(host, '#chat-error') || ''), await text(host, '#chat-error'))
  ok('and what you typed is kept, so you can send it again', (await host.$eval('#chat-input', e => e.value)) === 'fast two')
  await wait(700); await host.keyboard.press('Enter'); await wait(400)
  ok('which then goes through', (await lines(bob)).some(l => /fast two/.test(l.text)))
  ok('the message box stops at 200 characters', await (async () => { await host.type('#chat-input', 'x'.repeat(260)); return (await host.$eval('#chat-input', e => e.value.length)) === 200 })())
  await host.$eval('#chat-input', e => { e.value = ''; e.dispatchEvent(new Event('input')) })

  console.log('--- hostile text is only ever shown as text')
  await wait(700)
  await bob.evaluate(() => { window.__xss = 0 })
  await say(cara, '<img src=x onerror="window.__xss=1"><script>window.__xss=2</script><b>bold</b>')
  await until(async () => (await lines(bob)).some(l => /<img/.test(l.text)), 3000)
  ok('it appears as literal characters, not as an image or bold text', (await lines(bob)).some(l => /<img src=x/.test(l.text) && /<b>bold<\/b>/.test(l.text)))
  ok('no element was created from it', await bob.evaluate(() => !document.querySelector('#chat-log img') && !document.querySelector('#chat-log b b') && ![...document.querySelectorAll('#chat-log b')].some(e => e.textContent === 'bold')))
  ok('and no script ran, on anyone\'s page', (await Promise.all(all.map(p => p.evaluate(() => !window.__xss)))).every(Boolean))

  console.log('--- the conversation survives a refresh, and a late joiner sees none of it')
  const before = (await lines(bob)).length
  await bob.reload({ waitUntil: 'networkidle0' }); await bob.waitForSelector('#chat-panel'); await wait(600)
  ok('after a refresh the conversation is still there', (await lines(bob)).length === before && before >= 4, `${before} -> ${(await lines(bob)).length}`)
  const dan = await player(b, 'Dan', `${U}/room/${code}`); await wait(700)
  ok('someone who joins later starts with an empty chat (the server keeps nothing)', (await lines(dan)).length === 0 && /Say hi/.test(await logText(dan)))
  await wait(600); await say(dan, 'hi, I am late')
  ok('but what is said from now on reaches them, and everyone', await until(async () => (await lines(host)).some(l => /I am late/.test(l.text)), 3000))
  await host.screenshot({ path: shots + '/ch-lobby.png' })
  await dan.close()
  await wait(1200)

  console.log('=== while the game is on: closed for the cards and the drawing')
  await click(bob, "I'M READY"); await click(cara, "I'M READY")
  await until(() => host.$eval('#start-button', e => !e.disabled), 4000); await click(host, 'START GAME')
  await until(async () => (await Promise.all(all.map(p => p.$('#secret-card')))).every(Boolean), 6000); await wait(300)
  ok('no chat while the cards are being read', (await Promise.all(all.map(hasChat))).every(x => !x))
  const r1 = await roles(all); const word = r1.word
  await until(async () => (await Promise.all(all.map(p => p.$('#board')))).every(Boolean), 12000); await wait(300)
  ok('no chat while people draw (the drawings are the clues)', (await Promise.all(all.map(hasChat))).every(x => !x))

  console.log('=== the vote: open, and the secret word is hidden')
  ok('voting opens', await drawingOver(all))
  ok('chat is open for the vote, in the sidebar next to the vote buttons', (await Promise.all(all.map(hasChat))).every(Boolean))
  ok('the lobby conversation is still there', (await lines(host)).some(l => /hello everyone/.test(l.text)))
  await say(r1.crew[0], `I am sure it is a ${word}!`)
  await until(async () => (await lines(r1.crew[1])).some(l => /I am sure it is a/.test(l.text)), 3000)
  const shown = (await lines(r1.imposter)).find(l => /I am sure it is a/.test(l.text))
  ok('everyone sees the message, with the word hidden', !!shown && !new RegExp(word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i').test(shown.text) && /\*/.test(shown.text), JSON.stringify(shown))
  await until(async () => (await lines(r1.crew[0])).some(l => /I am sure it is a/.test(l.text)), 3000)
  const sentBy = (await lines(r1.crew[0])).find(l => /I am sure it is a/.test(l.text))
  ok('and the speaker sees the same hidden version', !!sentBy && /\*/.test(sentBy.text), JSON.stringify(sentBy))
  ok('the imposter\'s connection has NEVER carried the word, chat included', !r1.imposter.frames.join('\n').toLowerCase().includes(word.toLowerCase()), `${r1.imposter.frames.length} frames inspected`)
  await r1.crew[1].screenshot({ path: shots + '/ch-vote.png' })

  console.log('=== a caught imposter guesses: chat is closed')
  for (const p of all) {
    const target = p === r1.imposter ? r1.crew[0].name : r1.imposter.name
    await vote(p, target)
  }
  ok('the guess begins', await until(async () => !!(await r1.imposter.$('#guess-panel')), 3000))
  ok('chat is closed while they guess (nobody can shout the word)', await until(async () => (await Promise.all(all.map(hasChat))).every(x => !x), 3000))
  await r1.imposter.type('#guess-input', 'no idea at all'); await r1.imposter.click('#guess-button')

  console.log('=== after the round: open again, and the word is no longer hidden')
  ok('the result appears', await until(async () => (await Promise.all(all.map(p => p.$('#reveal-card')))).every(Boolean), 4000))
  ok('chat is open on the result screen, with the conversation so far', (await Promise.all(all.map(hasChat))).every(Boolean) && (await lines(host)).length >= 5)
  await wait(700); await say(host, `it was ${word} all along`)
  await until(async () => (await lines(bob)).some(l => /all along/.test(l.text)), 3000)
  ok('the word is shown as typed now that everyone knows it', (await lines(bob)).some(l => new RegExp(word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i').test(l.text) && /all along/.test(l.text)))
  await host.screenshot({ path: shots + '/ch-result.png' })

  console.log('=== leaving ends the conversation')
  ok('this tab is remembering the chat', await host.evaluate(() => Object.keys(sessionStorage).some(k => k.startsWith('sketchy:chat:'))))
  await click(host, '← Leave'); await wait(600)
  ok('after leaving, nothing of it is kept', await host.evaluate(() => !Object.keys(sessionStorage).some(k => k.startsWith('sketchy:chat:'))))

  const errs = all.flatMap(p => p.errs); ok('no page errors', errs.length === 0, errs.join('|'))
  for (const p of all) await p.close().catch(() => {})

  console.log('=== a phone')
  {
    const PHONE = { width: 390, height: 844, deviceScaleFactor: 2, hasTouch: true, isMobile: true }
    const h = await player(b, 'Ph1', U + '/', PHONE); const c = await text(h, '#room-code')
    const p2 = await player(b, 'Ph2', `${U}/room/${c}`, PHONE)
    await wait(700)
    // on a phone the lobby's chat is a bar that opens
    for (const phone of [h, p2]) if (await phone.$('#chat-toggle')) { await phone.click('#chat-toggle'); await phone.waitForSelector('#chat-panel') }
    await h.evaluate(() => document.querySelector('#chat-panel').scrollIntoView({ block: 'center' }))
    const fit = await fitsScreen(h)
    ok('the chat fits a phone: nothing sticks out sideways', fit.ok, fit.offenders.join(', '))
    ok('the box is large enough that iOS will not zoom in when it is tapped (16px+)', await h.$eval('#chat-input', e => parseFloat(getComputedStyle(e).fontSize) >= 16))
    ok('the Send button is easy to tap', await h.$eval('#chat-send', e => e.getBoundingClientRect().height >= 44))
    await h.tap('#chat-input'); await h.type('#chat-input', 'typed on a phone'); await h.tap('#chat-send')
    ok('a message can be sent by tapping', await until(async () => (await lines(p2)).some(l => /typed on a phone/.test(l.text)), 3000))
    await h.screenshot({ path: shots + '/ch-phone.png' })
    await h.close(); await p2.close()
  }

  console.log(fails ? `\n${fails} FAILED` : '\nALL PASSED'); await b.close()
})().catch(e => { console.log('CRASH', e.stack); process.exit(1) })
