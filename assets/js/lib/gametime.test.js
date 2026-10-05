import test from 'node:test'
import assert from 'node:assert/strict'
import { turnsPerWord, maxGameSeconds, describeLength, paceOf, ROUND_EXTRAS } from './gametime.js'

const extras = Object.values(ROUND_EXTRAS).reduce((a, b) => a + b, 0)

test('a word takes every player\'s turns, for each lap', () => {
  assert.equal(turnsPerWord(3, 2), 6)
  assert.equal(turnsPerWord(5, 1), 5)
})

test('a lone player, or no laps given, still counts as one turn', () => {
  assert.equal(turnsPerWord(1, 1), 1)
  assert.equal(turnsPerWord(0, 0), 1)
  assert.equal(turnsPerWord(3, undefined), 3)
})

test('a game is its rounds, each the drawing plus the fixed parts', () => {
  const seconds = maxGameSeconds({ rounds: 3, drawTime: 30, players: 3, lapsNow: 2 })
  assert.equal(seconds, 3 * (6 * 30 + extras))
})

test('more rounds, longer turns or more players all make it longer', () => {
  const base = { rounds: 3, drawTime: 30, players: 3, lapsNow: 2 }
  const length = o => maxGameSeconds({ ...base, ...o })
  assert.ok(length({ rounds: 4 }) > length({}))
  assert.ok(length({ drawTime: 60 }) > length({}))
  assert.ok(length({ players: 5 }) > length({}))
  assert.ok(length({ lapsNow: 1 }) < length({}))
})

test('it is said in whole minutes', () => {
  assert.equal(describeLength(13 * 60 + 15), 'up to about 13 minutes')
  assert.equal(describeLength(13 * 60 + 40), 'up to about 14 minutes')
})

test('never "0 minutes", and "1 minute" is singular', () => {
  assert.equal(describeLength(5), 'up to about 1 minute')
  assert.equal(describeLength(60), 'up to about 1 minute')
})

test('turn lengths have a name', () => {
  assert.equal(paceOf(30), 'Quick')
  assert.equal(paceOf(40), 'Quick')
  assert.equal(paceOf(60), 'Relaxed')
  assert.equal(paceOf(90), 'Slow and careful')
})
