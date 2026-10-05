const puppeteer = require('puppeteer-core')
const wait = ms => new Promise(r => setTimeout(r, ms))
const click = (p, t) => p.evaluate(t => { const b=[...document.querySelectorAll('button')].find(x => x.textContent.trim()===t); if(!b) throw new Error('no button '+t); b.click() }, t)
const body = p => p.evaluate(() => document.body.innerText.replace(/\s+/g,' '))
const { playerRows: list } = require('../lib/lobby')
const ok = (n, c, extra='') => console.log(c ? 'PASS' : 'FAIL', n, extra)
const { U, launch } = require('../lib/browser')
const URL = U + '/'
async function guest(b, w=1100, h=800) {
  const p = await b.newPage(); await p.setViewport({ width: w, height: h })
  const errs = []; p.on('pageerror', e => errs.push(e.message))
  await p.evaluateOnNewDocument(() => localStorage.setItem('sketchy:seen-how-to-play', 'true'))
  await p.evaluateOnNewDocument(() => localStorage.setItem('sketchy:seen-how-to-play', 'true'))
  await p.goto(URL, { waitUntil: 'networkidle0' }); await click(p, 'Play as Guest'); await p.waitForSelector('#name')
  p.errs = errs; return p
}
;(async () => {
  // separate contexts = separate localStorage, like two different people's browsers
  const b = await launch()
  const host = await guest(await b.createBrowserContext())
  await host.type('#name', 'Samir'); await click(host, 'Create Room'); await host.waitForSelector('#room-code')
  const code = await host.$eval('#room-code', e => e.textContent.trim())
  ok('host created room', /^[A-Z]{4}$/.test(code), code)

  const friend = await guest(await b.createBrowserContext(), 390, 844)
  await friend.type('#name', 'Priya'); await friend.type('#code', code.toLowerCase()); await click(friend, 'Join')
  await friend.waitForSelector('#room-code')
  ok('friend joined with lowercase code', (await friend.$eval('#room-code', e => e.textContent.trim())) === code)
  ok('friend sees both players', JSON.stringify(await list(friend)).includes('Samir') && JSON.stringify(await list(friend)).includes('Priya'), JSON.stringify(await list(friend)))

  await wait(500) // NO reload on host
  const hostList = await list(host)
  ok('HOST lobby updated live (no refresh)', hostList.length === 2 && hostList[1].startsWith('Priya'), JSON.stringify(hostList))
  ok('host marked as host, friend as you', hostList[0].includes('(Host)') && (await list(friend))[1].includes('(You)'))

  const third = await guest(await b.createBrowserContext())
  await third.type('#name', 'samir'); await third.type('#code', code); await click(third, 'Join'); await wait(600)
  ok('duplicate name rejected with message', (await body(third)).includes('already has that name'))
  await third.$eval('#name', e => e.value = ''); await third.type('#name', 'Dev'); await third.$eval('#code', e => e.value = ''); await third.type('#code', 'ZZZZ'); await click(third, 'Join'); await wait(600)
  ok('unknown code rejected with message', (await body(third)).includes('No room with that code'))
  await third.$eval('#code', e => e.value = ''); await third.type('#code', 'AB'); await click(third, 'Join'); await wait(200)
  ok('short code rejected before any request', (await body(third)).includes('4 letters'))
  await third.$eval('#code', e => e.value = ''); await third.type('#code', code); await click(third, 'Join'); await third.waitForSelector('#room-code')
  await wait(500)
  ok('third joins; everyone now sees 3', (await list(host)).length === 3 && (await list(friend)).length === 3 && (await list(third)).length === 3)
  await friend.screenshot({ path: process.argv[2] + '/join-lobby-phone.png' })
  await host.screenshot({ path: process.argv[2] + '/join-lobby-desktop.png' })
  const lonely = await guest(await b.createBrowserContext())
  await lonely.screenshot({ path: process.argv[2] + '/join-form-desktop.png' })
  const errs = [...host.errs, ...friend.errs, ...third.errs]
  ok('no page errors', errs.length === 0, errs.join('|'))
  await b.close()
})().catch(e => { console.log('CRASH', e.message); process.exit(1) })
