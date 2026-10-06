// Sticker reactions. The server only knows their names (a fixed list, so nothing typed can get
// through); the pictures (components/Sticker.svelte) are chosen here. Keep the ids in step with Backend.Rooms.Reactions.

export const REACTIONS = [
  { id: 'laugh', label: 'Laugh' },
  { id: 'think', label: 'Thinking' },
  { id: 'sus', label: 'Suspicious' },
  { id: 'eyes', label: 'Watching' },
  { id: 'clap', label: 'Applause' },
  { id: 'fire', label: 'Fire' },
]

export const isReaction = id => REACTIONS.some(r => r.id === id)

// How long one floats on screen, and how many may at once (a flood shouldn't cover the picture)
export const SHOW_MS = 2400
export const MAX_SHOWN = 14

// Add a reaction that just arrived to the ones on screen: unknown names are dropped, and when
// there are too many the oldest make way. `x` is where it floats up from, as a percentage of the
// picture's width (kept away from the very edges).
export function show(current, event, key, random = Math.random) {
  if (!isReaction(event?.id)) return current
  const next = [...current, { key, id: event.id, name: String(event.name ?? ''), x: 8 + Math.round(random() * 84) }]
  return next.slice(-MAX_SHOWN)
}
