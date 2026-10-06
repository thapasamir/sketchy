import test from 'node:test'
import assert from 'node:assert/strict'
import { createConnection } from './connection.js'

// timers we can step by hand
function clock() {
  let now = 0
  let next = 1
  const jobs = new Map()
  return {
    timers: {
      set: (fn, ms) => (jobs.set(next, { fn, at: now + ms }), next++),
      clear: id => jobs.delete(id),
    },
    advance(ms) {
      now += ms
      for (const [id, job] of [...jobs]) if (job.at <= now) (jobs.delete(id), job.fn())
    },
  }
}

function setup() {
  const c = clock()
  const seen = []
  const connection = createConnection({ onChange: s => seen.push(s), timers: c.timers })
  return { c, seen, connection }
}

test('a connected browser has nothing to say', () => {
  const { connection, seen } = setup()
  assert.equal(connection.state, 'online')
  assert.deepEqual(seen, [])
})

test('a blip that mends itself quickly never shows a banner', () => {
  const { c, connection, seen } = setup()
  connection.lost()
  c.advance(600)
  connection.restored()
  c.advance(5000)
  assert.deepEqual(seen, [])
  assert.equal(connection.state, 'online')
})

test('a drop that lasts says "offline"', () => {
  const { c, connection, seen } = setup()
  connection.lost()
  c.advance(1199)
  assert.equal(connection.state, 'online')
  c.advance(2)
  assert.deepEqual(seen, ['offline'])
})

test('coming back says "back" for a moment, then goes quiet', () => {
  const { c, connection, seen } = setup()
  connection.lost()
  c.advance(1300)
  connection.restored()
  assert.equal(connection.state, 'back')
  c.advance(2300)
  assert.deepEqual(seen, ['offline', 'back', 'online'])
})

test('dropping again while "back" is shown goes straight to waiting for the next drop', () => {
  const { c, connection, seen } = setup()
  connection.lost()
  c.advance(1300)
  connection.restored()
  connection.lost()
  assert.equal(connection.state, 'online')
  c.advance(1300)
  assert.deepEqual(seen, ['offline', 'back', 'online', 'offline'])
})

test('repeated "lost" reports do not stack timers', () => {
  const { c, connection, seen } = setup()
  connection.lost()
  connection.lost()
  connection.lost()
  c.advance(1300)
  assert.deepEqual(seen, ['offline'])
})

test('"restored" with nothing wrong is ignored', () => {
  const { connection, seen } = setup()
  connection.restored()
  assert.deepEqual(seen, [])
})

test('the phone saying it has a network again ends a drop that has not been shown yet', () => {
  const { c, connection, seen } = setup()
  connection.lost()
  c.advance(500)
  connection.networkUp()
  c.advance(5000)
  assert.deepEqual(seen, [])
})

test('but a banner already showing waits for the game itself to be reachable', () => {
  const { c, connection, seen } = setup()
  connection.lost()
  c.advance(1300)
  connection.networkUp()
  assert.equal(connection.state, 'offline')
  connection.restored()
  assert.deepEqual(seen, ['offline', 'back'])
  c.advance(0)
})

test('stopping cancels anything pending', () => {
  const { c, connection, seen } = setup()
  connection.lost()
  connection.stop()
  c.advance(5000)
  assert.deepEqual(seen, [])
})
