import test from 'node:test'
import assert from 'node:assert/strict'
import { urgencyOf, fractionLeft } from './countdown.js'

const at = (secondsLeft, totalMs = 30_000, phase = 'drawing') => urgencyOf({ phase, secondsLeft, totalMs })

test('plenty of time is calm', () => {
  assert.equal(at(30), 'calm')
  assert.equal(at(25), 'calm')
})

test('the last 10 seconds of a short turn warn', () => {
  assert.equal(at(11), 'calm')
  assert.equal(at(10), 'warn')
  assert.equal(at(6), 'warn')
})

test('the last 5 seconds are urgent, and 0 too', () => {
  assert.equal(at(5), 'urgent')
  assert.equal(at(1), 'urgent')
  assert.equal(at(0), 'urgent')
})

test('a long turn warns earlier: with the last quarter', () => {
  // a quarter of 90 seconds is 22.5, so from 23 seconds left
  assert.equal(at(24, 90_000), 'calm')
  assert.equal(at(23, 90_000), 'warn')
})

test('the vote and the guess are timed the same way', () => {
  assert.equal(at(8, 60_000, 'voting'), 'warn')
  assert.equal(at(3, 60_000, 'guess'), 'urgent')
})

test('the wait between rounds never turns alarming', () => {
  assert.equal(at(2, 20_000, 'result'), 'calm')
})

test('the share left stays between 0 and 1', () => {
  assert.equal(fractionLeft(15_000, 30_000), 0.5)
  assert.equal(fractionLeft(-5, 30_000), 0)
  assert.equal(fractionLeft(40_000, 30_000), 1)
  assert.equal(fractionLeft(5, 0), 1)
})
