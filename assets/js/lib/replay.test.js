import test from 'node:test'
import assert from 'node:assert/strict'
import { timeline, shownAt, MIN_MS, MAX_MS, GAP_MS } from './replay.js'

const stroke = n => ({ points: Array.from({ length: n }, (_, i) => [i / n, 0.5]) })

test('a small drawing still takes a few seconds to watch', () => {
  const plan = timeline([stroke(10)])
  assert.equal(Math.round(plan.total), MIN_MS)
})

test('a huge drawing does not take forever', () => {
  const plan = timeline(Array.from({ length: 30 }, () => stroke(2000)))
  assert.ok(plan.total <= MAX_MS + 1, plan.total)
})

test('strokes come one after another with a beat between them', () => {
  const { items } = timeline([stroke(100), stroke(100), stroke(100)])
  assert.equal(items[0].start, 0)
  assert.ok(Math.abs(items[1].start - (items[0].duration + GAP_MS)) < 1e-6)
  assert.ok(Math.abs(items[2].start - (items[1].start + items[1].duration + GAP_MS)) < 1e-6)
})

test('at the start the first stroke has begun, with its first point', () => {
  const plan = timeline([stroke(100), stroke(100)])
  assert.deepEqual(shownAt(plan, 0), { done: 0, current: 0, count: 1, finished: false })
})

test('partway through a stroke, part of its points show', () => {
  const plan = timeline([stroke(100), stroke(100)])
  const half = shownAt(plan, plan.items[0].duration / 2)
  assert.equal(half.current, 0)
  assert.ok(half.count > 40 && half.count < 60, half.count)
})

test('in the beat between strokes the first is done and none is current', () => {
  const plan = timeline([stroke(100), stroke(100)])
  const between = shownAt(plan, plan.items[0].duration + GAP_MS / 2)
  assert.deepEqual(between, { done: 1, current: null, count: 0, finished: false })
})

test('the second stroke is drawn after the first is done', () => {
  const plan = timeline([stroke(100), stroke(100)])
  const second = shownAt(plan, plan.items[1].start + 1)
  assert.equal(second.done, 1)
  assert.equal(second.current, 1)
})

test('at the end everything is done', () => {
  const plan = timeline([stroke(100), stroke(100)])
  assert.deepEqual(shownAt(plan, plan.total + 5), { done: 2, current: null, count: 0, finished: true })
})

test('a drawing with nothing in it is finished at once', () => {
  assert.equal(shownAt(timeline([]), 0).finished, true)
})
