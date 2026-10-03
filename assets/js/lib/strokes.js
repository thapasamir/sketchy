// The shared drawing, as the browser sees it.
//
// A stroke is { id, player_id, color, size, points: [[x, y], ...], done }, with x and y between
// 0 and 1 (a fraction of the canvas, so every screen size draws the same picture).
//
// Changes arrive as events from the server ('start', 'points', 'end', 'undo'), and the player who
// is drawing applies the same events to their own copy as they go. Whatever draws the strokes on
// screen subscribes here and is told what changed, so it only paints the new part.

export function createStrokeStore() {
  let strokes = []
  const listeners = new Set()
  const emit = change => listeners.forEach(listener => listener(change))
  const find = id => strokes.findLast(s => s.id === id)

  return {
    get strokes() {
      return strokes
    },

    // replace everything (joining, refreshing, reconnecting)
    load(list = []) {
      strokes = list.map(s => ({ ...s, points: [...s.points], done: true }))
      emit({ type: 'reset' })
    },

    apply(event) {
      switch (event.type) {
        case 'start': {
          if (find(event.id)) return
          const stroke = {
            id: event.id,
            player_id: event.player_id,
            color: event.color,
            size: event.size,
            points: [...event.points],
            done: false,
          }
          strokes.push(stroke)
          emit({ type: 'start', stroke })
          break
        }
        case 'points': {
          const stroke = find(event.id)
          if (!stroke) return
          const from = stroke.points.length
          stroke.points.push(...event.points)
          emit({ type: 'points', stroke, from })
          break
        }
        case 'end': {
          const stroke = find(event.id)
          if (!stroke) return
          stroke.done = true
          emit({ type: 'end', stroke })
          break
        }
        case 'undo':
          strokes = strokes.filter(s => s.id !== event.id)
          emit({ type: 'reset' })
          break
      }
    },

    subscribe(listener) {
      listeners.add(listener)
      return () => listeners.delete(listener)
    },
  }
}
