// Hand-drawn outlines for the players' bodies. The plain shapes (a perfect circle, a razor-sharp
// triangle) look mechanical once a face is on them; these keep each shape recognisable but give it
// soft corners and a slight wobble, like something drawn with a marker.
//
// Everything is deterministic: the same shape always gets the same wobble, so nobody's outline
// changes from one moment to the next, and it can be tested.
import { shapePoints } from './render.js'

// a steady pseudo-random number from 0 to 1 for a shape and a point on it
function noise(shape, i, salt = 0) {
  let h = 2166136261
  for (const ch of `${shape}:${i}:${salt}`) h = Math.imul(h ^ ch.charCodeAt(0), 16777619)
  return ((h >>> 0) % 10000) / 10000
}
const wobble = (shape, i, amount, salt) => (noise(shape, i, salt) - 0.5) * 2 * amount

const f = n => Math.round(n * 1000) / 1000
const pt = p => `${f(p[0])} ${f(p[1])}`

// How round each shape's corners are, as a share of the edge (0 sharp, 0.5 the most possible)
const ROUNDING = { square: 0.34, triangle: 0.3, diamond: 0.3, hexagon: 0.32, star: 0.2, plus: 0.28, cross: 0.28 }

// A closed smooth curve through the points (Catmull-Rom turned into Béziers)
export function smoothClosed(points) {
  const n = points.length
  let d = `M${pt(points[0])}`
  for (let i = 0; i < n; i++) {
    const p0 = points[(i + n - 1) % n]
    const p1 = points[i]
    const p2 = points[(i + 1) % n]
    const p3 = points[(i + 2) % n]
    const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6]
    const c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6]
    d += `C${pt(c1)} ${pt(c2)} ${pt(p2)}`
  }
  return d + 'Z'
}

// A polygon with every corner rounded off
export function roundedPolygon(points, share) {
  const n = points.length
  const toward = (a, b) => [a[0] + (b[0] - a[0]) * share, a[1] + (b[1] - a[1]) * share]
  let d = ''
  for (let i = 0; i < n; i++) {
    const prev = points[(i + n - 1) % n]
    const here = points[i]
    const next = points[(i + 1) % n]
    d += `${i === 0 ? 'M' : 'L'}${pt(toward(here, prev))}Q${pt(here)} ${pt(toward(here, next))}`
  }
  return d + 'Z'
}

// The outline of a body of this shape, as an SVG path, in the same units as the plain shapes
// (about 1 from the middle). Unknown shapes are circles. A `seed` (a player's id, say) gives the
// round body its own wobble, so a room of players are all the same kind of blob but no two the same.
export function bodyPath(shape, seed = '') {
  const corners = shapePoints(shape)

  if (!corners) {
    // a circle that is slightly out of true: nine points, each a touch nearer or further away
    const n = 9
    const key = `circle${seed}`
    const ring = Array.from({ length: n }, (_, i) => {
      const angle = -Math.PI / 2 + (i * 2 * Math.PI) / n + wobble(key, i, 0.05, 1)
      const radius = 1 + wobble(key, i, 0.045, 2)
      return [radius * Math.cos(angle), radius * Math.sin(angle)]
    })
    return smoothClosed(ring)
  }

  const jittered = corners.map(([x, y], i) => [x + wobble(shape, i, 0.035, 1), y + wobble(shape, i, 0.035, 2)])
  return roundedPolygon(jittered, ROUNDING[shape] ?? 0.3)
}
