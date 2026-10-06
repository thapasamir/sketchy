import test from 'node:test'
import assert from 'node:assert/strict'
import { shapePoints, isShape, TOOLS } from './shapes.js'

const box = points => {
  const xs = points.map(p => p[0])
  const ys = points.map(p => p[1])
  return [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)]
}

test('the pen is not a shape, the others are', () => {
  assert.deepEqual(TOOLS.map(t => t.id).filter(isShape), ['line', 'circle', 'box'])
  assert.equal(isShape('pen'), false)
})

test('a line runs from where it began to where it ended', () => {
  const pts = shapePoints('line', [0.1, 0.2], [0.9, 0.6])
  assert.deepEqual(pts[0], [0.1, 0.2])
  assert.deepEqual(pts.at(-1), [0.9, 0.6])
})

test('a box has its four corners and closes where it began', () => {
  const pts = shapePoints('box', [0.2, 0.3], [0.6, 0.7])
  assert.deepEqual(pts[0], pts.at(-1))
  for (const corner of [[0.6, 0.3], [0.6, 0.7], [0.2, 0.7]]) {
    assert.ok(pts.some(p => Math.abs(p[0] - corner[0]) < 1e-9 && Math.abs(p[1] - corner[1]) < 1e-9), String(corner))
  }
  assert.deepEqual(box(pts).map(n => Math.round(n * 100) / 100), [0.2, 0.3, 0.6, 0.7])
})

test('a circle fits the box dragged out, and closes', () => {
  const pts = shapePoints('circle', [0.2, 0.2], [0.8, 0.6])
  assert.deepEqual(box(pts).map(n => Math.round(n * 100) / 100), [0.2, 0.2, 0.8, 0.6])
  assert.ok(Math.hypot(pts[0][0] - pts.at(-1)[0], pts[0][1] - pts.at(-1)[1]) < 1e-9)
})

test('dragging the other way round gives the same shape', () => {
  const forward = box(shapePoints('circle', [0.2, 0.2], [0.8, 0.6]))
  const back = box(shapePoints('circle', [0.8, 0.6], [0.2, 0.2]))
  forward.forEach((n, i) => assert.ok(Math.abs(n - back[i]) < 1e-9))
})

test('a tap with no drag leaves a dot', () => {
  assert.deepEqual(shapePoints('box', [0.5, 0.5], [0.5, 0.5]), [[0.5, 0.5]])
})

test('a shape is a stroke the server will take: few points, all on the canvas', () => {
  for (const tool of ['line', 'circle', 'box']) {
    const pts = shapePoints(tool, [0, 0], [1, 1])
    assert.ok(pts.length > 1 && pts.length < 400, tool)
    assert.ok(pts.every(p => p.every(n => n >= -1e-9 && n <= 1 + 1e-9)), tool)
  }
})
