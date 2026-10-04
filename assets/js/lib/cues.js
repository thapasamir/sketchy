// What the game should sound like. Pure functions: given what changed, say which sounds to play.
// No audio, no DOM, so every rule here is unit-tested with plain `node --test`.

// When things land, in ms after a screen appears. The CSS animations use the same numbers
// (see `style` on the cards), so the sound arrives exactly as the picture does.
export const TIMING = {
  stampStart: 450, // the imposter card's stamp starts to fall...
  stampImpact: 750, // ...and hits here
  nameStart: 900, // on the result, the imposter's name starts to stamp in...
  nameImpact: 1200, // ...and lands here
}

// Which sounds does a change in the room call for? `prev` and `next` are the public room before
// and after, `me` is my player id, `secret` is what I'm allowed to know about this round.
// Returns [{ name, delay?, attention? }]. `attention` means "this is for you, even if the tab is
// in the background" (the caller can vibrate or flash the title).
export function cuesFor(prev, next, me, secret) {
  // the first snapshot (joining, refreshing, reconnecting) is not an event
  if (!prev || !next) return []

  if (prev.phase === next.phase) {
    if (next.phase === 'lobby' && next.players.length > prev.players.length) return [{ name: 'pop' }]

    // `n` numbers the turns, so you are told every time it is yours, even twice running
    if (next.phase === 'drawing' && next.turn && next.turn.player_id === me && next.turn.n !== prev.turn?.n) {
      return [{ name: 'turn', attention: true }]
    }
    return []
  }

  switch (next.phase) {
    case 'reveal':
      return secret?.role === 'imposter'
        ? [{ name: 'flip' }, { name: 'stamp', delay: TIMING.stampImpact }]
        : [{ name: 'flip' }]
    case 'drawing':
      return next.turn?.player_id === me ? [{ name: 'turn', attention: true }] : []
    case 'voting':
      return [{ name: 'bell' }]
    case 'guess':
      return [{ name: 'caught' }]
    case 'result':
      // someone only watching has no side to win or lose for: a neutral sound
      return next.result
        ? [{ name: watching(next, me) ? 'bell' : resultSound(next.result, me), delay: TIMING.nameImpact }]
        : []
    case 'final':
      return [{ name: next.final?.winner_ids?.includes(me) ? 'fanfare' : 'end' }]
    default:
      return []
  }
}

// did I arrive after the game began, so I'm only watching this round?
const watching = (room, me) => room.players?.find(p => p.id === me)?.spectator === true

// how a round's result sounds depends on which side I'm on
export function resultSound(result, me) {
  const imposter = result.imposter_id === me
  switch (result.outcome) {
    case 'escaped':
      return imposter ? 'win' : 'lose'
    case 'caught':
      return imposter ? 'lose' : 'win'
    case 'guessed':
      // caught, but they stole the word: a win for them, and not quite a loss for the crew
      return imposter ? 'win' : 'bell'
    default:
      // the imposter left
      return imposter ? 'lose' : 'win'
  }
}

// A tick for each of the last three seconds, but only where the clock is pressing on you:
// your own drawing turn, the vote and the guess. (Not while you merely watch someone else draw,
// and not for the wait between rounds.)
export function tickFor({ phase, myTurn, secondsLeft }) {
  if (!(secondsLeft >= 1 && secondsLeft <= 3)) return null
  const pressing = (phase === 'drawing' && myTurn) || phase === 'voting' || phase === 'guess'
  if (!pressing) return null
  return secondsLeft === 1 ? 'tickHigh' : 'tick'
}
