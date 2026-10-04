// A small QR code generator, so inviting a friend needs no library: `qr('https://...')` returns the
// grid of dark and light squares to draw.
//
// It does the same steps as the QR standard (ISO/IEC 18004): put the text in bytes, add
// Reed-Solomon error correction so a damaged or dirty code still scans, lay the bits out around
// the fixed patterns (the three corner squares, the alignment squares, the timing lines), then
// try each of the eight mask patterns and keep the one that is easiest for a camera to read.
//
// Limits: byte mode (any text, as UTF-8), error correction level L or M, versions 1 to 10. That
// holds 213 characters at level M, plenty for an invite link.

const LEVELS = { L: { formatBits: 1, index: 0 }, M: { formatBits: 0, index: 1 } }

// error-correction bytes per block, and number of blocks, indexed [level][version]
const ECC_PER_BLOCK = [
  [-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18],
  [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26],
]
const NUM_BLOCKS = [
  [-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4],
  [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5],
]

const MAX_VERSION = 10

// --- sizes ---

// how many modules (squares) are free for data and error correction in a code of this version
function dataModules(version) {
  let result = (16 * version + 128) * version + 64
  if (version >= 2) {
    const alignments = Math.floor(version / 7) + 2
    result -= (25 * alignments - 10) * alignments - 55
    if (version >= 7) result -= 36
  }
  return result
}

const dataCodewords = (version, level) =>
  Math.floor(dataModules(version) / 8) - ECC_PER_BLOCK[level][version] * NUM_BLOCKS[level][version]

// --- error correction: arithmetic on bytes that wraps around the "field" GF(256) ---

function gfMultiply(x, y) {
  let z = 0
  for (let i = 7; i >= 0; i--) {
    z = (z << 1) ^ ((z >>> 7) * 0x11d)
    z ^= ((y >>> i) & 1) * x
  }
  return z
}

// the polynomial whose roots are 2^0 .. 2^(degree-1); dividing by it leaves the check bytes
function generator(degree) {
  const result = new Array(degree).fill(0)
  result[degree - 1] = 1
  let root = 1
  for (let i = 0; i < degree; i++) {
    for (let j = 0; j < degree; j++) {
      result[j] = gfMultiply(result[j], root)
      if (j + 1 < degree) result[j] ^= result[j + 1]
    }
    root = gfMultiply(root, 0x02)
  }
  return result
}

function remainder(data, divisor) {
  const result = divisor.map(() => 0)
  for (const byte of data) {
    const factor = byte ^ result.shift()
    result.push(0)
    divisor.forEach((coefficient, i) => (result[i] ^= gfMultiply(coefficient, factor)))
  }
  return result
}

// --- the message, as bytes with error correction added and interleaved ---

function codewords(bytes, version, level) {
  // mode (byte = 0100), length, the bytes, then the terminator and padding up to the capacity
  const bits = []
  const push = (value, count) => {
    for (let i = count - 1; i >= 0; i--) bits.push((value >>> i) & 1)
  }
  push(0b0100, 4)
  push(bytes.length, version <= 9 ? 8 : 16)
  bytes.forEach(b => push(b, 8))

  const capacityBits = dataCodewords(version, level) * 8
  push(0, Math.min(4, capacityBits - bits.length))
  push(0, (8 - (bits.length % 8)) % 8)
  for (let pad = 0xec; bits.length < capacityBits; pad ^= 0xec ^ 0x11) push(pad, 8)

  const data = []
  for (let i = 0; i < bits.length; i += 8) data.push(parseInt(bits.slice(i, i + 8).join(''), 2))

  // split into blocks, work out each block's check bytes, and interleave them
  const blocks = NUM_BLOCKS[level][version]
  const eccLen = ECC_PER_BLOCK[level][version]
  const raw = Math.floor(dataModules(version) / 8)
  const shortBlocks = blocks - (raw % blocks)
  const shortLen = Math.floor(raw / blocks)
  const divisor = generator(eccLen)

  const split = []
  for (let i = 0, k = 0; i < blocks; i++) {
    const length = shortLen - eccLen + (i < shortBlocks ? 0 : 1)
    const chunk = data.slice(k, k + length)
    k += length
    split.push({ data: chunk, ecc: remainder(chunk, divisor) })
  }

  const result = []
  for (let i = 0; i < shortLen - eccLen + 1; i++) {
    split.forEach((block, j) => {
      if (i < block.data.length) result.push(block.data[i])
    })
  }
  for (let i = 0; i < eccLen; i++) split.forEach(block => result.push(block.ecc[i]))
  return result
}

// --- laying out the grid ---

const bit = (value, i) => ((value >>> i) & 1) !== 0

function alignmentPositions(version) {
  if (version === 1) return []
  const count = Math.floor(version / 7) + 2
  const size = version * 4 + 17
  const step = Math.ceil((version * 4 + 4) / (count * 2 - 2)) * 2
  const result = [6]
  for (let position = size - 7; result.length < count; position -= step) result.splice(1, 0, position)
  return result
}

function emptyGrid(version) {
  const size = version * 4 + 17
  return {
    size,
    modules: Array.from({ length: size }, () => new Array(size).fill(false)),
    fixed: Array.from({ length: size }, () => new Array(size).fill(false)),
  }
}

function drawFunctionPatterns(grid, version) {
  const { size, modules, fixed } = grid
  const set = (x, y, dark) => {
    modules[y][x] = dark
    fixed[y][x] = true
  }

  // timing lines
  for (let i = 0; i < size; i++) {
    set(6, i, i % 2 === 0)
    set(i, 6, i % 2 === 0)
  }

  // the three corner finder squares, with their light border
  const finder = (cx, cy) => {
    for (let dy = -4; dy <= 4; dy++) {
      for (let dx = -4; dx <= 4; dx++) {
        const distance = Math.max(Math.abs(dx), Math.abs(dy))
        const x = cx + dx
        const y = cy + dy
        if (x >= 0 && x < size && y >= 0 && y < size) set(x, y, distance !== 2 && distance !== 4)
      }
    }
  }
  finder(3, 3)
  finder(size - 4, 3)
  finder(3, size - 4)

  // alignment squares (not where they would overlap a finder)
  const positions = alignmentPositions(version)
  const last = positions.length - 1
  positions.forEach((cy, i) => {
    positions.forEach((cx, j) => {
      if ((i === 0 && j === 0) || (i === 0 && j === last) || (i === last && j === 0)) return
      for (let dy = -2; dy <= 2; dy++) {
        for (let dx = -2; dx <= 2; dx++) set(cx + dx, cy + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1)
      }
    })
  })

  // version number blocks (version 7 and up)
  if (version >= 7) {
    let remainderBits = version
    for (let i = 0; i < 12; i++) remainderBits = (remainderBits << 1) ^ ((remainderBits >>> 11) * 0x1f25)
    const bits = (version << 12) | remainderBits
    for (let i = 0; i < 18; i++) {
      const dark = bit(bits, i)
      const a = size - 11 + (i % 3)
      const b = Math.floor(i / 3)
      set(a, b, dark)
      set(b, a, dark)
    }
  }

  // reserve the format-bit squares; they are filled in once the mask is chosen
  drawFormat(grid, 'L', 0)
}

function drawFormat(grid, level, mask) {
  const { size, modules, fixed } = grid
  const data = (LEVELS[level].formatBits << 3) | mask
  let remainderBits = data
  for (let i = 0; i < 10; i++) remainderBits = (remainderBits << 1) ^ ((remainderBits >>> 9) * 0x537)
  const bits = ((data << 10) | remainderBits) ^ 0x5412

  const set = (x, y, dark) => {
    modules[y][x] = dark
    fixed[y][x] = true
  }
  for (let i = 0; i <= 5; i++) set(8, i, bit(bits, i))
  set(8, 7, bit(bits, 6))
  set(8, 8, bit(bits, 7))
  set(7, 8, bit(bits, 8))
  for (let i = 9; i < 15; i++) set(14 - i, 8, bit(bits, i))
  for (let i = 0; i < 8; i++) set(size - 1 - i, 8, bit(bits, i))
  for (let i = 8; i < 15; i++) set(8, size - 15 + i, bit(bits, i))
  set(8, size - 8, true) // always dark
}

// the data, zig-zagging up and down pairs of columns from the bottom right
function drawCodewords(grid, data) {
  const { size, modules, fixed } = grid
  let i = 0
  for (let right = size - 1; right >= 1; right -= 2) {
    if (right === 6) right = 5 // skip the vertical timing line
    for (let vert = 0; vert < size; vert++) {
      for (let j = 0; j < 2; j++) {
        const x = right - j
        const upward = ((right + 1) & 2) === 0
        const y = upward ? size - 1 - vert : vert
        if (!fixed[y][x] && i < data.length * 8) {
          modules[y][x] = bit(data[i >>> 3], 7 - (i & 7))
          i++
        }
      }
    }
  }
}

// --- masks: flip some squares so the code has no big blank or striped areas ---

const MASKS = [
  (x, y) => (x + y) % 2 === 0,
  (x, y) => y % 2 === 0,
  (x, y) => x % 3 === 0,
  (x, y) => (x + y) % 3 === 0,
  (x, y) => (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0,
  (x, y) => ((x * y) % 2) + ((x * y) % 3) === 0,
  (x, y) => (((x * y) % 2) + ((x * y) % 3)) % 2 === 0,
  (x, y) => (((x + y) % 2) + ((x * y) % 3)) % 2 === 0,
]

function applyMask(grid, mask) {
  const { size, modules, fixed } = grid
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      if (!fixed[y][x] && MASKS[mask](x, y)) modules[y][x] = !modules[y][x]
    }
  }
}

// how hard this layout would be for a camera, by the standard's four rules (lower is better)
function penalty({ size, modules }) {
  let score = 0

  // 1. runs of five or more of the same colour in a row or column
  const runs = line => {
    let run = 1
    for (let i = 1; i <= line.length; i++) {
      if (i < line.length && line[i] === line[i - 1]) run++
      else {
        if (run >= 5) score += 3 + (run - 5)
        run = 1
      }
    }
  }
  for (let y = 0; y < size; y++) runs(modules[y])
  for (let x = 0; x < size; x++) runs(modules.map(row => row[x]))

  // 2. blocks of 2 x 2 in one colour
  for (let y = 0; y < size - 1; y++) {
    for (let x = 0; x < size - 1; x++) {
      const c = modules[y][x]
      if (c === modules[y][x + 1] && c === modules[y + 1][x] && c === modules[y + 1][x + 1]) score += 3
    }
  }

  // 3. something that looks like the corner squares (dark-light-dark dark dark-light-dark, with
  // four light squares beside it), which a camera could mistake for one
  const patterns = [
    [true, false, true, true, true, false, true, false, false, false, false],
    [false, false, false, false, true, false, true, true, true, false, true],
  ]
  const matches = (read, i) => patterns.some(p => p.every((v, k) => read(i + k) === v))
  for (let y = 0; y < size; y++) {
    for (let x = 0; x <= size - 11; x++) {
      if (matches(k => modules[y][k], x)) score += 40
      if (matches(k => modules[k][y], x)) score += 40
    }
  }

  // 4. balance of dark and light
  const dark = modules.flat().filter(Boolean).length
  const total = size * size
  score += Math.floor(Math.abs(dark * 20 - total * 10) / total) * 10

  return score
}

// --- the whole thing ---

// Returns { size, version, modules } where modules[y][x] is true for a dark square.
export function qr(text, level = 'M') {
  if (!LEVELS[level]) throw new Error(`unknown error correction level ${level}`)
  const bytes = Array.from(new TextEncoder().encode(text))
  const lengthBits = version => (version <= 9 ? 8 : 16)

  let version = 1
  while (version <= MAX_VERSION && 4 + lengthBits(version) + bytes.length * 8 > dataCodewords(version, LEVELS[level].index) * 8) version++
  if (version > MAX_VERSION) throw new Error(`that text is too long for a QR code here (${bytes.length} bytes)`)

  const lv = LEVELS[level].index
  const data = codewords(bytes, version, lv)

  let best = null
  for (let mask = 0; mask < 8; mask++) {
    const grid = emptyGrid(version)
    drawFunctionPatterns(grid, version)
    drawCodewords(grid, data)
    applyMask(grid, mask)
    drawFormat(grid, level, mask)
    const score = penalty(grid)
    if (!best || score < best.score) best = { score, grid }
  }

  return { size: best.grid.size, version, modules: best.grid.modules }
}

// The grid as one SVG path (a unit square for each dark module), with the 4-module quiet zone the
// standard asks for around it. Use as `<svg viewBox="0 0 {box} {box}"><path d={path} /></svg>`.
export function qrPath(text, level = 'M') {
  const { size, modules, version } = qr(text, level)
  const quiet = 4
  let path = ''
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      if (modules[y][x]) path += `M${x + quiet} ${y + quiet}h1v1h-1z`
    }
  }
  return { box: size + quiet * 2, path, version }
}
