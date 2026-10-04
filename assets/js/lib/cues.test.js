// Run with: npm run test:js
import test from 'node:test'
import assert from 'node:assert/strict'
import { cuesFor, resultSound, tickFor, TIMING } from './cues.js'

const players = n => Array.from({ length: n }, (_, i) => ({ id: `p${i}` }))
const room = (phase, extra = {}) => ({ phase, players: players(3), turn: null, result: null, final: null, ...extra })
const names = cues => cues.map(c => c.name)

test('the first snapshot is not an event: joining or refreshing is silent', () => {
  assert.deepEqual(cuesFor(null, room('drawing', { turn: { player_id: 'p0', n: 1 } }), 'p0'), [])
  assert.deepEqual(cuesFor(room('lobby'), null, 'p0'), [])
})

test('a player joining the lobby pops; leaving, or the same list, is silent', () => {
  assert.deepEqual(names(cuesFor(room('lobby', { players: players(2) }), room('lobby', { players: players(3) }), 'p0')), ['pop'])
  assert.deepEqual(cuesFor(room('lobby', { players: players(3) }), room('lobby', { players: players(2) }), 'p0'), [])
  assert.deepEqual(cuesFor(room('lobby'), room('lobby'), 'p0'), [])
})

test('the reveal flips the card, and an imposter also gets the stamp, timed to land with the animation', () => {
  const crew = cuesFor(room('lobby'), room('reveal'), 'p0', { role: 'crew' })
  assert.deepEqual(crew, [{ name: 'flip' }])

  const imposter = cuesFor(room('lobby'), room('reveal'), 'p1', { role: 'imposter' })
  assert.deepEqual(imposter, [{ name: 'flip' }, { name: 'stamp', delay: TIMING.stampImpact }])
})

test('a later round flips too', () => {
  assert.deepEqual(names(cuesFor(room('result'), room('reveal'), 'p0', { role: 'crew' })), ['flip'])
})

test('your turn chimes, and asks for attention; someone else\'s turn is silent', () => {
  const first = room('drawing', { turn: { player_id: 'p0', n: 1 } })
  const second = room('drawing', { turn: { player_id: 'p1', n: 2 } })

  assert.deepEqual(cuesFor(room('reveal'), first, 'p0'), [{ name: 'turn', attention: true }])
  assert.deepEqual(cuesFor(room('reveal'), first, 'p1'), [])
  assert.deepEqual(cuesFor(first, second, 'p1'), [{ name: 'turn', attention: true }])
  assert.deepEqual(cuesFor(first, second, 'p2'), [])
})

test('every one of your turns chimes, even if it is yours twice running (others skipped)', () => {
  const a = room('drawing', { turn: { player_id: 'p0', n: 1 } })
  const b = room('drawing', { turn: { player_id: 'p0', n: 2 } })
  assert.deepEqual(cuesFor(a, b, 'p0'), [{ name: 'turn', attention: true }])
})

test('the turn chime plays once per turn, not on every update during it', () => {
  const mine = room('drawing', { turn: { player_id: 'p0', n: 1 } })
  assert.deepEqual(cuesFor(mine, { ...mine, players: players(3) }, 'p0'), [])
})

test('voting opens with a bell and a caught imposter gets the sting', () => {
  assert.deepEqual(names(cuesFor(room('drawing'), room('voting'), 'p0')), ['bell'])
  assert.deepEqual(names(cuesFor(room('voting'), room('guess'), 'p0')), ['caught'])
})

test('the result sound waits for the imposter\'s name to land', () => {
  const result = { outcome: 'caught', imposter_id: 'p1' }
  const [cue] = cuesFor(room('voting'), room('result', { result }), 'p0')
  assert.equal(cue.delay, TIMING.nameImpact)
})

test('every outcome sounds right for each side', () => {
  const sound = (outcome, me) => resultSound({ outcome, imposter_id: 'p1' }, me)

  // the imposter got away
  assert.equal(sound('escaped', 'p1'), 'win')
  assert.equal(sound('escaped', 'p0'), 'lose')
  // the imposter was caught
  assert.equal(sound('caught', 'p1'), 'lose')
  assert.equal(sound('caught', 'p0'), 'win')
  // caught, but they guessed the word
  assert.equal(sound('guessed', 'p1'), 'win')
  assert.equal(sound('guessed', 'p0'), 'bell')
  // the imposter left
  assert.equal(sound('imposter_left', 'p0'), 'win')
  assert.equal(sound('imposter_left', 'p1'), 'lose')
})

test('the final: fanfare for a winner (including in a tie), a soft end for everyone else', () => {
  const final = room('final', { final: { winner_ids: ['p0', 'p1'] } })
  assert.deepEqual(names(cuesFor(room('result'), final, 'p0')), ['fanfare'])
  assert.deepEqual(names(cuesFor(room('result'), final, 'p1')), ['fanfare'])
  assert.deepEqual(names(cuesFor(room('result'), final, 'p2')), ['end'])
  assert.deepEqual(names(cuesFor(room('result'), room('final', { final: { winner_ids: [] } }), 'p0')), ['end'])
})

test('going back to the lobby is silent', () => {
  assert.deepEqual(cuesFor(room('final'), room('lobby'), 'p0'), [])
})

test('ticks: the last three seconds, only where the clock presses on you', () => {
  assert.equal(tickFor({ phase: 'drawing', myTurn: true, secondsLeft: 3 }), 'tick')
  assert.equal(tickFor({ phase: 'drawing', myTurn: true, secondsLeft: 2 }), 'tick')
  assert.equal(tickFor({ phase: 'drawing', myTurn: true, secondsLeft: 1 }), 'tickHigh')
  assert.equal(tickFor({ phase: 'voting', myTurn: false, secondsLeft: 2 }), 'tick')
  assert.equal(tickFor({ phase: 'guess', myTurn: false, secondsLeft: 1 }), 'tickHigh')
})

test('no ticks when it is not pressing, or outside the last three seconds', () => {
  assert.equal(tickFor({ phase: 'drawing', myTurn: false, secondsLeft: 2 }), null) // watching someone else
  assert.equal(tickFor({ phase: 'result', myTurn: false, secondsLeft: 2 }), null) // waiting for the next round
  assert.equal(tickFor({ phase: 'drawing', myTurn: true, secondsLeft: 4 }), null)
  assert.equal(tickFor({ phase: 'drawing', myTurn: true, secondsLeft: 0 }), null)
  assert.equal(tickFor({ phase: 'voting', myTurn: false, secondsLeft: 30 }), null)
  assert.equal(tickFor({ phase: 'voting', myTurn: false, secondsLeft: NaN }), null)
})

test('the stamp lands after it starts, and the name after the stamp', () => {
  assert.ok(TIMING.stampImpact > TIMING.stampStart)
  assert.ok(TIMING.nameImpact > TIMING.nameStart)
  assert.ok(TIMING.nameStart > TIMING.stampImpact)
})
