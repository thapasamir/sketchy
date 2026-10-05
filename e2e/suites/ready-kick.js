const puppeteer = require('puppeteer-core')
const wait = ms => new Promise(r => setTimeout(r, ms))
const { U, launch } = require('../lib/browser')
const { setSetting } = require('../lib/lobby')
const click = (p, t) => p.evaluate(t => { const b=[...document.querySelectorAll('button')].find(x => x.textContent.trim()===t); if(!b) throw new Error('no button "'+t+'"'); b.click() }, t)
const has = (p, t) => p.evaluate(t => document.body.innerText.includes(t), t)
const { playerRows: list } = require('../lib/lobby')
const row = (p, name) => p.$eval(`li[data-player="${name}"]`, e => e.innerText.replace(/\s+/g,' ').trim()).catch(() => null)
const exists = (p, sel) => p.$(sel).then(Boolean)
const startState = p => p.$eval('#start-button', e => ({ disabled: e.disabled, text: e.innerText.trim() }))
let fails = 0
const ok = (n, c, x='') => { if(!c) fails++; console.log(c ? 'PASS' : 'FAIL', n, x) }
async function until(fn, ms=4000) { const t=Date.now(); while(Date.now()-t<ms){ try{ if(await fn()) return true }catch{} await wait(100) } return false }
async function player(b, name, url=U+'/') {
  const ctx = await b.createBrowserContext(); const p = await ctx.newPage(); await p.setViewport({ width: 1100, height: 900 })
  p.errs = []; p.on('pageerror', e => p.errs.push(e.message))
  await p.evaluateOnNewDocument(() => localStorage.setItem('sketchy:seen-how-to-play', 'true'))
  await p.goto(url, { waitUntil: 'networkidle0' }); await click(p, 'Play as Guest'); await p.waitForSelector('#name')
  await p.type('#name', name); await p.keyboard.press('Enter'); await p.waitForSelector('#room-code'); return p
}
;(async () => {
  const b = await launch()
  const shots = process.argv[2]
  const host = await player(b, 'Host'); const code = await host.$eval('#room-code', e => e.textContent.trim())
  const bob = await player(b, 'Bob', `${U}/room/${code}`); const cara = await player(b, 'Cara', `${U}/room/${code}`)
  await until(async () => (await startState(host)).text.includes('ready'))

  console.log('--- ready ---')
  ok('host sees "Waiting for 2 to get ready", start disabled', (await startState(host)).disabled && (await startState(host)).text === 'Waiting for 2 to get ready', (await startState(host)).text)
  ok('non-host gets a Ready button, no Start button', await exists(bob, '#ready-button') && !(await exists(bob, '#start-button')))
  ok('host has no Ready button', !(await exists(host, '#ready-button')))
  await click(bob, "I'M READY")
  ok('everyone sees Bob as ready', await until(async () => (await row(host, 'Bob'))?.includes('(ready)') && (await row(cara, 'Bob'))?.includes('(ready)')))
  ok("Bob's button now offers undo", await has(bob, 'Ready (tap to undo)'))
  ok('host now waits for 1', (await startState(host)).text === 'Waiting for 1 to get ready')
  await click(bob, 'Ready (tap to undo)')
  ok('undo clears the ready badge for everyone', await until(async () => !(await row(host, 'Bob'))?.includes('(ready)')))
  await click(bob, "I'M READY"); await click(cara, "I'M READY")
  ok('host can start once everyone is ready', await until(async () => { const s = await startState(host); return !s.disabled && s.text === 'START GAME' }))

  await setSetting(host, 'rounds', 4)
  ok('changing a setting clears everyone\'s ready', await until(async () => !(await row(host, 'Bob'))?.includes('(ready)') && !(await row(host, 'Cara'))?.includes('(ready)') && (await startState(host)).disabled))
  await bob.screenshot({ path: shots + '/rk-guest-ready.png' })
  await click(bob, "I'M READY"); await click(cara, "I'M READY")
  await until(async () => !(await startState(host)).disabled)
  await host.screenshot({ path: shots + '/rk-host-ready.png' })
  await click(host, 'START GAME')
  ok('game starts for everyone', await until(async () => (await Promise.all([host, bob, cara].map(p => p.$('#turn-banner')))).every(Boolean)))
  ok('no Remove buttons once the game started', !(await exists(host, '[data-kick]')))

  console.log('--- remove (kick) ---')
  const h2 = await player(b, 'Boss'); const c2 = await h2.$eval('#room-code', e => e.textContent.trim())
  const p2 = await player(b, 'Bob', `${U}/room/${c2}`); const p3 = await player(b, 'Cara', `${U}/room/${c2}`)
  await until(async () => (await list(h2)).length === 3)
  ok('host sees Remove on others, not on themselves', await exists(h2, '[data-kick="Bob"]') && await exists(h2, '[data-kick="Cara"]') && !(await exists(h2, '[data-kick="Boss"]')))
  ok('regular players see no Remove buttons', !(await exists(p2, '[data-kick]')))
  await h2.screenshot({ path: shots + '/rk-host-kick.png' })

  await h2.click('[data-kick="Bob"]')
  ok('first click only asks "Sure?"', (await row(h2, 'Bob')).includes('Sure?') && (await list(p3)).length === 3)
  await wait(3400)
  ok('...and the question times out without removing anyone', (await row(h2, 'Bob')).includes('Remove') && (await list(h2)).length === 3)

  await h2.click('[data-kick="Bob"]'); await h2.click('[data-kick="Bob"]')
  ok('second click removes Bob for everyone', await until(async () => (await list(h2)).length === 2 && (await list(p3)).length === 2 && !(await row(p3, 'Bob'))))
  ok('Bob is sent home with an explanation', await until(async () => await has(p2, 'removed you') && await exists(p2, '#code')))
  ok("Bob's seat is wiped (a refresh won't drag him back)", await p2.evaluate(() => localStorage.getItem('sketchy:seat')) === null)
  await p2.screenshot({ path: shots + '/rk-kicked.png' })

  await p2.reload({ waitUntil: 'networkidle0' })
  ok('after a refresh Bob is still on the dashboard, not in the room', await exists(p2, '#code') && !(await exists(p2, '#room-code')))

  await p2.type('#code', c2); await p2.keyboard.press('Enter'); await p2.waitForSelector('#room-code')
  ok('Bob may rejoin the same room (no ban)', await until(async () => (await list(h2)).length === 3 && !!(await row(h2, 'Bob'))))

  const errs = [host, bob, cara, h2, p2, p3].flatMap(p => p.errs)
  ok('no page errors', errs.length === 0, errs.join('|'))
  console.log(fails ? `\n${fails} FAILED` : '\nALL PASSED')
  await b.close()
})().catch(e => { console.log('CRASH', e.message); process.exit(1) })
