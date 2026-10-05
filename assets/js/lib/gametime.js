// How long a game takes, roughly, so the host can see what their settings add up to.
//
// It is an upper limit: a turn ends early when the drawer taps "I'm done", and the vote ends as
// soon as everyone has voted. Each round has a fixed part (reading the cards, the vote, the
// imposter's guess, the result) and the drawing, which is every player's turns on the word.

// seconds, as the server's defaults (config/dev.exs): reveal, vote, guess and result
export const ROUND_EXTRAS = { reveal: 8, vote: 45, guess: 20, result: 12 }
const EXTRAS_TOTAL = Object.values(ROUND_EXTRAS).reduce((a, b) => a + b, 0)

// how many turns the drawing of one word takes
export const turnsPerWord = (players, lapsNow) => Math.max(players, 1) * Math.max(lapsNow ?? 1, 1)

// the longest a whole game can take, in seconds
export function maxGameSeconds({ rounds, drawTime, players, lapsNow }) {
  return rounds * (turnsPerWord(players, lapsNow) * drawTime + EXTRAS_TOTAL)
}

// "up to about 13 minutes"
export function describeLength(seconds) {
  const minutes = Math.max(1, Math.round(seconds / 60))
  return `up to about ${minutes} ${minutes === 1 ? 'minute' : 'minutes'}`
}

// a word for how fast turns are: short turns keep the game moving, long ones suit careful drawers
export function paceOf(drawTime) {
  if (drawTime <= 40) return 'Quick'
  if (drawTime <= 70) return 'Relaxed'
  return 'Slow and careful'
}
