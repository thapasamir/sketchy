// Run with: npm run test:js
//
// These check the shape of what qr() draws. That the codes really DECODE was checked separately
// against an independent decoder (jsQR) over hundreds of inputs; see the commit message.
import test from 'node:test'
import assert from 'node:assert/strict'
import { qr, qrPath } from './qr.js'

const LINK = 'https://sketchy.example.com/room/ABCD'

test('the same text always gives the same code', () => {
  assert.deepEqual(qr(LINK).modules, qr(LINK).modules)
})

test('the size follows the version: 21 squares for version 1, and 4 more per version', () => {
  assert.equal(qr('hi').size, 21)
  assert.equal(qr('hi').version, 1)
  const big = qr('x'.repeat(100))
  assert.equal(big.size, big.version * 4 + 17)
})

test('longer text needs a bigger code', () => {
  assert.ok(qr('x'.repeat(80)).version > qr('x'.repeat(10)).version)
})

test('level M (more error correction) never fits more than level L in the same size', () => {
  for (const length of [10, 30, 60, 100, 150]) {
    assert.ok(qr('x'.repeat(length), 'M').version >= qr('x'.repeat(length), 'L').version)
  }
})

test('the three corner squares are there', () => {
  const { size, modules } = qr(LINK)
  // a finder square: a dark 7x7 ring, a light ring inside it, and a dark 3x3 centre
  const finder = (left, top) => {
    for (let y = 0; y < 7; y++) {
      for (let x = 0; x < 7; x++) {
        const ring = Math.max(Math.abs(x - 3), Math.abs(y - 3))
        const expected = ring !== 2
        assert.equal(modules[top + y][left + x], expected, `finder at ${left},${top}: ${x},${y}`)
      }
    }
  }
  finder(0, 0)
  finder(size - 7, 0)
  finder(0, size - 7)
})

test('there is no corner square in the fourth corner', () => {
  const { size, modules } = qr(LINK)
  const centre = modules[size - 4][size - 4]
  const ring = [modules[size - 7][size - 7], modules[size - 7][size - 1], modules[size - 1][size - 7]]
  // not a finder pattern: a finder would have a dark centre inside a light ring inside a dark ring
  assert.ok(!(centre && !modules[size - 6][size - 6] && modules[size - 7][size - 7] && ring.every(Boolean)))
})

test('the timing lines alternate dark and light between the corner squares', () => {
  const { size, modules } = qr(LINK)
  for (let i = 8; i < size - 8; i++) {
    assert.equal(modules[6][i], i % 2 === 0, `row 6, column ${i}`)
    assert.equal(modules[i][6], i % 2 === 0, `column 6, row ${i}`)
  }
})

test('the fixed dark square beside the bottom-left corner is dark', () => {
  const { size, modules } = qr(LINK)
  assert.equal(modules[size - 8][8], true)
})

test('about half the squares are dark (a lopsided code is hard to scan)', () => {
  const { size, modules } = qr(LINK)
  const dark = modules.flat().filter(Boolean).length
  const share = dark / (size * size)
  assert.ok(share > 0.35 && share < 0.65, `dark share ${share.toFixed(2)}`)
})

test('different text gives a different code', () => {
  assert.notDeepEqual(qr('https://a.example/room/ABCD').modules, qr('https://a.example/room/ABCE').modules)
})

test('any text works, as UTF-8 (so a character can take several bytes)', () => {
  assert.ok(qr('café').version >= 1)
  assert.ok(qr('🎨🎨🎨🎨🎨🎨🎨🎨🎨🎨🎨🎨').version > qr('aaaa').version)
})

test('text that is too long is refused rather than drawn wrongly', () => {
  assert.throws(() => qr('x'.repeat(400)), /too long/)
})

test('an unknown error-correction level is refused', () => {
  assert.throws(() => qr('hi', 'Z'), /unknown/)
})

test('qrPath draws one unit square per dark module, inside a quiet zone of 4', () => {
  const { size, modules } = qr(LINK)
  const { box, path } = qrPath(LINK)
  assert.equal(box, size + 8)
  assert.equal((path.match(/M/g) || []).length, modules.flat().filter(Boolean).length)
  // nothing is drawn inside the quiet zone
  for (const [, x, y] of path.matchAll(/M(\d+) (\d+)h1v1h-1z/g)) {
    assert.ok(+x >= 4 && +x < box - 4 && +y >= 4 && +y < box - 4)
  }
})
