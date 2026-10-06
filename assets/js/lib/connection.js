// Whether this browser is still connected to the game, and what to say about it.
//
//   online   - nothing to say
//   offline  - the connection dropped and has not come back: "Reconnecting…"
//   back     - it has come back: "Back online", for a moment
//
// A blip that mends itself within a second or so is not worth a banner (it would just flash), so
// "offline" is only shown if the drop lasts. Pure apart from the timers it is given, so the rules
// are unit-tested.
export function createConnection({ onChange, showAfter = 1200, backFor = 2200, timers = { set: (fn, ms) => setTimeout(fn, ms), clear: id => clearTimeout(id) } }) {
  let state = 'online'
  let pending = null
  let backTimer = null

  const set = next => {
    if (next === state) return
    state = next
    onChange(next)
  }
  const stopPending = () => {
    if (pending !== null) timers.clear(pending)
    pending = null
  }
  const stopBack = () => {
    if (backTimer !== null) timers.clear(backTimer)
    backTimer = null
  }

  return {
    get state() {
      return state
    },

    // the connection dropped
    lost() {
      stopBack()
      if (state === 'back') set('online')
      if (state === 'online' && pending === null) {
        pending = timers.set(() => {
          pending = null
          set('offline')
        }, showAfter)
      }
    },

    // the connection is (back) up
    restored() {
      stopPending()
      if (state !== 'offline') return
      set('back')
      backTimer = timers.set(() => {
        backTimer = null
        set('online')
      }, backFor)
    },

    // the phone says it has a network again. That ends a drop nobody has been told about yet (so a
    // blip never gets a banner), but a banner that is already up waits for the game to be reachable.
    networkUp() {
      if (state === 'online') stopPending()
    },

    stop() {
      stopPending()
      stopBack()
    },
  }
}
