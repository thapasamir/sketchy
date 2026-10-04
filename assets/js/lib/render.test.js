import test from 'node:test'
import assert from 'node:assert/strict'
import { strokeAt, shapePoints, SHAPE_NAMES, drawMarker } from './render.js'

const stroke = (id, points, size = 1) => ({ id, player_id: id, color: '#000', size, points })

test('a tap on a line finds that stroke', () => {
  const a = stroke('a', [[0.1, 0.5], [0.9, 0.5]])
  assert.equal(strokeAt([a], [0.5, 0.5], 400, 400)?.id, 'a')
})

test('a tap a fingertip away still finds it, and one far away finds nothing', () => {
  const a = stroke('a', [[0.1, 0.5], [0.9, 0.5]])
  assert.equal(strokeAt([a], [0.5, 0.5 + 10 / 400], 400, 400)?.id, 'a')
  assert.equal(strokeAt([a], [0.5, 0.8], 400, 400), null)
})

test('the nearest of several strokes wins', () => {
  const a = stroke('a', [[0.1, 0.4], [0.9, 0.4]])
  const b = stroke('b', [[0.1, 0.45], [0.9, 0.45]])
  assert.equal(strokeAt([a, b], [0.5, 0.44], 400, 400)?.id, 'b')
  assert.equal(strokeAt([a, b], [0.5, 0.41], 400, 400)?.id, 'a')
})

test('when two strokes cross, the one drawn last is on top', () => {
  const a = stroke('a', [[0.1, 0.5], [0.9, 0.5]])
  const b = stroke('b', [[0.5, 0.1], [0.5, 0.9]])
  assert.equal(strokeAt([a, b], [0.5, 0.5], 400, 400)?.id, 'b')
  assert.equal(strokeAt([b, a], [0.5, 0.5], 400, 400)?.id, 'a')
})

test('a dot (a tap with no movement) can be found', () => {
  const dot = stroke('d', [[0.3, 0.3]])
  assert.equal(strokeAt([dot], [0.3, 0.3], 400, 400)?.id, 'd')
  assert.equal(strokeAt([dot], [0.6, 0.6], 400, 400), null)
})

test('a fat brush is easier to hit than a thin one', () => {
  const thin = stroke('t', [[0.1, 0.5], [0.9, 0.5]], 1)
  const fat = stroke('f', [[0.1, 0.5], [0.9, 0.5]], 3)
  const offset = [0.5, 0.5 + 18 / 800]
  assert.equal(strokeAt([thin], offset, 800, 800), null)
  assert.equal(strokeAt([fat], offset, 800, 800)?.id, 'f')
})

test('an empty picture, or a stroke with no points, finds nothing', () => {
  assert.equal(strokeAt([], [0.5, 0.5], 400, 400), null)
  assert.equal(strokeAt([stroke('x', [])], [0.5, 0.5], 400, 400), null)
})

test('the hit-test works the same on a small canvas and a big one', () => {
  const a = stroke('a', [[0.2, 0.2], [0.8, 0.8]])
  assert.equal(strokeAt([a], [0.5, 0.5], 200, 200)?.id, 'a')
  assert.equal(strokeAt([a], [0.5, 0.5], 1000, 1000)?.id, 'a')
})

test('there are eight shapes, all different, and the corners stay inside the unit circle', () => {
  assert.equal(SHAPE_NAMES.length, 8)
  const seen = new Set(SHAPE_NAMES.map(n => JSON.stringify(shapePoints(n))))
  assert.equal(seen.size, 8)
  for (const name of SHAPE_NAMES)
    for (const [x, y] of shapePoints(name) ?? []) assert.ok(Math.hypot(x, y) <= 1.0001, name)
})

test('the names match the server\'s order', () => {
  assert.deepEqual(SHAPE_NAMES, ['circle', 'square', 'triangle', 'diamond', 'star', 'plus', 'hexagon', 'cross'])
})

test('an unknown shape is a circle', () => {
  assert.equal(shapePoints('blob'), null)
})

test('drawMarker paints a corner for every point of the shape', () => {
  for (const name of SHAPE_NAMES) {
    const calls = []
    const ctx = new Proxy({}, { get: (_, k) => (...args) => calls.push([k, ...args]), set: () => true })
    drawMarker(ctx, name, 50, 50, 10, '#f00')
    const corners = shapePoints(name)?.length ?? 0
    assert.equal(calls.filter(c => c[0] === 'moveTo' || c[0] === 'lineTo').length, corners, name)
    assert.ok(calls.some(c => c[0] === 'fill') && calls.some(c => c[0] === 'stroke'), name)
  }
})
