// Shapes for the drawing board. A shape is dragged out from one corner to the opposite one and
// then becomes an ordinary stroke (a list of points), so it has the player's colour and can be
// undone, replayed and picked out like anything else drawn, and the server needs to know nothing
// about it.
//
// The points are close together along straight edges: the board smooths lines by curving through
// the middle of neighbouring points, and a corner made of a single point would come out round.

export const TOOLS = [
  { id: 'pen', label: 'Pen' },
  { id: 'line', label: 'Line' },
  { id: 'circle', label: 'Circle' },
  { id: 'box', label: 'Box' },
]

export const isShape = tool => tool === 'line' || tool === 'circle' || tool === 'box'

// shorter than this (as a fraction of the canvas) is a tap, not a shape: it leaves a dot
const MIN_SIZE = 0.01

const lerp = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]
const along = (from, to, steps) => Array.from({ length: steps }, (_, i) => lerp(from, to, (i + 1) / steps))

// the points of the shape dragged from `a` to `b` (each [x, y], 0..1)
export function shapePoints(tool, a, b) {
  if (Math.hypot(b[0] - a[0], b[1] - a[1]) < MIN_SIZE) return [a]

  if (tool === 'line') return [a, ...along(a, b, 12)]

  if (tool === 'box') {
    const corners = [a, [b[0], a[1]], b, [a[0], b[1]], a]
    return [a, ...corners.slice(1).flatMap((to, i) => along(corners[i], to, 10))]
  }

  if (tool === 'circle') {
    const cx = (a[0] + b[0]) / 2
    const cy = (a[1] + b[1]) / 2
    const rx = Math.abs(b[0] - a[0]) / 2
    const ry = Math.abs(b[1] - a[1]) / 2
    const steps = 48
    // from the top, all the way round and back to where it began
    return Array.from({ length: steps + 1 }, (_, i) => {
      const angle = -Math.PI / 2 + (i / steps) * Math.PI * 2
      return [cx + Math.cos(angle) * rx, cy + Math.sin(angle) * ry]
    })
  }

  return [a, b]
}
