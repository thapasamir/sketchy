// Run with: npm run test:js
import test from 'node:test'
import assert from 'node:assert/strict'
import { append, load, save, clear } from './chatlog.js'

const msg = (id, text = 'hi', extra = {}) => ({ id, player_id: 'p1', name: 'Ann', text, at: 1000 + id, ...extra })

// a stand-in for the browser's sessionStorage
function fakeStorage(initial = {}) {
  const data = { ...initial }
  globalThis.sessionStorage = {
    getItem: k => (k in data ? data[k] : null),
    setItem: (k, v) => void (data[k] = String(v)),
    removeItem: k => void delete data[k],
  }
  return data
}

test('append adds a message at the end', () => {
  assert.deepEqual(append([msg(1)], msg(2)).map(m => m.id), [1, 2])
})

test('append ignores a message it already has', () => {
  const list = [msg(1), msg(2)]
  assert.equal(append(list, msg(2)), list)
})

test('a new message that reuses an old id (a restarted server) is still kept', () => {
  const list = [msg(1)]
  assert.equal(append(list, msg(1, 'later', { at: 99999 })).length, 2)
})

test('append keeps only the most recent messages', () => {
  let list = []
  for (let i = 1; i <= 150; i++) list = append(list, msg(i))
  assert.equal(list.length, 100)
  assert.equal(list[0].id, 51)
  assert.equal(list.at(-1).id, 150)
})

test('append does not change the list it was given', () => {
  const list = [msg(1)]
  append(list, msg(2))
  assert.equal(list.length, 1)
})

test('what is saved comes back after a refresh', () => {
  fakeStorage()
  save('ABCD', 'p1', [msg(1, 'hello'), msg(2, 'world')])
  assert.deepEqual(load('ABCD', 'p1').map(m => m.text), ['hello', 'world'])
})

test('each room and each seat has its own conversation', () => {
  fakeStorage()
  save('ABCD', 'p1', [msg(1, 'in ABCD')])
  assert.deepEqual(load('WXYZ', 'p1'), [])
  assert.deepEqual(load('ABCD', 'p2'), [])
})

test('clear forgets it', () => {
  fakeStorage()
  save('ABCD', 'p1', [msg(1)])
  clear('ABCD', 'p1')
  assert.deepEqual(load('ABCD', 'p1'), [])
})

test('nothing saved is an empty conversation', () => {
  fakeStorage()
  assert.deepEqual(load('ABCD', 'p1'), [])
})

test('storage that holds junk is not trusted: only well-formed messages come back', () => {
  const junk = JSON.stringify([msg(1, 'good'), null, 'text', 7, { id: 'x' }, { ...msg(2), text: 42 }, { ...msg(3), at: 'soon' }, msg(4, 'also good')])
  fakeStorage({ 'sketchy:chat:ABCD:p1': junk })
  assert.deepEqual(load('ABCD', 'p1').map(m => m.text), ['good', 'also good'])
})

test('storage that is not even JSON, or not a list, is an empty conversation', () => {
  fakeStorage({ 'sketchy:chat:ABCD:p1': '{not json' })
  assert.deepEqual(load('ABCD', 'p1'), [])
  fakeStorage({ 'sketchy:chat:ABCD:p1': JSON.stringify({ a: 1 }) })
  assert.deepEqual(load('ABCD', 'p1'), [])
})

test('blocked storage never throws: the chat just forgets', () => {
  globalThis.sessionStorage = {
    getItem() {
      throw new Error('blocked')
    },
    setItem() {
      throw new Error('blocked')
    },
    removeItem() {
      throw new Error('blocked')
    },
  }
  assert.doesNotThrow(() => save('ABCD', 'p1', [msg(1)]))
  assert.deepEqual(load('ABCD', 'p1'), [])
  assert.doesNotThrow(() => clear('ABCD', 'p1'))
})

test('no sessionStorage at all (an old browser) is fine too', () => {
  delete globalThis.sessionStorage
  assert.doesNotThrow(() => save('ABCD', 'p1', [msg(1)]))
  assert.deepEqual(load('ABCD', 'p1'), [])
})
