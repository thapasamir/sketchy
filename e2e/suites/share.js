const puppeteer = require('puppeteer-core')
const fs = require('fs')
const wait = ms => new Promise(r => setTimeout(r, ms))
const { U, launch } = require('../lib/browser')
const { fitsScreen } = require('../lib/layout')
// a real QR reader, to prove a phone could scan the code on screen
const JSQR = fs.readFileSync(require.resolve('jsqr/dist/jsQR.js'), 'utf8')
const click = (p, t) => p.evaluate(t => { const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === t); if (!b) throw new Error('no button "' + t + '"'); b.click() }, t)
const text = (p, sel) => p.$eval(sel, e => e.textContent.trim().replace(/\s+/g, ' ')).catch(() => null)
let fails = 0
const ok = (n, c, x = '') => { if (!c) fails++; console.log(c ? 'PASS' : 'FAIL', n, x) }
async function until(fn, ms = 6000) { const t = Date.now(); while (Date.now() - t < ms) { try { if (await fn()) return true } catch {} await wait(100) } return false }

// `shareMode`: 'record' (a working share sheet), 'cancel' (the person closes it), 'fail' (it errors), 'none' (no share sheet)
async function player(b, name, url = U + '/', { shareMode = 'record', vp = { width: 1200, height: 950 } } = {}) {
  const ctx = await b.createBrowserContext(); const p = await ctx.newPage(); await p.setViewport(vp)
  p.errs = []; p.on('pageerror', e => p.errs.push(e.message))
  await p.evaluateOnNewDocument(mode => {
    localStorage.setItem('sketchy:seen-how-to-play', 'true')
    window.__shared = []
    if (mode === 'none') { Object.defineProperty(navigator, 'share', { value: undefined, configurable: true }) }
    else navigator.share = async data => {
      window.__shared.push(data)
      if (mode === 'cancel') throw new DOMException('Share canceled', 'AbortError')
      if (mode === 'fail') throw new DOMException('not allowed', 'NotAllowedError')
    }
  }, shareMode)
  await p.goto(url, { waitUntil: 'networkidle0' })
  await click(p, 'Play as Guest'); await p.waitForSelector('#name'); await p.type('#name', name); await p.keyboard.press('Enter')
  await p.waitForSelector('#room-code'); p.name = name; return p
}

// read the QR code off the screen the way a phone would: draw it to pixels, then decode those
async function scan(p) {
  await p.addScriptTag({ content: JSQR })
  return p.evaluate(async () => {
    const svg = document.querySelector('#qr-panel svg')
    const xml = new XMLSerializer().serializeToString(svg)
    const img = new Image(); img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(xml)
    await img.decode()
    const px = 480; const c = document.createElement('canvas'); c.width = c.height = px
    const ctx = c.getContext('2d'); ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, px, px); ctx.drawImage(img, 0, 0, px, px)
    const data = ctx.getImageData(0, 0, px, px)
    const found = jsQR(data.data, px, px)
    return found ? found.data : null
  })
}

;(async () => {
  const b = await launch()
  const shots = process.argv[2]

  console.log('=== the share button')
  const host = await player(b, 'Host'); const code = await text(host, '#room-code')
  const link = `${U}/room/${code}`
  ok('there is a Share button and a QR button', !!(await host.$('#share-button')) && !!(await host.$('#qr-toggle')))
  await host.click('#share-button'); await wait(300)
  const shared = await host.evaluate(() => window.__shared)
  ok('Share opens the phone\'s share sheet, once', shared.length === 1)
  ok('with the invite link', shared[0]?.url === link, shared[0]?.url)
  ok('and a message that has the room code in it', new RegExp(code).test(shared[0]?.text || '') && !!shared[0]?.title, JSON.stringify(shared[0]))
  ok('nothing was copied: the share sheet handled it', !/Copied/.test(await text(host, 'body')))

  console.log('--- closing the share sheet is not an error')
  {
    const h = await player(b, 'Cancel', U + '/', { shareMode: 'cancel' })
    await h.click('#share-button'); await wait(400)
    ok('cancelling does nothing (no "Copied!" and no error)', !/Copied/.test(await text(h, 'body')) && h.errs.length === 0)
    await h.close()
  }
  console.log('--- a share sheet that fails falls back to copying')
  {
    const h = await player(b, 'Fail', U + '/', { shareMode: 'fail' })
    await h.click('#share-button'); await wait(400)
    ok('the link is copied instead', /Copied!/.test(await text(h, 'body')))
    await h.close()
  }
  console.log('--- a browser with no share sheet (most desktops)')
  {
    const h = await player(b, 'Plain', U + '/', { shareMode: 'none' })
    await h.click('#share-button'); await wait(400)
    ok('Share copies the link', /Copied!/.test(await text(h, 'body')))
    await h.close()
  }

  console.log('=== the QR code')
  ok('it is hidden until asked for', !(await host.$('#qr-panel')))
  await host.click('#qr-toggle'); await host.waitForSelector('#qr-panel svg')
  ok('the button says what it does now', (await text(host, '#qr-toggle')) === 'Hide QR code' && (await host.$eval('#qr-toggle', e => e.getAttribute('aria-expanded'))) === 'true')
  ok('it has a description for screen readers, with the room code', new RegExp(code).test(await host.$eval('#qr-panel svg', e => e.getAttribute('aria-label'))))
  const box = await host.$eval('#qr-panel svg', e => { const r = e.getBoundingClientRect(); return { w: r.width, h: r.height } })
  ok('it is big enough to scan from across a table (200px+) and square', box.w >= 200 && Math.abs(box.w - box.h) < 2, `${box.w}x${box.h}`)
  const decoded = await scan(host)
  ok('scanning it gives exactly the invite link', decoded === link, String(decoded))
  await host.screenshot({ path: shots + '/sh-qr.png' })

  console.log('--- and the link it holds really gets a friend in')
  const friend = await player(b, 'Friend', decoded)
  ok('opening the scanned link puts them in the same room', await until(async () => (await text(friend, '#room-code')) === code, 4000))
  ok('and the host sees them arrive', await until(async () => (await host.$$eval('#player-list li', e => e.length)) === 2, 4000))
  ok('hiding the QR code works', await (async () => { await host.click('#qr-toggle'); await wait(200); return !(await host.$('#qr-panel')) })())

  console.log('=== a phone')
  {
    const PHONE = { width: 390, height: 844, deviceScaleFactor: 2, hasTouch: true, isMobile: true }
    const ph = await player(b, 'Phone', U + '/', { vp: PHONE })
    const c = await text(ph, '#room-code')
    await ph.tap('#qr-toggle'); await ph.waitForSelector('#qr-panel svg')
    const fit = await fitsScreen(ph)
    ok('nothing sticks out sideways with the QR code open', fit.ok, fit.offenders.join(', '))
    ok('the buttons are easy to tap (44px)', await ph.$$eval('#share-button, #qr-toggle', els => els.every(e => e.getBoundingClientRect().height >= 44)))
    ok('the QR code on a phone screen still scans', (await scan(ph)) === `${U}/room/${c}`)
    await ph.evaluate(() => document.querySelector('#qr-panel').scrollIntoView({ block: 'center' })); await ph.screenshot({ path: shots + '/sh-phone.png' })
  }

  const errs = [host, friend].flatMap(p => p.errs); ok('no page errors', errs.length === 0, errs.join('|'))
  console.log(fails ? `\n${fails} FAILED` : '\nALL PASSED'); await b.close()
})().catch(e => { console.log('CRASH', e.stack); process.exit(1) })
