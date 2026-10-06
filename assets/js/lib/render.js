// Painting strokes onto a canvas. Coordinates are 0..1 and are scaled to the canvas size here,
// so the same stroke looks the same on a phone and a big monitor.

// brush size 1..5 -> line width as a fraction of the canvas width (keep the sizes in step with
// @brush_sizes in Backend.Rooms.Room)
export const BRUSH_WIDTH = { 1: 0.006, 2: 0.014, 3: 0.03, 4: 0.05, 5: 0.08 }

const mid = (a, b) => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2]

// Draw one whole stroke as a single path.
//
// Raw mouse samples are jittery, so the line is not drawn point to point. Each piece is a curve
// that runs from the middle of one pair of points to the middle of the next, bending toward the
// point between them, which makes the line smooth.
//
// It is one path and one stroke() call on purpose. Stroking each little piece separately leaves a
// visible bead at every joint (the soft anti-aliased edges of neighbouring pieces pile up).
// It also means the result depends only on the points, never on how they arrived.
export function drawStroke(ctx, stroke, w, h) {
  const pts = stroke.points
  const width = BRUSH_WIDTH[stroke.size] * w
  ctx.strokeStyle = stroke.color
  ctx.fillStyle = stroke.color
  ctx.lineWidth = width
  ctx.lineCap = 'round'
  ctx.lineJoin = 'round'

  if (pts.length === 1) {
    // a tap with no movement still leaves a dot
    ctx.beginPath()
    ctx.arc(pts[0][0] * w, pts[0][1] * h, width / 2, 0, Math.PI * 2)
    ctx.fill()
    return
  }

  ctx.beginPath()
  ctx.moveTo(pts[0][0] * w, pts[0][1] * h)
  for (let i = 1; i < pts.length; i++) {
    const end = mid(pts[i - 1], pts[i])
    ctx.quadraticCurveTo(pts[i - 1][0] * w, pts[i - 1][1] * h, end[0] * w, end[1] * h)
  }
  // the curves stop in the middle of the last pair; run the line out to the last point
  const last = pts[pts.length - 1]
  ctx.lineTo(last[0] * w, last[1] * h)
  ctx.stroke()
}

export function clear(ctx, w, h) {
  ctx.clearRect(0, 0, w, h)
}

// --- shapes: the way to tell players apart that isn't colour ---

const polygon = (n, radius, start = -Math.PI / 2) =>
  Array.from({ length: n }, (_, i) => {
    const a = start + (i * 2 * Math.PI) / n
    return [radius * Math.cos(a), radius * Math.sin(a)]
  })

const star = () =>
  Array.from({ length: 10 }, (_, i) => {
    const a = -Math.PI / 2 + (i * Math.PI) / 5
    const r = i % 2 ? 0.45 : 1
    return [r * Math.cos(a), r * Math.sin(a)]
  })

const PLUS = [
  [-0.28, -0.92], [0.28, -0.92], [0.28, -0.28], [0.92, -0.28], [0.92, 0.28], [0.28, 0.28],
  [0.28, 0.92], [-0.28, 0.92], [-0.28, 0.28], [-0.92, 0.28], [-0.92, -0.28], [-0.28, -0.28],
]
const turn45 = pts => pts.map(([x, y]) => [(x - y) * Math.SQRT1_2, (x + y) * Math.SQRT1_2])

// each is a list of [x, y] corners around (0, 0), no further than 1 from it; 'circle' has none
const SHAPES = {
  circle: null,
  square: [[-0.7, -0.7], [0.7, -0.7], [0.7, 0.7], [-0.7, 0.7]],
  triangle: polygon(3, 1),
  diamond: [[0, -1], [1, 0], [0, 1], [-1, 0]],
  star: star(),
  plus: PLUS,
  hexagon: polygon(6, 1),
  cross: turn45(PLUS),
}

export const SHAPE_NAMES = Object.keys(SHAPES)

// the corners of a shape, or null for a circle; an unknown name is drawn as a circle too
export const shapePoints = name => SHAPES[name] ?? null

// Paint a shape centred at (x, y), `r` pixels across from the middle, filled and outlined.
export function drawMarker(ctx, shape, x, y, r, color) {
  const pts = shapePoints(shape)
  ctx.beginPath()
  if (!pts) ctx.arc(x, y, r, 0, Math.PI * 2)
  else pts.forEach(([px, py], i) => (i ? ctx.lineTo(x + px * r, y + py * r) : ctx.moveTo(x + px * r, y + py * r)))
  ctx.closePath()
  ctx.fillStyle = color
  ctx.fill()
  ctx.lineWidth = Math.max(1, r * 0.22)
  ctx.lineJoin = 'round'
  ctx.strokeStyle = '#1b1b1b'
  ctx.stroke()
}

// --- which stroke was tapped? ---

// distance from point p to the segment a-b, all in pixels
function distanceToSegment(p, a, b) {
  const dx = b[0] - a[0]
  const dy = b[1] - a[1]
  const len2 = dx * dx + dy * dy
  const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / len2))
  return Math.hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dy))
}

// The stroke nearest to where somebody tapped, or null if the tap was on empty paper.
// `point` is [x, y] as 0..1 fractions, like the strokes. A finger is bigger than a thin line, so a
// stroke counts as hit when it is within a fingertip's reach (`reach` pixels, at least the line's
// own width); where several are in reach, the closest wins, and the one drawn last wins a tie.
export function strokeAt(strokes, point, w, h, reach = 14) {
  const p = [point[0] * w, point[1] * h]
  let best = null
  let bestDistance = Infinity
  for (const stroke of strokes) {
    if (!stroke.points.length) continue
    const px = stroke.points.map(([x, y]) => [x * w, y * h])
    let d = Infinity
    if (px.length === 1) d = Math.hypot(p[0] - px[0][0], p[1] - px[0][1])
    for (let i = 1; i < px.length; i++) d = Math.min(d, distanceToSegment(p, px[i - 1], px[i]))
    const allowed = Math.max(reach, (BRUSH_WIDTH[stroke.size] * w) / 2 + 6)
    if (d <= allowed && d <= bestDistance) {
      best = stroke
      bestDistance = d
    }
  }
  return best
}
