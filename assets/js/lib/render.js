// Painting strokes onto a canvas. Coordinates are 0..1 and are scaled to the canvas size here,
// so the same stroke looks the same on a phone and a big monitor.

// brush size 1, 2, 3 -> line width as a fraction of the canvas width
export const BRUSH_WIDTH = { 1: 0.006, 2: 0.014, 3: 0.03 }

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
