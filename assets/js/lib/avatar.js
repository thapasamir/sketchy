// A player's face: which eyes, which mouth, which hat (0 is no hat). The drawings of each are in
// the Face* components; this is the choice, and remembering it.
//
// The counts must match the server's (Backend.Avatar; a test compares them).
import { read, write } from './storage.js'

export const COUNTS = { eyes: 12, mouth: 12, hat: 16 }
export const PARTS = Object.keys(COUNTS)

// What each choice is called, in the order of the drawings (so the arrows can say what you are on)
export const NAMES = {
  eyes: ['Dots', 'Wide', 'Happy', 'Sleepy', 'Wink', 'Sparkle', 'Shades', 'Angry', 'Hearts', 'Lashes', 'Cyclops', 'Dizzy'],
  mouth: ['Smile', 'Grin', 'Oh', 'Flat', 'Tongue', 'Cat', 'Sad', 'Smirk', 'Fangs', 'Moustache', 'Teeth', 'Kiss'],
  hat: ['None', 'Party', 'Crown', 'Cap', 'Top hat', 'Beanie', 'Bow', 'Cat ears', 'Wizard', 'Pirate', 'Chef', 'Cowboy', 'Viking', 'Santa', 'Halo', 'Bunny'],
}

// The next choice in a ring: `step` of 1 goes forward, -1 back, and past either end it comes round.
export const cycle = (index, count, step) => (((index + step) % count) + count) % count

const KEY = 'sketchy:avatar'

const inRange = (part, value) => Number.isInteger(value) && value >= 0 && value < COUNTS[part]

// A face as the server and the screens use it, or null if it isn't one. Anything else in the object
// is dropped.
export function normalizeAvatar(face) {
  if (!face || typeof face !== 'object') return null
  if (!PARTS.every(part => inRange(part, face[part]))) return null
  return { eyes: face.eyes, mouth: face.mouth, hat: face.hat }
}

// A face chosen at random. (`random` is Math.random, or something steady for a test.)
export function randomAvatar(random = Math.random) {
  return Object.fromEntries(PARTS.map(part => [part, Math.floor(random() * COUNTS[part])]))
}

// the same face with one part changed
export const withPart = (face, part, index) => ({ ...face, [part]: index })

// The face this browser last chose. Someone who has never chosen one gets a random face, which is
// kept, so it doesn't change every visit.
export function loadAvatar() {
  const saved = normalizeAvatar(read(KEY))
  if (saved) return saved
  const fresh = randomAvatar()
  write(KEY, fresh)
  return fresh
}

export const saveAvatar = face => {
  const valid = normalizeAvatar(face)
  if (valid) write(KEY, valid)
}
