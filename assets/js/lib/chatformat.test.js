import test from 'node:test'
import assert from 'node:assert/strict'
import { groupMessages, timeLabel, GROUP_GAP_MS } from './chatformat.js'

const msg = (player_id, at, text = 'x') => ({ id: `${player_id}${at}`, player_id, at, text })

test('a single message is its own group', () => {
  const [m] = groupMessages([msg('a', 0)])
  assert.equal(m.first, true)
  assert.equal(m.last, true)
})

test('messages from one person in a row form one group', () => {
  const [one, two, three] = groupMessages([msg('a', 0), msg('a', 1000), msg('a', 2000)])
  assert.deepEqual([one.first, one.last], [true, false])
  assert.deepEqual([two.first, two.last], [false, false])
  assert.deepEqual([three.first, three.last], [false, true])
})

test('a different speaker starts a new group, and ends the one before', () => {
  const [a, b] = groupMessages([msg('a', 0), msg('b', 1000)])
  assert.deepEqual([a.first, a.last], [true, true])
  assert.deepEqual([b.first, b.last], [true, true])
})

test('taking turns makes every message its own group', () => {
  const rows = groupMessages([msg('a', 0), msg('b', 1), msg('a', 2), msg('b', 3)])
  assert.ok(rows.every(r => r.first && r.last))
})

test('the same person after a long pause starts a new group', () => {
  const [one, two] = groupMessages([msg('a', 0), msg('a', GROUP_GAP_MS + 1)])
  assert.equal(one.last, true)
  assert.equal(two.first, true)
})

test('just inside the pause it is still one group', () => {
  const [one, two] = groupMessages([msg('a', 0), msg('a', GROUP_GAP_MS)])
  assert.equal(one.last, false)
  assert.equal(two.first, false)
})

test('an interruption splits what would have been one group', () => {
  const rows = groupMessages([msg('a', 0), msg('a', 1), msg('b', 2), msg('a', 3)])
  assert.deepEqual(rows.map(r => [r.first, r.last]), [[true, false], [false, true], [true, true], [true, true]])
})

test('no messages, no groups', () => {
  assert.deepEqual(groupMessages([]), [])
})

test('the messages themselves are not changed', () => {
  const original = [msg('a', 0), msg('a', 1)]
  groupMessages(original)
  assert.equal('first' in original[0], false)
})

test('the time is hours and minutes', () => {
  assert.match(timeLabel(Date.UTC(2026, 0, 1, 14, 32), 'en-GB'), /\d{2}:\d{2}/)
})
