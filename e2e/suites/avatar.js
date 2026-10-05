// Choosing a face (eyes, mouth, hat) with the arrows, having it remembered, seeing other people's,
// and changing yours in the lobby.
const { U, launch } = require('../lib/browser')
const { fitsScreen } = require('../lib/layout')

const wait = ms => new Promise(r => setTimeout(r, ms))
const click = (p, t) => p.evaluate(t => { const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === t); if (!b) throw new Error('no button "' + t + '"'); b.click() }, t)
const text = (p, sel) => p.$eval(sel, e => e.textContent.trim().replace(/\s+/g, ' ')).catch(() => null)
let fails = 0
const ok = (n, c, x = '') => { if (!c) fails++; console.log(c ? 'PASS' : 'FAIL', n, x) }
async function until(fn, ms = 6000) { const t = Date.now(); while (Date.now() - t < ms) { try { if (await fn()) return true } catch {} await wait(100) } return false }

// the drawing of a marker, as text: two faces are the same face if this is the same
const drawing = (p, sel) => p.$eval(sel, e => e.innerHTML)
// (each drawn part is marked with its number, so a test doesn't depend on how it is drawn)
const CROWN = 'data-hat="2"'
const TOP_HAT = 'data-hat="4"'
const SUNGLASSES = 'data-eyes="6"'

// how many choices there are of each part: the server's own list
const COUNTS = (() => {
  const source = require('node:fs').readFileSync(require('node:path').join(__dirname, '../../lib/backend/avatar.ex'), 'utf8')
  const [, eyes, mouth, hat] = source.match(/@counts %\{eyes: (\d+), mouth: (\d+), hat: (\d+)\}/)
  return { eyes: Number(eyes), mouth: Number(mouth), hat: Number(hat) }
})()

// which choice of a part the editor is on, and going there with the "next" arrow
const index = (p, part) => p.$eval(`#avatar-${part}-value`, e => Number(e.dataset.index))
async function setPart(p, part, target) {
  for (let i = 0; i < COUNTS[part] && (await index(p, part)) !== target; i++) await p.click(`#avatar-${part}-next`)
}

async function newPage(b, vp = { width: 1200, height: 950 }) {
  const ctx = await b.createBrowserContext(); const p = await ctx.newPage(); await p.setViewport(vp)
  p.errs = []; p.on('pageerror', e => p.errs.push(e.message))
  await p.evaluateOnNewDocument(() => localStorage.setItem('sketchy:seen-how-to-play', 'true'))
  return p
}
async function guest(p, url = U + '/') {
  await p.goto(url, { waitUntil: 'networkidle0' })
  await click(p, 'Play as Guest'); await p.waitForSelector('#name')
}
async function enter(p, name) {
  await p.type('#name', name); await p.keyboard.press('Enter'); await p.waitForSelector('#room-code')
}

;(async () => {
  const b = await launch()

  console.log('--- before joining')
  const host = await newPage(b)
  await guest(host)
  ok('there is a "Your look" row with a face already on it', !!(await host.$('#avatar-open')) && (await host.$eval('[data-marker][data-faced="true"]', e => true).catch(() => false)))
  await host.click('#avatar-open'); await host.waitForSelector('#avatar-dialog')
  ok('each of eyes, mouth and hat has a back and a forward arrow, and says what it is on',
    await host.evaluate(() => ['eyes', 'mouth', 'hat'].every(p => document.querySelector(`#avatar-${p}-prev`) && document.querySelector(`#avatar-${p}-next`) && document.querySelector(`#avatar-${p}-value`).textContent.trim().length > 1)))
  ok('the editor needs no scrolling on a normal screen', await host.$eval('#avatar-dialog [class*="overflow-y-auto"]', e => e.scrollHeight <= e.clientHeight + 1))

  // start from a known face
  await setPart(host, 'hat', 0); await setPart(host, 'eyes', 0)
  const before = await drawing(host, '#avatar-preview')
  ok('with no hat there is no crown', !before.includes(CROWN) && (await text(host, '#avatar-hat-value')) === 'None')
  await host.click('#avatar-hat-next'); await host.click('#avatar-hat-next')
  ok('two steps forward is the crown, and it says so', (await text(host, '#avatar-hat-value')) === 'Crown' && (await drawing(host, '#avatar-preview')).includes(CROWN))
  await host.click('#avatar-eyes-prev'); await host.click('#avatar-eyes-prev')
  // (eyes 0 is Dots; two steps back goes round to the end, not to Shades)
  ok('stepping back from the first goes round to the last', (await index(host, 'eyes')) === COUNTS.eyes - 2)
  await setPart(host, 'eyes', 6)
  ok('Shades are eyes number 6, and the preview shows them', (await text(host, '#avatar-eyes-value')) === 'Shades' && (await drawing(host, '#avatar-preview')).includes(SUNGLASSES))
  ok('choosing changes the preview', (await drawing(host, '#avatar-preview')) !== before)
  const start = await index(host, 'mouth')
  for (let i = 0; i < COUNTS.mouth; i++) await host.click('#avatar-mouth-next')
  ok(`${COUNTS.mouth} steps forward comes back to where it started`, (await index(host, 'mouth')) === start)
  const picked = await drawing(host, '#avatar-preview')
  let shuffled = false
  for (let i = 0; i < 4 && !shuffled; i++) { await host.click('#avatar-shuffle'); shuffled = (await drawing(host, '#avatar-preview')) !== picked }
  ok('shuffle gives another face', shuffled)
  await setPart(host, 'hat', 2); await setPart(host, 'eyes', 6)
  const chosen = await drawing(host, '#avatar-preview')
  await host.keyboard.press('Escape')
  ok('Escape closes it', await until(async () => !(await host.$('#avatar-dialog'))))

  console.log('--- remembered')
  await host.reload({ waitUntil: 'networkidle0' }); await host.waitForSelector('#avatar-open')
  await host.click('#avatar-open'); await host.waitForSelector('#avatar-dialog')
  ok('after a refresh it is the same face', (await drawing(host, '#avatar-preview')) === chosen)
  await click(host, 'Done')

  console.log('--- in a room')
  await enter(host, 'Host')
  const code = await text(host, '#room-code')
  ok('your marker in the player list is a face with the crown', (await drawing(host, '#edit-avatar')).includes(CROWN))
  ok('and it is still assigned the shape the game gave you (used on the drawing)', (await host.$eval('#edit-avatar [data-marker]', e => e.dataset.marker)) === 'circle')

  const friend = await newPage(b)
  await guest(friend, `${U}/room/${code}`)
  await friend.click('#avatar-open'); await friend.waitForSelector('#avatar-dialog')
  await setPart(friend, 'hat', 4); await setPart(friend, 'mouth', 4)
  await click(friend, 'Done'); await enter(friend, 'Friend')
  await until(async () => (await host.$$eval('#player-list li', e => e.length)) === 2)

  const seenByHost = await host.$$eval('#player-list li', lis => lis.map(li => ({ name: li.dataset.player, svg: li.querySelector('[data-marker]').innerHTML })))
  const friendOnHost = seenByHost.find(p => p.name === 'Friend')
  ok('the host sees the friend\'s face, with the top hat', !!friendOnHost && friendOnHost.svg.includes(TOP_HAT))
  ok('and it is not the same as the host\'s', friendOnHost.svg !== seenByHost.find(p => p.name === 'Host').svg)
  const hostOnFriend = await friend.$$eval('#player-list li', lis => lis.find(li => li.dataset.player === 'Host').querySelector('[data-marker]').innerHTML)
  ok('the friend sees the host\'s crown', hostOnFriend.includes(CROWN))
  ok('the friend is assigned a different shape from the host (for the drawing)', (await friend.$eval('#edit-avatar [data-marker]', e => e.dataset.marker)) !== 'circle')
  ok('but both are drawn as the same kind of round character, not as their shape', !friendOnHost.svg.includes('<polygon') && !hostOnFriend.includes('<polygon') && friendOnHost.svg.includes('<path'))
  ok('and no two bodies are exactly alike', friendOnHost.svg !== seenByHost.find(p => p.name === 'Host').svg)

  console.log('--- changing it in the lobby')
  await host.click('#edit-avatar'); await host.waitForSelector('#avatar-dialog')
  await setPart(host, 'hat', 4)
  ok('the host\'s own preview updates', await until(async () => (await drawing(host, '#avatar-preview')).includes(TOP_HAT)))
  ok('and the friend sees it change live', await until(async () => (await friend.$$eval('#player-list li', lis => lis.find(li => li.dataset.player === 'Host').querySelector('[data-marker]').innerHTML)).includes(TOP_HAT)))
  await click(host, 'Done')
  ok('Done closes it', !(await host.$('#avatar-dialog')))

  console.log('--- the chat shows faces too')
  await friend.type('#chat-input', 'nice hat'); await friend.keyboard.press('Enter')
  ok('a message from the friend has their face by it', await until(async () => (await host.$$eval('#chat-log [data-chat-from="Friend"] [data-faced="true"]', e => e.length)) >= 1))

  console.log('--- on a phone')
  const phone = await newPage(b, { width: 390, height: 844, deviceScaleFactor: 2, hasTouch: true, isMobile: true })
  await guest(phone)
  const fitBefore = await fitsScreen(phone)
  ok('the dashboard with the look row fits', fitBefore.ok, fitBefore.offenders.join(', '))
  await phone.click('#avatar-open'); await phone.waitForSelector('#avatar-dialog'); await wait(400)
  const fit = await fitsScreen(phone)
  ok('and so does the editor', fit.ok, fit.offenders.join(', '))
  ok('and it needs no scrolling on a phone either', await phone.$eval('#avatar-dialog [class*="overflow-y-auto"]', e => e.scrollHeight <= e.clientHeight + 1))
  const arrows = await phone.$$eval('[id$="-prev"], [id$="-next"]', els => els.map(e => { const r = e.getBoundingClientRect(); return `${e.id} ${Math.round(r.width * 10) / 10}x${Math.round(r.height * 10) / 10}` }))
  ok('every arrow is big enough to tap', arrows.length === 6 && arrows.every(a => { const [w, h] = a.split(' ')[1].split('x').map(Number); return w >= 43.9 && h >= 43.9 }), arrows.join(', '))
  const was = await index(phone, 'hat')
  await phone.tap('#avatar-hat-next')
  ok('tapping on a phone works', (await index(phone, 'hat')) === (was + 1) % COUNTS.hat)

  console.log('--- a bad face sent to the server is not used, and does not break joining')
  const res = await fetch(U + '/api/rooms', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ name: 'Sneaky', avatar: { eyes: 99, mouth: -1, hat: 'x', url: 'http://x' } }) })
  ok('a room is still made', res.status === 201, res.status)

  const errs = [host, friend, phone].flatMap(p => p.errs)
  ok('no page errors', errs.length === 0, errs.join('|'))
  await b.close()
  console.log(fails ? `${fails} FAILED` : 'ALL PASSED')
  process.exit(fails ? 1 : 0)
})().catch(e => { console.log('CRASH', e.stack); process.exit(1) })
