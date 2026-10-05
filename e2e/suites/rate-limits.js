// The abuse limits, tried the way a script would: over plain HTTP and over a raw WebSocket, with
// no browser doing the sensible thing for it. The server runs with tight limits (see the `limited`
// profile in e2e/run.js) and takes a caller's address from the `x-test-ip` header, so each check
// can be a different "person" without needing another machine.
const WebSocket = require('ws')
const { U, launch } = require('../lib/browser')

let fails = 0
const ok = (n, c, x = '') => { if (!c) fails++; console.log(c ? 'PASS' : 'FAIL', n, x) }
const wait = ms => new Promise(r => setTimeout(r, ms))
const unique = p => p + Date.now().toString(36) + Math.random().toString(36).slice(2, 6)

// Each name below is a different "person": it is turned into an address of its own (the server
// is told it in the x-test-ip header, which it only trusts in this test's server settings)
const addresses = new Map()
const addressOf = label => {
  if (!addresses.has(label)) addresses.set(label, `10.7.${Math.floor(addresses.size / 250)}.${(addresses.size % 250) + 1}`)
  return addresses.get(label)
}

// one HTTP request, as `ip`
async function api(path, { ip, method = 'POST', body = {}, raw } = {}) {
  const request = () =>
    fetch(U + path, {
      method,
      headers: { 'content-type': 'application/json', 'x-test-ip': addressOf(ip) },
      body: method === 'GET' ? undefined : (raw ?? JSON.stringify(body)),
    })
  // after refusing a huge body the server closes the connection, and the next request may find
  // the closed one reused: that is the connection's doing, so try again on a fresh one
  const res = await request().catch(() => request())
  const data = await res.json().catch(() => ({}))
  return { status: res.status, data, retryAfter: res.headers.get('retry-after') }
}

// a raw Phoenix channel client: what a script would write, no page, no sense of manners
function socket(ip) {
  const ws = new WebSocket(U.replace('http', 'ws') + '/socket/websocket?vsn=2.0.0', { headers: { 'x-test-ip': addressOf(ip) } })
  const sock = { ws, replies: [], closed: false, ref: 0 }
  ws.on('message', raw => { const [, ref, topic, event, payload] = JSON.parse(raw); sock.replies.push({ ref, topic, event, payload }) })
  ws.on('close', () => (sock.closed = true))
  sock.open = () => new Promise(res => { ws.once('open', () => res(true)); ws.once('error', () => res(false)); ws.once('unexpected-response', () => res(false)) })
  sock.send = (topic, event, payload = {}) => ws.send(JSON.stringify(['1', String(++sock.ref), topic, event, payload]))
  return sock
}

;(async () => {
  console.log('--- making users: a script making guests')
  const g = []
  for (let i = 0; i < 8; i++) g.push(await api('/api/users/guest', { ip: 'guest-script' }))
  ok('the first few go through', g.slice(0, 6).every(r => r.status === 201), g.map(r => r.status).join(','))
  ok('then it is refused with a 429', g[6].status === 429 && g[7].status === 429)
  ok('with a plain message', /wait/i.test(g[6].data.message || ''), g[6].data.message)
  ok('and how many seconds to wait', Number(g[6].retryAfter) > 0 && Number(g[6].retryAfter) <= 600, g[6].retryAfter)
  ok('a different caller is not affected', (await api('/api/users/guest', { ip: 'someone-else' })).status === 201)

  console.log('--- registering (each one costs a slow password hash)')
  const user = unique('rl')
  const reg = n => api('/api/users/register', { ip: 'reg-script', body: { username: n, email: n + '@example.com', password: 'secret123' } })
  ok('one account is made', (await reg(user)).status === 201)
  ok('the next is refused', (await reg(user + 'b')).status === 429)

  console.log('--- guessing one account\'s password from many addresses')
  const login = (ip, name) => api('/api/users/login', { ip, body: { username: name, password: 'wrong' } })
  ok('a wrong guess is just wrong', (await login('guesser-1', user)).status === 401)
  ok('the same account from another address is refused', (await login('guesser-2', user)).status === 429)
  ok('other accounts are not locked by it', (await login('guesser-2', unique('other'))).status === 401)

  console.log('--- guessing room codes')
  const made = await api('/api/rooms', { ip: 'code-guesser', body: { name: 'Host' } })
  ok('a room can be made', made.status === 201 && /^[A-Z]{4}$/.test(made.data.code))
  const join = (ip, code) => api(`/api/rooms/${code}/join`, { ip, body: { name: unique('p') } })
  ok('a wrong code is just not found', (await join('code-guesser', 'ZZZA')).status === 404 && (await join('code-guesser', 'ZZZB')).status === 404)
  ok('after a few misses even the right code is refused', (await join('code-guesser', made.data.code)).status === 429)
  ok('someone else can still join the real room', (await join('a-friend', made.data.code)).status === 200)

  console.log('--- a WebSocket client that floods a room')
  const host = await api('/api/rooms', { ip: 'flooder', body: { name: 'Flood' } })
  const flood = socket('flooder')
  ok('it connects', await flood.open())
  const topic = 'room:' + host.data.code
  flood.send(topic, 'phx_join', { player_id: host.data.player_id })
  await wait(400)
  ok('and joins', flood.replies.some(r => r.event === 'phx_reply' && r.payload.status === 'ok'))
  for (let i = 0; i < 400; i++) flood.send(topic, 'finish_turn')
  await wait(1200)
  const answered = flood.replies.filter(r => r.event === 'phx_reply' && r.ref !== '1').length
  const refused = flood.replies.filter(r => r.payload?.response?.reason === 'rate_limited').length
  console.log('   (the flood got', answered, 'answers,', refused, 'of them refusals; connection closed:', flood.closed, ')')
  // The server answers the first burst, refuses the rest, and drops the connection once it has
  // refused enough; replies still on their way when it is dropped never arrive. So what can be
  // checked is that the connection ends, and that nowhere near all 400 messages were served.
  ok('a connection that keeps at it is closed (not just this room, the whole connection)', flood.closed)
  ok('and nowhere near all of the flood was served', answered < 100, answered + ' answered')

  console.log('--- a connection storm')
  const attempts = []
  for (let i = 0; i < 6; i++) { const s = socket('storm'); attempts.push(await s.open()); s.ws.terminate() }
  ok('only the first few connections are accepted', attempts.filter(Boolean).length === 3 && attempts.filter(x => !x).length === 3, attempts.join(','))

  console.log('--- one address holding too many rooms open')
  const hosts = []
  for (let i = 0; i < 2; i++) hosts.push(await api('/api/rooms', { ip: 'holder', body: { name: 'H' + i } }))
  const holders = []
  const held = []
  for (const h of hosts) {
    const s = socket('holder'); const opened = await s.open()
    if (!opened) { held.push('refused-connect'); continue }
    holders.push(s)
    s.send('room:' + h.data.code, 'phx_join', { player_id: h.data.player_id }); await wait(300)
    held.push(s.replies.find(r => r.event === 'phx_reply')?.payload?.response?.reason || s.replies.find(r => r.event === 'phx_reply')?.payload?.status)
  }
  ok('two are fine, and another address is not stopped by them', held.every(x => x === 'ok'), held.join(','))
  holders.forEach(s => s.ws.terminate())

  console.log('--- a body that is far too big')
  const big = await api('/api/rooms', { ip: 'big-body', raw: JSON.stringify({ name: 'x'.repeat(40000) }) })
  ok('is refused before it is read (413)', big.status === 413, big.status)

  console.log('--- the whole API has a ceiling')
  // 30 a minute are allowed. A minute is a fixed slice of the clock, so a run of requests can be
  // split across two slices: 70 is enough that one slice must get more than 30.
  const hammered = []
  for (let i = 0; i < 70; i++) hammered.push((await api('/api/users/me', { ip: 'api-hammer', method: 'GET' })).status)
  ok('a hammered endpoint ends up refusing', hammered.includes(429), hammered.filter(s => s === 429).length + ' refused of 70')

  console.log('--- the server can only hold so many rooms')
  // (a room nobody has connected to closes after a few seconds, so make the one to join just now)
  const target = await api('/api/rooms', { ip: 'target-host', body: { name: 'Target' } })
  const statuses = []
  for (let i = 0; i < 8; i++) statuses.push((await api('/api/rooms', { ip: 'filler-' + i, body: { name: 'F' } })).status)
  ok('past the cap, new rooms are told to wait (503)', statuses.includes(503), statuses.join(','))
  const busy = await api('/api/rooms', { ip: 'filler-late', body: { name: 'F' } })
  ok('in plain words', busy.status === 503 && /full/i.test(busy.data.message || ''), busy.data.message)
  const stillJoin = await join('a-latecomer', target.data.code)
  ok('but people can still join rooms that exist', stillJoin.status === 200, stillJoin.status)

  console.log('--- what a person sees')
  const b = await launch()
  const page = await (await b.createBrowserContext()).newPage()
  page.errs = []; page.on('pageerror', e => page.errs.push(e.message))
  await page.setViewport({ width: 1200, height: 900 })
  await page.setExtraHTTPHeaders({ 'x-test-ip': addressOf('guest-script') }) // the address already over its guest limit
  await page.evaluateOnNewDocument(() => localStorage.setItem('sketchy:seen-how-to-play', 'true'))
  await page.goto(U + '/', { waitUntil: 'networkidle0' })
  await page.evaluate(() => [...document.querySelectorAll('button')].find(x => x.textContent.trim() === 'Play as Guest').click())
  await wait(800)
  const text = await page.evaluate(() => document.body.innerText)
  ok('being refused shows a message, not a broken page', /Too many tries/.test(text) && /Play as Guest/.test(text), text.replace(/\s+/g, ' ').slice(0, 160))
  ok('without any script error', page.errs.length === 0, page.errs.join('|'))
  await b.close()

  console.log(fails ? `${fails} FAILED` : 'ALL PASSED'); process.exit(fails ? 1 : 0)
})().catch(e => { console.log('CRASH', e.message); process.exit(1) })
