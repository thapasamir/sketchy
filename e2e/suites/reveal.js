const puppeteer = require('puppeteer-core')
const wait = ms => new Promise(r => setTimeout(r, ms))
const { U, launch } = require('../lib/browser')
const click = (p, t) => p.evaluate(t => { const b=[...document.querySelectorAll('button')].find(x => x.textContent.trim()===t); if(!b) throw new Error('no button "'+t+'"'); b.click() }, t)
const text = (p, sel) => p.$eval(sel, e => e.textContent.trim().replace(/\s+/g,' ')).catch(() => null)
const body = p => p.evaluate(() => document.body.innerText)
let fails = 0
const ok = (n, c, x='') => { if(!c) fails++; console.log(c ? 'PASS' : 'FAIL', n, x) }
async function until(fn, ms=6000) { const t=Date.now(); while(Date.now()-t<ms){ try{ if(await fn()) return true }catch{} await wait(100) } return false }
async function player(b, name, url=U+'/') {
  const ctx = await b.createBrowserContext(); const p = await ctx.newPage(); await p.setViewport({ width: 1100, height: 900 })
  p.errs = []; p.on('pageerror', e => p.errs.push(e.message))
  // record every WebSocket frame this browser RECEIVES from the server
  p.frames = []; const cdp = await p.createCDPSession(); await cdp.send('Network.enable')
  cdp.on('Network.webSocketFrameReceived', e => p.frames.push(e.response.payloadData))
  await p.evaluateOnNewDocument(() => localStorage.setItem('sketchy:seen-how-to-play', 'true'))
  await p.goto(url, { waitUntil: 'networkidle0' })
  await click(p, 'Play as Guest'); await p.waitForSelector('#name'); await p.type('#name', name); await p.keyboard.press('Enter')
  await p.waitForSelector('#room-code'); p.name = name; return p
}
;(async () => {
  const b = await launch()
  const shots = process.argv[2]
  const host = await player(b, 'Host'); const code = await text(host, '#room-code')
  const bob = await player(b, 'Bob', `${U}/room/${code}`); const cara = await player(b, 'Cara', `${U}/room/${code}`)
  await wait(700); await click(bob, "I'M READY"); await click(cara, "I'M READY")
  await until(() => host.$eval('#start-button', e => !e.disabled)); await click(host, 'START GAME')
  const all = [host, bob, cara]
  ok('everyone gets a secret card', await until(async () => (await Promise.all(all.map(p => p.$('#secret-card')))).every(Boolean)))
  await wait(300)

  const roles = await Promise.all(all.map(p => text(p, '#secret-role')))
  const imposters = all.filter((p, i) => /imposter/i.test(roles[i]))
  const crew = all.filter((p, i) => !/imposter/i.test(roles[i]))
  ok('exactly one imposter and two crew', imposters.length === 1 && crew.length === 2, JSON.stringify(roles))
  const imp = imposters[0]
  const words = await Promise.all(crew.map(p => text(p, '#secret-word')))
  ok('both crew see the same word', words[0] && words[0] === words[1], words.join(' / '))
  const word = words[0]
  const cats = await Promise.all(all.map(p => text(p, '#secret-category')))
  ok('everyone sees the same category', cats.every(c => c && c === cats[0]), cats[0])
  const hint = await text(imp, '#secret-hint')
  ok('the imposter sees a hint, not the word', !!hint && hint.toLowerCase() !== word.toLowerCase(), `hint="${hint}" word="${word}"`)
  ok("the imposter's page does not contain the word anywhere", !(await body(imp)).toLowerCase().includes(word.toLowerCase()))
  ok('countdown is showing', /Drawing starts in \d+s/.test(await text(imp, '#reveal-countdown') || ''))
  await crew[0].screenshot({ path: shots + '/rv-crew.png' }); await imp.screenshot({ path: shots + '/rv-imposter.png' })

  console.log('--- what actually travelled over each WebSocket ---')
  const impFrames = imp.frames.join('\n').toLowerCase()
  ok(`the imposter's connection NEVER carried the word "${word}" (${imp.frames.length} frames inspected)`, !impFrames.includes(word.toLowerCase()))
  const crewBad = crew.filter(p => p.frames.join('\n').toLowerCase().includes('imposter'))
  ok("a crew member's connection never mentions 'imposter' at all", crewBad.length === 0)
  ok('no connection ever carries the imposter_id or the game state', all.every(p => !/imposter_id|used_words|imposter_history/.test(p.frames.join('\n'))))
  ok("the imposter's frames did carry their hint (so the check above is meaningful)", impFrames.includes(hint.toLowerCase()))

  console.log('--- reveal ends by itself ---')
  ok('after the countdown everyone is on the drawing screen', await until(async () => (await Promise.all(all.map(p => p.$('#turn-banner')))).every(Boolean), 6000))
  ok('the secret is still shown after the reveal', (await text(imp, '#secret-hint')) === hint && (await text(crew[0], '#secret-word')) === word)

  console.log('--- refresh keeps your own secret ---')
  await imp.reload({ waitUntil: 'networkidle0' }); await imp.waitForSelector('#secret-card'); await wait(300)
  await crew[0].reload({ waitUntil: 'networkidle0' }); await crew[0].waitForSelector('#secret-card'); await wait(300)
  ok('imposter refreshes: still the imposter with the same hint', /imposter/i.test(await text(imp, '#secret-role')) && (await text(imp, '#secret-hint')) === hint)
  ok('crew refreshes: still the same word', (await text(crew[0], '#secret-word')) === word)
  ok("...and the imposter's connection STILL never carried the word after the reload", !imp.frames.join('\n').toLowerCase().includes(word.toLowerCase()))

  const errs = all.flatMap(p => p.errs); ok('no page errors', errs.length === 0, errs.join('|'))
  console.log(fails ? `\n${fails} FAILED` : '\nALL PASSED'); await b.close()
})().catch(e => { console.log('CRASH', e.message); process.exit(1) })
