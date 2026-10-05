import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { COUNTS, PARTS, NAMES, cycle, normalizeAvatar, randomAvatar, withPart, loadAvatar, saveAvatar } from './avatar.js'

test('every choice has a name, and the names differ', () => {
  for (const part of PARTS) {
    assert.equal(NAMES[part].length, COUNTS[part], part)
    assert.equal(new Set(NAMES[part]).size, COUNTS[part], part)
  }
})

test('the first hat is no hat', () => {
  assert.equal(NAMES.hat[0], 'None')
})

test('stepping forward and back goes round', () => {
  assert.equal(cycle(0, 8, 1), 1)
  assert.equal(cycle(7, 8, 1), 0)
  assert.equal(cycle(0, 8, -1), 7)
  assert.equal(cycle(3, 8, -1), 2)
})

test('stepping all the way round comes back to where you were', () => {
  let index = 5
  for (let i = 0; i < 8; i++) index = cycle(index, 8, 1)
  assert.equal(index, 5)
})

// a stand-in for the browser's storage
function storage() {
  const data = new Map()
  Object.defineProperty(globalThis, 'localStorage', {
    configurable: true,
    value: { getItem: k => data.get(k) ?? null, setItem: (k, v) => data.set(k, v), removeItem: k => data.delete(k) },
  })
  return data
}

test('the counts are the same as the server\'s', () => {
  const server = readFileSync(new URL('../../../lib/backend/avatar.ex', import.meta.url), 'utf8')
  const [, eyes, mouth, hat] = server.match(/@counts %\{eyes: (\d+), mouth: (\d+), hat: (\d+)\}/)
  assert.deepEqual(COUNTS, { eyes: Number(eyes), mouth: Number(mouth), hat: Number(hat) })
})

test('a face is three numbers in range', () => {
  assert.deepEqual(normalizeAvatar({ eyes: 1, mouth: 2, hat: 3 }), { eyes: 1, mouth: 2, hat: 3 })
  const last = Object.fromEntries(PARTS.map(p => [p, COUNTS[p] - 1]))
  assert.deepEqual(normalizeAvatar(last), last)
})

test('anything else is not a face', () => {
  const ok = { eyes: 0, mouth: 0, hat: 0 }
  for (const bad of [null, undefined, 5, 'face', [], {}, { ...ok, eyes: -1 }, { ...ok, hat: COUNTS.hat }, { ...ok, mouth: 1.5 }, { ...ok, eyes: '1' }, { eyes: 0, mouth: 0 }])
    assert.equal(normalizeAvatar(bad), null, JSON.stringify(bad))
})

test('extra things are dropped', () => {
  assert.deepEqual(normalizeAvatar({ eyes: 0, mouth: 0, hat: 0, url: 'x' }), { eyes: 0, mouth: 0, hat: 0 })
})

test('a random face is always a valid one, and they vary', () => {
  const seen = new Set()
  for (let i = 0; i < 300; i++) {
    const face = randomAvatar()
    assert.ok(normalizeAvatar(face))
    seen.add(JSON.stringify(face))
  }
  assert.ok(seen.size > 100)
})

test('the ends of each range can be reached', () => {
  assert.deepEqual(randomAvatar(() => 0), { eyes: 0, mouth: 0, hat: 0 })
  assert.deepEqual(randomAvatar(() => 0.9999), { eyes: COUNTS.eyes - 1, mouth: COUNTS.mouth - 1, hat: COUNTS.hat - 1 })
})

test('changing one part leaves the rest', () => {
  const face = { eyes: 1, mouth: 2, hat: 3 }
  assert.deepEqual(withPart(face, 'mouth', 7), { eyes: 1, mouth: 7, hat: 3 })
  assert.deepEqual(face, { eyes: 1, mouth: 2, hat: 3 })
})

test('a face you choose is remembered', () => {
  storage()
  saveAvatar({ eyes: 4, mouth: 5, hat: 6 })
  assert.deepEqual(loadAvatar(), { eyes: 4, mouth: 5, hat: 6 })
})

test('someone who has never chosen gets a random face, and keeps it', () => {
  storage()
  const first = loadAvatar()
  assert.ok(normalizeAvatar(first))
  assert.deepEqual(loadAvatar(), first)
})

test('a damaged saved face is replaced, not used', () => {
  const data = storage()
  data.set('sketchy:avatar', JSON.stringify({ eyes: 99, mouth: 0, hat: 0 }))
  assert.ok(normalizeAvatar(loadAvatar()))
})

test('saving something that is not a face does nothing', () => {
  storage()
  saveAvatar({ eyes: 3, mouth: 3, hat: 3 })
  saveAvatar({ eyes: 99 })
  assert.deepEqual(loadAvatar(), { eyes: 3, mouth: 3, hat: 3 })
})

test('storage that is blocked does not break it', () => {
  Object.defineProperty(globalThis, 'localStorage', {
    configurable: true,
    value: { getItem: () => { throw new Error('blocked') }, setItem: () => { throw new Error('blocked') } },
  })
  assert.ok(normalizeAvatar(loadAvatar()))
})
