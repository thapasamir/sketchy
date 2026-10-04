// Run with: npm run test:js
import test from 'node:test'
import assert from 'node:assert/strict'
import { noticesFor } from './notices.js'

const player = (id, extra = {}) => ({ id, name: id.toUpperCase(), connected: true, spectator: false, ...extra })
const room = (players, extra = {}) => ({ phase: 'lobby', host_id: 'a', players, result: null, ...extra })
const texts = list => list.map(n => n.text)

test('the first snapshot is not news', () => {
  assert.deepEqual(noticesFor(null, room([player('a')]), 'a'), [])
  assert.deepEqual(noticesFor(room([player('a')]), null, 'a'), [])
})

test('nothing changed, nothing to say', () => {
  const r = room([player('a'), player('b')])
  assert.deepEqual(noticesFor(r, r, 'a'), [])
})

test('someone joins the lobby', () => {
  const before = room([player('a')])
  const after = room([player('a'), player('b')])
  assert.deepEqual(noticesFor(before, after, 'a'), [{ text: 'B joined', kind: 'good' }])
})

test('you are not told about yourself', () => {
  assert.deepEqual(noticesFor(room([player('a')]), room([player('a'), player('b')]), 'b'), [])
})

test('someone who arrives mid-game is described as watching, not joining', () => {
  const before = room([player('a'), player('b')], { phase: 'drawing' })
  const after = room([player('a'), player('b'), player('c', { spectator: true })], { phase: 'drawing' })
  assert.deepEqual(texts(noticesFor(before, after, 'a')), ['C is watching'])
})

test('someone leaves', () => {
  const before = room([player('a'), player('b')])
  const after = room([player('a')])
  assert.deepEqual(noticesFor(before, after, 'a'), [{ text: 'B left', kind: 'warn' }])
})

test('someone loses their connection, and comes back', () => {
  const up = room([player('a'), player('b')])
  const down = room([player('a'), player('b', { connected: false })])
  assert.deepEqual(noticesFor(up, down, 'a'), [{ text: 'B lost their connection', kind: 'warn' }])
  assert.deepEqual(noticesFor(down, up, 'a'), [{ text: 'B is back', kind: 'good' }])
})

test('your own connection changing is not announced to you', () => {
  const up = room([player('a'), player('b')])
  const down = room([player('a', { connected: false }), player('b')])
  assert.deepEqual(noticesFor(up, down, 'a'), [])
})

test('a player who has just arrived is not also reported as "back"', () => {
  const before = room([player('a')])
  const after = room([player('a'), player('b', { connected: true })])
  assert.deepEqual(texts(noticesFor(before, after, 'a')), ['B joined'])
})

test('the imposter leaving mid-round says so, because the round ends there', () => {
  const before = room([player('a'), player('b'), player('c')], { phase: 'drawing' })
  const after = room([player('a'), player('c')], {
    phase: 'result',
    result: { outcome: 'imposter_left', imposter_id: 'b' },
  })
  assert.deepEqual(noticesFor(before, after, 'a'), [{ text: 'B left, and they were the imposter!', kind: 'warn' }])
})

test('someone else leaving mid-round is just "left" (no hint who the imposter is)', () => {
  const before = room([player('a'), player('b'), player('c')], { phase: 'drawing' })
  const after = room([player('a'), player('c')], { phase: 'drawing' })
  assert.deepEqual(texts(noticesFor(before, after, 'a')), ['B left'])
})

test('someone leaving AFTER the result is just "left", even if they were the imposter', () => {
  const result = { outcome: 'escaped', imposter_id: 'b' }
  const before = room([player('a'), player('b')], { phase: 'result', result })
  const after = room([player('a')], { phase: 'result', result })
  assert.deepEqual(texts(noticesFor(before, after, 'a')), ['B left'])
})

test('a spectator joining in at the start of a round', () => {
  const before = room([player('a'), player('c', { spectator: true })], { phase: 'result' })
  const after = room([player('a'), player('c', { spectator: false })], { phase: 'reveal' })
  assert.deepEqual(noticesFor(before, after, 'a'), [{ text: 'C joins in this round', kind: 'good' }])
})

test('a new host is announced', () => {
  const before = room([player('a'), player('b')], { host_id: 'a' })
  const after = room([player('b')], { host_id: 'b' })
  assert.deepEqual(texts(noticesFor(before, after, 'c')), ['A left', 'B is the host now'])
  assert.deepEqual(texts(noticesFor(before, after, 'b')), ['A left', 'You are the host now'])
})

test('several things at once are all reported', () => {
  const before = room([player('a'), player('b'), player('c')])
  const after = room([player('a'), player('b', { connected: false }), player('d')])
  assert.deepEqual(texts(noticesFor(before, after, 'a')), ['D joined', 'C left', 'B lost their connection'])
})
