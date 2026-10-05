import test from 'node:test'
import assert from 'node:assert/strict'
import { progress, whenMine } from './progress.js'

const order = ['a', 'b', 'c']
const at = (player_id, lap, laps, playerId) => progress({ order, laps, turn: { player_id, lap }, playerId })

test('the first turn', () => {
  const p = at('a', 1, 2, 'c')
  assert.equal(p.number, 1)
  assert.equal(p.total, 6)
  assert.deepEqual(p.slots.map(s => s.state), ['now', 'next', 'next', 'next', 'next', 'next'])
  assert.equal(p.upNext, 'b')
})

test('the second lap counts on from the first', () => {
  const p = at('b', 2, 2, 'a')
  assert.equal(p.number, 5)
  assert.deepEqual(p.slots.map(s => s.state), ['done', 'done', 'done', 'done', 'now', 'next'])
  assert.equal(p.upNext, 'c')
})

test('the last turn has nobody next', () => {
  const p = at('c', 2, 2, 'a')
  assert.equal(p.number, 6)
  assert.equal(p.upNext, null)
})

test('one lap', () => {
  assert.equal(at('b', 1, 1, 'a').total, 3)
})

test('how far away my turn is', () => {
  assert.equal(at('a', 1, 2, 'a').turnsUntilMe, 0)
  assert.equal(at('a', 1, 2, 'b').turnsUntilMe, 1)
  assert.equal(at('a', 1, 2, 'c').turnsUntilMe, 2)
})

test('in the first lap my next turn can be in the second lap', () => {
  // c has just drawn in lap 1; I am a, and I am next, in lap 2
  assert.equal(at('c', 1, 2, 'a').turnsUntilMe, 1)
})

test('when I have no turn left', () => {
  assert.equal(at('c', 2, 2, 'a').turnsUntilMe, null)
  assert.equal(at('b', 1, 1, 'a').turnsUntilMe, null)
})

test('someone watching has no turns', () => {
  assert.equal(at('a', 1, 2, 'late').turnsUntilMe, null)
})

test('nothing when no one is drawing, or the drawer is not in the order', () => {
  assert.equal(progress({ order, laps: 2, turn: null, playerId: 'a' }), null)
  assert.equal(progress({ order: [], laps: 2, turn: { player_id: 'a', lap: 1 }, playerId: 'a' }), null)
  assert.equal(at('zzz', 1, 2, 'a'), null)
})

test('the words', () => {
  assert.equal(whenMine(0), "It's your turn.")
  assert.equal(whenMine(1), "You're up next.")
  assert.equal(whenMine(3), "You're up in 3 turns.")
  assert.equal(whenMine(null), "You've drawn all your turns.")
})
