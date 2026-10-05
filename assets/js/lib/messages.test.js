import test from 'node:test'
import assert from 'node:assert/strict'
import { joinReasons, chatReasons, drawReasons, describeAction, actionReasons } from './messages.js'

test('a known refusal is explained', () => {
  assert.equal(describeAction('not_host'), 'Only the host can do that.')
})

test('an unknown one gets a generic line, never the raw reason', () => {
  assert.equal(describeAction('xyz_internal'), 'Something went wrong.')
  assert.equal(describeAction(undefined), 'Something went wrong.')
})

test('the player-count message uses the room\'s own minimum', () => {
  assert.match(describeAction('not_enough_players', 4), /at least 4 connected/)
  assert.match(describeAction('not_enough_players'), /at least 3 connected/)
})

test('every sentence is plain text for a person', () => {
  const all = [...Object.values(joinReasons), ...Object.values(chatReasons), ...Object.values(actionReasons(3))]
  for (const text of all) assert.ok(text.length > 5 && !/_/.test(text), text)
})

test('being slowed down is explained, in the room and when joining one', () => {
  assert.match(describeAction('rate_limited'), /too fast/)
  assert.match(chatReasons.rate_limited, /Slow down/)
  assert.match(joinReasons.rate_limited, /Wait a minute/)
  assert.match(joinReasons.too_many_connections, /Close a tab/)
})

test('not being the drawer is not worth a complaint', () => {
  assert.equal(drawReasons.not_your_turn, '')
})
