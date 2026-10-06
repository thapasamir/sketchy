// How a turn announces itself: "Your turn!" with the word for whoever has the pen, and, for everyone
// else, how close their own turn is, right in the banner.
const wait = ms => new Promise(r => setTimeout(r, ms))
const { U, launch } = require('../lib/browser')
const click = (p, t) => p.evaluate(t => { const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === t); if (!b) throw new Error('no button "' + t + '"'); b.click() }, t)
const text = (p, sel) => p.$eval(sel, e => e.textContent.trim().replace(/\s+/g, ' ')).catch(() => null)
let fails = 0
const ok = (n, c, x = '') => { if (!c) fails++; console.log(c ? 'PASS' : 'FAIL', n, x) }
async function until(fn, ms = 8000) { const t = Date.now(); while (Date.now() - t < ms) { try { if (await fn()) return true } catch {} await wait(100) } return false }

async function player(b, name, url = U + '/') {
  const ctx = await b.createBrowserContext(); const p = await ctx.newPage(); await p.setViewport({ width: 1200, height: 950 })
  p.errs = []; p.on('pageerror', e => p.errs.push(e.message))
  await p.evaluateOnNewDocument(() => localStorage.setItem('sketchy:seen-how-to-play', 'true'))
  await p.goto(url, { waitUntil: 'networkidle0' })
  await click(p, 'Play as Guest'); await p.waitForSelector('#name'); await p.type('#name', name); await p.keyboard.press('Enter')
  await p.waitForSelector('#room-code'); p.name = name; return p
}
const myTurn = p => p.$eval('#turn-banner', e => e.dataset.myTurn === 'true').catch(() => false)

;(async () => {
  const b = await launch()
  const host = await player(b, 'Host'); const code = await text(host, '#room-code')
  const bob = await player(b, 'Bob', `${U}/room/${code}`); const cara = await player(b, 'Cara', `${U}/room/${code}`)
  const all = [host, bob, cara]
  await wait(700); await click(bob, "I'M READY"); await click(cara, "I'M READY")
  await until(() => host.$eval('#start-button', e => !e.disabled)); await click(host, 'START GAME')

  console.log('--- the first turn')
  ok('somebody is drawing', await until(async () => (await Promise.all(all.map(myTurn))).some(Boolean), 10000))
  const turns = await Promise.all(all.map(myTurn)); const drawer = all[turns.indexOf(true)]
  const waiting = all.filter(p => p !== drawer)
  ok('the drawer is told "Your turn!"', await until(async () => /Your turn!/.test(await text(drawer, '#turn-splash') || '')))
  const splash = await text(drawer, '#turn-splash')
  const word = await text(drawer, '#secret-word')
  ok('with what to draw (the word, or the imposter\'s clue)', word ? splash.includes(word) : /Your clue:/.test(splash), splash)
  ok('and nobody else is', (await Promise.all(waiting.map(p => p.$('#turn-splash')))).every(x => !x))
  const pen = await drawer.evaluate(() => { const e = document.querySelector('#turn-splash'); return getComputedStyle(e).pointerEvents })
  ok('the announcement never takes a tap', pen === 'none', pen)
  ok('and goes away by itself', await until(async () => !(await drawer.$('#turn-splash')), 4000))

  console.log('--- who is next is in the banner, for the people waiting')
  const labels = await Promise.all(waiting.map(p => text(p, '#turn-next')))
  ok('exactly one player is told they are up next', labels.filter(l => /You're up next/.test(l || '')).length === 1, labels.join(' | '))
  ok('the other is told who is next', labels.filter(l => /Next: /.test(l || '')).length === 1, labels.join(' | '))
  ok('the drawer has no such label', !(await drawer.$('#turn-next')))

  console.log('--- the pen moves on')
  const nextUp = waiting[labels.findIndex(l => /You're up next/.test(l || ''))]
  await click(drawer, "I'm done")
  ok('the one who was next now has the pen and is told so', await until(async () => (await myTurn(nextUp)) && /Your turn!/.test(await text(nextUp, '#turn-splash') || '')))
  ok('and the label is gone for them', !(await nextUp.$('#turn-next')))
  ok('the player who just drew is not told they are next (it is the third player, or no one)', await until(async () => !/You're up next/.test(await text(drawer, '#turn-next') || '')))

  ok('no page errors', all.every(p => p.errs.length === 0), all.flatMap(p => p.errs).join('|'))
  await b.close()
  console.log(fails ? `${fails} FAILED` : 'ALL PASSED'); process.exit(fails ? 1 : 0)
})().catch(e => { console.log('CRASH', e.stack); process.exit(1) })
