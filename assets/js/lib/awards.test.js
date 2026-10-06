import test from 'node:test'
import assert from 'node:assert/strict'
import { awards, recap, outcomeText, nameIn } from './awards.js'

const names = { a: 'Ann', b: 'Bob', c: 'Cy' }
const round = (n, imposter, outcome, votes = {}) => ({ round: n, imposter_id: imposter, outcome, votes, names, word: 'Kite', category: 'Toys', accused: null, points: {} })

test('outcomes have plain names', () => {
  assert.equal(outcomeText('caught'), 'Caught')
  assert.equal(outcomeText('escaped'), 'Got away')
  assert.equal(outcomeText('guessed'), 'Caught, but guessed the word')
  assert.equal(outcomeText('imposter_left'), 'The imposter left')
  assert.equal(outcomeText('something new'), 'Finished')
})

test('the recap has a line per round, with who the imposter was', () => {
  const lines = recap([round(1, 'a', 'caught'), round(2, 'b', 'escaped')])
  assert.deepEqual(lines.map(l => [l.round, l.imposterName, l.text, l.crewWon]), [
    [1, 'Ann', 'Caught', true],
    [2, 'Bob', 'Got away', false],
  ])
})

test('a player who has left is still named in the recap', () => {
  const lines = recap([{ ...round(1, 'z', 'caught'), names: { z: 'Zed' } }])
  assert.equal(lines[0].imposterName, 'Zed')
})

test('no rounds, no awards and no recap', () => {
  assert.deepEqual(awards([]), [])
  assert.deepEqual(recap([]), [])
})

test('"Master of disguise" goes to whoever got away most', () => {
  const found = awards([round(1, 'a', 'escaped'), round(2, 'a', 'escaped'), round(3, 'b', 'escaped')])
  const award = found.find(a => a.key === 'disguise')
  assert.deepEqual(award.ids, ['a'])
  assert.equal(award.count, 2)
})

test('nobody getting away means no such award', () => {
  assert.equal(awards([round(1, 'a', 'caught')]).some(a => a.key === 'disguise'), false)
})

test('"Sharpest eye" counts votes for the real imposter, across rounds', () => {
  const found = awards([
    round(1, 'a', 'caught', { b: 'a', c: 'b' }),
    round(2, 'b', 'caught', { a: 'c', c: 'b' }),
  ])
  const award = found.find(a => a.key === 'eye')
  // b voted for the imposter once; c voted for the imposter once (round 2)
  assert.deepEqual(award.ids.sort(), ['b', 'c'])
  assert.equal(award.count, 1)
})

test('a tie shares the award', () => {
  const found = awards([round(1, 'a', 'escaped'), round(2, 'b', 'escaped')])
  assert.deepEqual(found.find(a => a.key === 'disguise').ids.sort(), ['a', 'b'])
})

test('"Word thief" is for a caught imposter who guessed the word', () => {
  const found = awards([round(1, 'c', 'guessed', { a: 'c', b: 'c' })])
  assert.deepEqual(found.find(a => a.key === 'thief').ids, ['c'])
})

test('a vote for the wrong person earns nothing', () => {
  const found = awards([round(1, 'a', 'escaped', { b: 'c', c: 'b' })])
  assert.equal(found.some(a => a.key === 'eye'), false)
})

test('looking up a name finds it in any round', () => {
  assert.equal(nameIn([round(1, 'a', 'caught')], 'b'), 'Bob')
  assert.equal(nameIn([], 'b'), 'Someone')
})
