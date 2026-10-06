// Signing in, staying signed in, and signing out: guests and registered players.
const wait = ms => new Promise(r => setTimeout(r, ms))
const { U, launch } = require('../lib/browser')
// exact-text match, so "Log in" never hits "Log in / Sign up"
const click = (p, t) => p.evaluate(t => { const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === t); if (!b) throw new Error('no button ' + t); b.click() }, t)
const body = p => p.evaluate(() => document.body.innerText.replace(/\s+/g, ' '))
const stored = p => p.evaluate(() => localStorage.getItem('sketchy:user'))
let fails = 0
const ok = (n, c, x = '') => { if (!c) fails++; console.log(c ? 'PASS' : 'FAIL', n, x) }
async function until(fn, ms = 5000) { const t = Date.now(); while (Date.now() - t < ms) { try { if (await fn()) return true } catch {} await wait(100) } return false }

;(async () => {
  const b = await launch()
  const p = await b.newPage(); const errs = []
  // (the one 401 the browser logs is the wrong password we type on purpose)
  p.on('pageerror', e => errs.push(e.message)); p.on('console', m => m.type() === 'error' && !/\b401\b/.test(m.text()) && errs.push(m.text()))
  let guestPosts = 0; p.on('request', r => r.url().endsWith('/api/users/guest') && guestPosts++)
  await p.goto(U + '/', { waitUntil: 'networkidle0' })

  console.log('--- a guest')
  await click(p, 'Play as Guest'); await p.waitForSelector('#name')
  const u1 = JSON.parse(await stored(p))
  ok('the guest is saved in the browser', u1?.userType === 'guest' && !!u1.userId)
  await p.type('#name', 'Alice'); await click(p, 'Create Room'); await p.waitForSelector('#room-code')
  ok('a guest can create a room', /^[A-Z]{4}$/.test(await p.$eval('#room-code', e => e.textContent.trim())))

  const code = await p.$eval('#room-code', e => e.textContent.trim())
  await p.goto(U + '/', { waitUntil: 'networkidle0' }); await p.waitForSelector('#home-rejoin')
  ok('the base address is the landing page, offering the way back to the room', (await body(p)).includes('Back to room ' + code))
  await p.click('#home-rejoin'); await p.waitForSelector('#room-code')
  ok('and that puts you back in your room', (await p.$eval('#room-code', e => e.textContent.trim())) === code)
  ok('as the same user, with no new guest made', JSON.parse(await stored(p)).userId === u1.userId && guestPosts === 1)

  await click(p, '← Leave'); await p.waitForSelector('#name')
  ok('leaving goes to the dashboard, not the landing page', (await body(p)).includes("Let's Play") && !(await body(p)).includes('Play as Guest'))
  await p.goto(U + '/', { waitUntil: 'networkidle0' }); await p.waitForSelector('#home-continue')
  ok('a refresh at the base address shows the landing page, with Continue', !(await body(p)).includes('Play as Guest'))
  await p.click('#home-continue'); await p.waitForSelector('#name')
  ok('and Continue opens the dashboard', (await body(p)).includes("Let's Play"))

  console.log('--- registering')
  const uname = 'user' + Date.now().toString().slice(-6)
  await click(p, 'Log in'); await click(p, 'New here? Create an account'); await p.waitForSelector('#reg-username')
  await p.type('#reg-username', uname); await p.type('#reg-email', uname + '@example.com'); await p.type('#reg-password', 'secret123')
  await click(p, 'Create Account')
  ok('registering signs in and remembers', await until(async () => (await body(p)).includes('Hi, ' + uname)) && JSON.parse(await stored(p)).username === uname)
  await click(p, 'Create Room'); await p.waitForSelector('#room-code')
  ok('a registered player can create a room, under their own name', true)

  console.log('--- signing out and back in')
  await p.goto(U + '/', { waitUntil: 'networkidle0' }); await p.waitForSelector('#home-rejoin'); await p.click('#home-rejoin'); await p.waitForSelector('#room-code')
  await click(p, '← Leave'); await p.waitForSelector('#code')
  ok('after a refresh and leaving, they are still signed in', (await body(p)).includes('Hi, ' + uname))
  await click(p, 'Log out'); await wait(300)
  ok('logging out forgets them and shows the landing page', (await stored(p)) === null && (await body(p)).includes('Play as Guest'))

  await click(p, 'Log in / Sign up'); await p.waitForSelector('#login-username')
  await p.type('#login-username', uname); await p.type('#login-password', 'wrongpass'); await click(p, 'Log In')
  ok('a wrong password shows an error', await until(async () => (await body(p)).includes('incorrect')))
  await p.$eval('#login-password', e => (e.value = '')); await p.type('#login-password', 'secret123'); await click(p, 'Log In')
  ok('the right password logs in', await until(async () => (await body(p)).includes('Hi, ' + uname)) && JSON.parse(await stored(p)).username === uname)

  ok('no console errors', errs.length === 0, errs.join(' | '))
  await b.close()
  console.log(fails ? `${fails} FAILED` : 'ALL PASSED'); process.exit(fails ? 1 : 0)
})().catch(e => { console.log('CRASH', e.message); process.exit(1) })
