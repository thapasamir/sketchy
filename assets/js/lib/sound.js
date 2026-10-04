// Every sound in the game is made here, in the browser, with the Web Audio API. There are no
// audio files to download, license or keep in step with the code.
//
// A sound is just data: a list of notes and whooshes with start times. `schedule` turns that into
// audio nodes. Because it only needs an audio context, the same code runs live (play) and in an
// offline context, which is how the tests render each sound and check it for clipping and clicks.

import { writable, get } from 'svelte/store'
import { loadMuted, saveMuted } from './prefs.js'

// the overall loudness; the sounds are meant to sit under a conversation, not on top of it
const MASTER_GAIN = 0.6

const HZ = {
  C4: 261.63, D4: 293.66, E4: 329.63, G4: 392, A4: 440, B4: 493.88,
  C5: 523.25, D5: 587.33, E5: 659.25, G5: 783.99, A5: 880, C6: 1046.5, E6: 1318.5,
}

// a pitched note: `freq` Hz for `dur` seconds from `t`, optionally sliding to `to`
const tone = (t, dur, freq, gain = 0.3, { to, type = 'sine' } = {}) => ({ kind: 'tone', t, dur, freq, to, gain, type })
// a whoosh: noise through a band-pass filter whose centre sweeps from `from` to `to` Hz
const whoosh = (t, dur, from, to, gain = 0.2, q = 1) => ({ kind: 'noise', t, dur, from, to, gain, q })

export const SOUNDS = {
  // someone joined the room
  pop: [tone(0, 0.14, 600, 0.4, { to: 900 })],
  // someone said something in the chat: a soft two-note blip, quieter than the game sounds
  message: [tone(0, 0.08, 740, 0.28, { type: 'triangle' }), tone(0.07, 0.1, 988, 0.24, { type: 'triangle' })],
  // a choice was made (a vote, a brush)
  select: [tone(0, 0.07, 520, 0.38, { type: 'triangle' })],
  // the last seconds of a timer
  tick: [tone(0, 0.05, 900, 0.34, { type: 'triangle' })],
  tickHigh: [tone(0, 0.08, 1300, 0.4, { type: 'triangle' })],
  // it is your turn to draw: a bright two-note chime
  turn: [tone(0, 0.24, HZ.E5, 0.3), tone(0.12, 0.38, HZ.A5, 0.3), tone(0.12, 0.38, HZ.E6, 0.07, { type: 'triangle' })],
  // the vote has opened
  bell: [tone(0, 0.5, HZ.G5, 0.22), tone(0, 0.5, HZ.G5 * 2.01, 0.05), tone(0.16, 0.6, HZ.D5, 0.22)],
  // a card turning over
  flip: [whoosh(0, 0.28, 500, 3000, 0.22, 1.2), tone(0.2, 0.14, 170, 0.35, { to: 90 })],
  // the imposter stamp landing: a thud with an uneasy interval on top
  stamp: [
    tone(0, 0.34, 140, 0.55, { to: 45 }),
    whoosh(0, 0.12, 3000, 600, 0.3, 0.8),
    tone(0.02, 0.5, 233, 0.12, { type: 'triangle' }),
    tone(0.02, 0.5, 330, 0.12, { type: 'triangle' }),
  ],
  // the imposter has been caught
  caught: [tone(0, 0.32, HZ.B4, 0.25, { to: 330, type: 'triangle' }), tone(0.05, 0.45, 165, 0.3)],
  // your side won the round
  win: [
    tone(0, 0.2, HZ.C5, 0.26, { type: 'triangle' }),
    tone(0.08, 0.2, HZ.E5, 0.26, { type: 'triangle' }),
    tone(0.16, 0.2, HZ.G5, 0.26, { type: 'triangle' }),
    tone(0.24, 0.55, HZ.C6, 0.26, { type: 'triangle' }),
    tone(0.24, 0.55, HZ.C5, 0.14),
  ],
  // your side lost the round: a gentle step down, not a buzzer
  lose: [
    tone(0, 0.24, HZ.G4, 0.26),
    tone(0.16, 0.26, HZ.E4, 0.26),
    tone(0.34, 0.55, HZ.C4, 0.26),
    tone(0.34, 0.55, HZ.C5, 0.07, { type: 'triangle' }),
  ],
  // you won the whole game
  fanfare: [
    tone(0, 0.2, HZ.C5, 0.24, { type: 'triangle' }),
    tone(0.1, 0.2, HZ.E5, 0.24, { type: 'triangle' }),
    tone(0.2, 0.2, HZ.G5, 0.24, { type: 'triangle' }),
    tone(0.3, 0.25, HZ.C6, 0.24, { type: 'triangle' }),
    tone(0.42, 1.1, HZ.C5, 0.14),
    tone(0.42, 1.1, HZ.E5, 0.14),
    tone(0.42, 1.1, HZ.G5, 0.14),
    tone(0.42, 1.1, HZ.C6, 0.14),
    tone(0.42, 0.9, HZ.E6, 0.06, { type: 'triangle' }),
  ],
  // the game is over and you didn't win
  end: [tone(0, 0.3, HZ.C5, 0.22), tone(0.18, 0.6, HZ.G4, 0.22)],
}

// Turn one sound into audio nodes that feed `destination`, starting at `when` (seconds on the
// context's clock). Each note has a short fade in and a smooth fade out: without them, switching a
// tone on or off mid-wave is heard as a click.
export function schedule(ctx, destination, name, when = ctx.currentTime) {
  for (const part of SOUNDS[name] ?? []) {
    const start = when + part.t
    const end = start + part.dur

    const envelope = ctx.createGain()
    envelope.gain.setValueAtTime(0, start)
    envelope.gain.linearRampToValueAtTime(part.gain, start + Math.min(0.01, part.dur / 4))
    envelope.gain.exponentialRampToValueAtTime(0.0001, end)
    envelope.gain.setValueAtTime(0, end)
    envelope.connect(destination)

    if (part.kind === 'tone') {
      const osc = ctx.createOscillator()
      osc.type = part.type
      osc.frequency.setValueAtTime(part.freq, start)
      if (part.to) osc.frequency.exponentialRampToValueAtTime(part.to, end)
      osc.connect(envelope)
      osc.start(start)
      osc.stop(end + 0.02)
    } else {
      const source = ctx.createBufferSource()
      source.buffer = noiseBuffer(ctx)
      const filter = ctx.createBiquadFilter()
      filter.type = 'bandpass'
      filter.Q.value = part.q
      filter.frequency.setValueAtTime(part.from, start)
      filter.frequency.exponentialRampToValueAtTime(part.to, end)
      source.connect(filter)
      filter.connect(envelope)
      source.start(start)
      source.stop(end + 0.02)
    }
  }
}

const noiseBuffers = new WeakMap()
function noiseBuffer(ctx) {
  if (!noiseBuffers.has(ctx)) {
    const buffer = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate)
    const data = buffer.getChannelData(0)
    for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1
    noiseBuffers.set(ctx, buffer)
  }
  return noiseBuffers.get(ctx)
}

// --- playing live ---

export const muted = writable(loadMuted())
muted.subscribe(saveMuted)

let audio = null // { ctx, master }, created the first time a sound is wanted

function ensureAudio() {
  if (audio) return audio
  const Context = window.AudioContext || window.webkitAudioContext
  if (!Context) return null
  const ctx = new Context()
  const master = ctx.createGain()
  master.gain.value = MASTER_GAIN
  // a limiter, so that several sounds at once can never be louder than intended
  const limiter = ctx.createDynamicsCompressor()
  master.connect(limiter)
  limiter.connect(ctx.destination)
  audio = { ctx, master }
  return audio
}

// Browsers only allow sound after the person has interacted with the page. Call this from any
// click or key press so audio is ready by the time the game wants it.
export function unlock() {
  try {
    const a = ensureAudio()
    if (a && a.ctx.state === 'suspended') a.ctx.resume()
  } catch {}
}

const lastPlayed = {}

export function play(name) {
  if (get(muted) || !SOUNDS[name]) return
  try {
    const a = ensureAudio()
    if (!a) return
    // the same sound twice in a few milliseconds is a glitch (two updates in one go), not intent
    const now = performance.now()
    if (now - (lastPlayed[name] ?? -Infinity) < 60) return
    lastPlayed[name] = now
    if (a.ctx.state === 'suspended') a.ctx.resume()
    schedule(a.ctx, a.master, name, a.ctx.currentTime + 0.01)
  } catch {
    // sound is a nicety: it must never be able to break the game
  }
}

export function toggleMuted() {
  const next = !get(muted)
  muted.set(next)
  if (!next) play('select') // let them hear that it's back on
}
