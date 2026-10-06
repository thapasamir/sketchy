// Your own connection dropping: say so, and say when it is back. Others see you "away" meanwhile.
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
const banner = p => text(p, '#connection')

;(async () => {
  const b = await launch()
  const host = await player(b, 'Host'); const code = await text(host, '#room-code')
  const bob = await player(b, 'Bob', `${U}/room/${code}`)
  await wait(800)

  console.log('--- all is well')
  ok('nothing is said while connected', (await banner(host)) === '')

  console.log('--- a blip')
  await host.evaluate(() => window.dispatchEvent(new Event('offline'))); await wait(500)
  await host.evaluate(() => window.dispatchEvent(new Event('online'))); await wait(2000)
  ok('one that mends within a second is not worth a banner', (await banner(host)) === '')

  console.log('--- a real drop (the whole network goes away, as Chrome can pretend)')
  const cdp = await host.createCDPSession(); await cdp.send('Network.enable')
  const network = offline => cdp.send('Network.emulateNetworkConditions', { offline, latency: 0, downloadThroughput: -1, uploadThroughput: -1 })
  await network(true)
  ok('after a moment, the player is told the connection is lost', await until(async () => /Connection lost/.test(await banner(host) || ''), 4000), await banner(host))
  ok('it reads out as a status, for screen readers', await host.$eval('#connection', e => e.getAttribute('role') === 'status' && e.getAttribute('aria-live') === 'polite'))
  ok('and never gets in the way of a tap', await host.$eval('#connection', e => getComputedStyle(e).pointerEvents === 'none'))
  if (process.argv[2]) await host.screenshot({ path: process.argv[2] + '/cn-offline.png' })
  await network(false)
  ok('when it is back, they are told so', await until(async () => /Back online/.test(await banner(host) || ''), 15000), await banner(host))
  ok('and then it goes quiet', await until(async () => (await banner(host)) === '', 6000))
  ok('and the game carries on: the room still answers', await until(async () => /Host/.test(await text(host, '#player-list') || await text(host, 'main') || ''), 3000))
  ok('the other player never saw any of it', (await banner(bob)) === '')
  ok('no page errors', [host, bob].every(p => p.errs.length === 0), [host, bob].flatMap(p => p.errs).join('|'))
  await b.close()
  console.log(fails ? `${fails} FAILED` : 'ALL PASSED'); process.exit(fails ? 1 : 0)
})().catch(e => { console.log('CRASH', e.stack); process.exit(1) })
