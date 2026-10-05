import test from 'node:test'
import assert from 'node:assert/strict'
import { shareInvite } from './invite.js'

const invite = { code: 'ABCD', url: 'https://x.test/room/ABCD' }

// a stand-in browser: a clipboard that records, and a share sheet that does what the test says
function browser({ share, clipboard = async () => {} } = {}) {
  const copied = []
  Object.defineProperty(globalThis, 'navigator', {
    configurable: true,
    value: { share, clipboard: { writeText: async text => (copied.push(text), clipboard(text)) } },
  })
  return copied
}

test('a share sheet is used when the browser has one', async () => {
  const shared = []
  const copied = browser({ share: async data => shared.push(data) })
  assert.equal(await shareInvite(invite), 'shared')
  assert.deepEqual(shared[0], {
    title: 'Join my Sketchy game',
    text: 'Join my Sketchy game! Room code ABCD',
    url: invite.url,
  })
  assert.deepEqual(copied, [])
})

test('with no share sheet, the link is copied instead', async () => {
  const copied = browser({ share: undefined })
  assert.equal(await shareInvite(invite), 'copied')
  assert.deepEqual(copied, [invite.url])
})

test('closing the share sheet is not an error and copies nothing', async () => {
  const copied = browser({ share: async () => { throw new DOMException('closed', 'AbortError') } })
  assert.equal(await shareInvite(invite), 'cancelled')
  assert.deepEqual(copied, [])
})

test('a share sheet that fails falls back to copying the link', async () => {
  const copied = browser({ share: async () => { throw new DOMException('no', 'NotAllowedError') } })
  assert.equal(await shareInvite(invite), 'copied')
  assert.deepEqual(copied, [invite.url])
})
