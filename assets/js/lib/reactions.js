// Emoji reactions. The server only knows their names (a fixed list, so nothing typed can get
// through); the pictures are chosen here. Keep the ids in step with Backend.Rooms.Reactions.

export const REACTIONS = [
  { id: 'laugh', emoji: '😂', label: 'Laugh' },
  { id: 'think', emoji: '🤔', label: 'Thinking' },
  { id: 'sus', emoji: '🤨', label: 'Suspicious' },
  { id: 'eyes', emoji: '👀', label: 'Watching' },
  { id: 'clap', emoji: '👏', label: 'Applause' },
  { id: 'fire', emoji: '🔥', label: 'Fire' },
]

export const emojiFor = id => REACTIONS.find(r => r.id === id)?.emoji ?? null

// How long one floats on screen, and how many may at once (a flood shouldn't cover the picture)
export const SHOW_MS = 2400
export const MAX_SHOWN = 14

// Add a reaction that just arrived to the ones on screen: unknown names are dropped, and when
// there are too many the oldest make way. `x` is where it floats up from, as a percentage of the
// picture's width (kept away from the very edges).
export function show(current, event, key, random = Math.random) {
  const emoji = emojiFor(event?.id)
  if (!emoji) return current
  const next = [...current, { key, emoji, name: String(event.name ?? ''), x: 8 + Math.round(random() * 84) }]
  return next.slice(-MAX_SHOWN)
}
