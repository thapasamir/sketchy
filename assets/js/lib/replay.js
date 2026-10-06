// Playing a drawing back. Pure: given the strokes and how long it has been, which are done, which
// is being drawn and how much of it. (No clock and no canvas here, so it is unit-tested.)

// The replay takes about as long as the drawing has points to show, but never less than a few
// seconds (so a small drawing is still a moment to watch) or more than a dozen (so a huge one
// doesn't take forever). A short beat between strokes shows where each one ends.
export const MIN_MS = 3000
export const MAX_MS = 12000
export const MS_PER_POINT = 14
export const GAP_MS = 160

// the plan: when each stroke starts and how long it takes
export function timeline(strokes) {
  const points = strokes.reduce((sum, s) => sum + s.points.length, 0)
  const gaps = Math.max(0, strokes.length - 1) * GAP_MS
  const drawing = Math.min(MAX_MS - gaps, Math.max(MIN_MS - gaps, points * MS_PER_POINT))
  const perPoint = points ? Math.max(drawing, 1) / points : 0

  let at = 0
  const items = strokes.map(stroke => {
    const duration = stroke.points.length * perPoint
    const item = { start: at, duration, points: stroke.points.length }
    at += duration + GAP_MS
    return item
  })
  return { items, total: Math.max(at - GAP_MS, 0) }
}

// what is on the page `elapsed` ms in:
//   done     how many strokes are complete
//   current  the index of the stroke being drawn (null between strokes, and at the end)
//   count    how many of its points are showing
//   finished everything has been drawn
export function shownAt(plan, elapsed) {
  const { items, total } = plan
  if (!items.length || elapsed >= total) return { done: items.length, current: null, count: 0, finished: true }

  let done = 0
  for (let i = 0; i < items.length; i++) {
    const item = items[i]
    if (elapsed >= item.start + item.duration) {
      done = i + 1
      continue
    }
    if (elapsed < item.start) break
    const count = Math.min(item.points, Math.max(1, Math.ceil(((elapsed - item.start) / item.duration) * item.points)))
    return { done, current: i, count, finished: false }
  }
  return { done, current: null, count: 0, finished: false }
}
