import test from 'node:test'
import assert from 'node:assert/strict'
import { bodyPath, roundedPolygon, smoothClosed } from './blob.js'
import { SHAPE_NAMES } from './render.js'

const numbers = d => (d.match(/-?\d+(\.\d+)?/g) || []).map(Number)

test('every shape has an outline, a closed path', () => {
  for (const shape of SHAPE_NAMES) {
    const d = bodyPath(shape)
    assert.match(d, /^M/, shape)
    assert.match(d, /Z$/, shape)
  }
})

test('the same shape always gets the same outline', () => {
  for (const shape of SHAPE_NAMES) assert.equal(bodyPath(shape), bodyPath(shape))
})

test('different shapes have different outlines', () => {
  assert.equal(new Set(SHAPE_NAMES.map(bodyPath)).size, SHAPE_NAMES.length)
})

test('a seed gives a round body its own wobble, the same every time', () => {
  assert.equal(bodyPath('circle', 'ann'), bodyPath('circle', 'ann'))
  assert.notEqual(bodyPath('circle', 'ann'), bodyPath('circle', 'bob'))
  assert.notEqual(bodyPath('circle', 'ann'), bodyPath('circle'))
})

test('a seeded body is still round and inside the area it is drawn in', () => {
  for (const seed of ['a', 'b', 'c', 'player-12', 'zz9'])
    for (const n of numbers(bodyPath('circle', seed))) assert.ok(Math.abs(n) <= 1.12, `${seed}: ${n}`)
})

test('an unknown shape is drawn as the circle', () => {
  assert.equal(bodyPath('blob'), bodyPath('circle'))
})

test('no outline strays outside the area a body is drawn in', () => {
  for (const shape of SHAPE_NAMES) for (const n of numbers(bodyPath(shape))) assert.ok(Math.abs(n) <= 1.12, `${shape}: ${n}`)
})

test('the circle is not a perfect circle', () => {
  // the points of a perfect circle are all exactly 1 from the middle; these are not
  const d = bodyPath('circle')
  const values = numbers(d)
  const radii = []
  for (let i = 0; i + 1 < values.length; i += 2) radii.push(Math.hypot(values[i], values[i + 1]))
  assert.ok(Math.max(...radii) - Math.min(...radii) > 0.04)
})

test('a rounded polygon replaces each corner with a curve', () => {
  const square = [[-1, -1], [1, -1], [1, 1], [-1, 1]]
  const d = roundedPolygon(square, 0.25)
  assert.equal((d.match(/Q/g) || []).length, 4)
  // the sharp corner itself is only the control point of a curve, never a point the line goes to
  assert.ok(!d.includes('L-1 -1') && !d.includes('L1 1'))
})

test('a smooth closed curve has one piece for each point', () => {
  const d = smoothClosed([[0, -1], [1, 0], [0, 1], [-1, 0]])
  assert.equal((d.match(/C/g) || []).length, 4)
})
