const puppeteer = require('puppeteer-core')
const wait = ms => new Promise(r => setTimeout(r, ms))
const { U, launch } = require('../lib/browser')
const { setSetting } = require('../lib/lobby')
const click = (p, t) => p.evaluate(t => { const b=[...document.querySelectorAll('button')].find(x => x.textContent.trim()===t); if(!b) throw new Error('no button "'+t+'"'); b.click() }, t)
const has = (p, t) => p.evaluate(t => document.body.innerText.includes(t), t)
const { playerRows: list } = require('../lib/lobby')
const text = (p, sel) => p.$eval(sel, e => e.textContent.trim())
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

  console.log('--- settings & start ---')
  const alice = await player(b, 'Alice')
  const code = await text(alice, '#room-code')
  const bob = await player(b, 'Bob', `${U}/room/${code}`)
  ok('start disabled with 2 players, says why', await alice.$eval('#start-button', e => e.disabled) && await has(alice, 'Need 1 more player'))
  const cara = await player(b, 'Cara', `${U}/room/${code}`)
  await wait(600)
  await click(bob, "I'M READY"); await click(cara, "I'M READY"); await until(() => alice.$eval('#start-button', e => !e.disabled))
  ok('host can start with 3 connected and ready', await alice.$eval('#start-button', e => !e.disabled) && await has(alice, 'START GAME'))
  ok('non-host has Ready instead of Start', await bob.$exists?.('#x') === undefined && await bob.$('#ready-button') !== null && await bob.$('#start-button') === null)
  ok('a non-host has no sliders to move, only the values', !(await bob.$('#rounds')) && !(await bob.$('#drawtime')) && (await text(bob, '#rounds-value')) === '3')
  ok('the host has a Change settings button, a non-host does not', !!(await alice.$('#edit-settings')) && !(await bob.$('#edit-settings')))

  await setSetting(alice, 'rounds', 4); await setSetting(alice, 'drawtime', 90)
  ok('slider change reaches other players live', await until(async () => await text(bob, '#rounds-value') === '4' && await text(cara, '#drawtime-value') === '90s'))
  await bob.reload({ waitUntil: 'networkidle0' }); await bob.waitForSelector('#rounds-value')
  ok('settings persist on the server (visible after a refresh)', await text(bob, '#rounds-value') === '4')

  console.log('--- presence & grace period ---')
  await bob.close()
  ok('closed tab shows as "(away)" to others', await until(async () => (await list(alice)).some(l => l.startsWith('Bob') && l.includes('(away)')), 3000))
  ok('away player still has a seat during grace', (await list(alice)).length === 3)
  ok('start is blocked while only 2 are connected', await alice.$eval('#start-button', e => e.disabled) && await has(alice, 'Need 1 more player'))
  ok('after the grace period the ghost is removed', await until(async () => (await list(alice)).length === 2, 5000), JSON.stringify(await list(alice)))

  await cara.reload({ waitUntil: 'networkidle0' }); await cara.waitForSelector('#room-code')
  await wait(3500) // longer than the grace period
  ok('refreshing inside the grace period keeps your seat', (await list(alice)).length === 2 && (await list(cara)).length === 2 && !(await list(alice)).some(l => l.includes('(away)')), JSON.stringify(await list(alice)))

  console.log('--- leaving on purpose & host handover ---')
  const dan = await player(b, 'Dan', `${U}/room/${code}`)
  await until(async () => (await list(alice)).length === 3)
  const t0 = Date.now(); await click(dan, '← Leave')
  ok('Leave frees the seat immediately (no grace wait)', await until(async () => (await list(alice)).length === 2, 1500), (Date.now()-t0)+'ms')
  ok('leaver is back on the dashboard', await dan.waitForSelector('#code').then(() => true))

  await click(alice, '← Leave')
  ok('host leaving hands the host role to someone else', await until(async () => (await list(cara)).length === 1 && (await list(cara))[0].includes('(Host)'), 3000), JSON.stringify(await list(cara)))
  await click(cara, '← Leave'); await cara.waitForSelector('#code')
  const late = await player(b, 'Late').catch(() => null)
  await alice.waitForSelector('#code')
  await alice.type('#code', code); await alice.$eval('#code', e => e.focus()); await alice.keyboard.press('Enter')
  ok('when the last player leaves the room closes', await until(() => has(alice, 'No room with that code'), 3000))

  console.log('--- starting a game ---')
  const h = await player(b, 'Host'); const c2 = await text(h, '#room-code')
  const p2 = await player(b, 'Two', `${U}/room/${c2}`); const p3 = await player(b, 'Three', `${U}/room/${c2}`)
  await wait(600); await click(p2, "I'M READY"); await click(p3, "I'M READY")
  await until(() => h.$eval('#start-button', e => !e.disabled))
  await h.screenshot({ path: shots + '/lc-lobby-host.png' })
  await p2.screenshot({ path: shots + '/lc-lobby-guest.png' })
  await click(h, 'START GAME')
  ok('everyone sees the game start', await until(async () => (await Promise.all([h, p2, p3].map(p => p.$('#turn-banner')))).every(Boolean)))
  const late2 = await player(b, 'Late', `${U}/room/${c2}`).catch(() => null)
  ok('nobody can join a started game', late2 === null)
  await h.screenshot({ path: shots + '/lc-started.png' })

  const errs = [alice, cara, dan, h, p2, p3].flatMap(p => p.errs)
  ok('no page errors', errs.length === 0, errs.join('|'))
  console.log(fails ? `\n${fails} FAILED` : '\nALL PASSED')
  await b.close()
})().catch(e => { console.log('CRASH', e.message); process.exit(1) })
