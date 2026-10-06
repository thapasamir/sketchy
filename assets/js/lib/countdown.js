// How pressing the clock should look. Pure, so the rules are unit-tested.
//
//   calm    - plenty of time
//   warn   - running low: the last 10 seconds, or the last quarter of a long turn
//   urgent - the last 5 seconds
//
// The wait between rounds is never alarming: nothing is being lost, the next round is just coming.
export const URGENT_SECONDS = 5
export const WARN_SECONDS = 10
export const WARN_FRACTION = 0.25

export function urgencyOf({ phase, secondsLeft, totalMs }) {
  if (phase === 'result' || phase === 'final' || phase === 'lobby') return 'calm'
  if (secondsLeft <= URGENT_SECONDS) return 'urgent'
  const warnAt = Math.max(WARN_SECONDS, Math.ceil((totalMs / 1000) * WARN_FRACTION))
  return secondsLeft <= warnAt ? 'warn' : 'calm'
}

// the share of the time that is left, from 0 to 1 (for the ring and the bar)
export const fractionLeft = (msLeft, totalMs) => Math.min(1, Math.max(0, msLeft / Math.max(totalMs, 1)))
