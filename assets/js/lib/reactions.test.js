import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { REACTIONS, emojiFor, show, MAX_SHOWN } from './reactions.js'

test('every reaction has a picture and a label, and no two share an id', () => {
  assert.equal(new Set(REACTIONS.map(r => r.id)).size, REACTIONS.length)
  for (const r of REACTIONS) assert.ok(r.emoji && r.label, r.id)
})

test('the ids match the ones the server accepts', () => {
  const server = readFileSync(new URL('../../../lib/backend/rooms/reactions.ex', import.meta.url), 'utf8')
  const ids = server.match(/@ids ~w\(([^)]*)\)/)[1].split(/\s+/)
  assert.deepEqual(REACTIONS.map(r => r.id), ids)
})

test('a name the list does not know has no picture', () => {
  assert.equal(emojiFor('laugh'), '😂')
  assert.equal(emojiFor('<script>'), null)
  assert.equal(emojiFor(undefined), null)
})

test('a reaction arrives with its picture, its sender and a place to float from', () => {
  const [one] = show([], { id: 'fire', name: 'Bob' }, 1, () => 0.5)
  assert.deepEqual(one, { key: 1, emoji: '🔥', name: 'Bob', x: 50 })
})

test('it floats up from inside the picture, never at the very edge', () => {
  assert.equal(show([], { id: 'fire' }, 1, () => 0)[0].x, 8)
  assert.equal(show([], { id: 'fire' }, 1, () => 1)[0].x, 92)
})

test('something that is not a known reaction is ignored', () => {
  const current = show([], { id: 'laugh', name: 'A' }, 1)
  assert.equal(show(current, { id: 'giraffe', name: 'B' }, 2), current)
  assert.equal(show(current, null, 3), current)
})

test('the oldest make way when too many are showing', () => {
  let list = []
  for (let i = 0; i < MAX_SHOWN + 5; i++) list = show(list, { id: 'clap', name: 'A' }, i)
  assert.equal(list.length, MAX_SHOWN)
  assert.equal(list[0].key, 5)
  assert.equal(list.at(-1).key, MAX_SHOWN + 4)
})

test('the earlier list is not changed', () => {
  const before = show([], { id: 'laugh', name: 'A' }, 1)
  show(before, { id: 'fire', name: 'B' }, 2)
  assert.equal(before.length, 1)
})
