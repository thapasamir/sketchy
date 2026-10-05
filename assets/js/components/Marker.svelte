<script>
  import { shapePoints } from '../lib/render.js'
  import { bodyPath } from '../lib/blob.js'
  import FaceEyes from './face/FaceEyes.svelte'
  import FaceMouth from './face/FaceMouth.svelte'
  import FaceHat from './face/FaceHat.svelte'

  // A player. Big enough, they are a little character: a hand-drawn round body in their assigned
  // colour, with their chosen face and hat. Small (and for anyone without a face), they are
  // their assigned colour and shape with their initial: that small form is the one used where
  // there is no room for a face, such as the tags on the drawing, so a player is told apart there by
  // shape as well as colour (colour is never the only clue).
  export let player
  export let size = 20

  // A face needs room: at this size and below there are only a few pixels for each eye.
  const FACE_MIN_SIZE = 24

  // The body is drawn smaller and lower to leave room above it for a hat, and the face and the hat
  // are placed on it.
  const BODY = { scale: 0.72, dy: 0.2 }
  const FACE = { scale: 1.3, dy: -0.02 }
  const HAT_Y = BODY.dy - BODY.scale + 0.05

  $: points = shapePoints(player?.shape)
  $: initial = (player?.name ?? '').trim().charAt(0).toUpperCase()
  $: avatar = player?.avatar
  $: faced = !!avatar && size >= FACE_MIN_SIZE
  $: fill = player?.color ?? '#b9bbb0'
  // each player's own wobble, so a room of round bodies are all different
  $: outline = faced ? bodyPath('circle', player?.id ?? player?.name ?? '') : ''
</script>

<svg
  width={size}
  height={size}
  viewBox="-1.15 -1.15 2.3 2.3"
  class="shrink-0"
  data-marker={player?.shape ?? 'circle'}
  data-faced={faced}
  aria-hidden="true">
  <g transform={faced ? `translate(0 ${BODY.dy}) scale(${BODY.scale})` : undefined}>
    {#if faced}
      <!-- an offset shadow, like a print slightly out of register -->
      <path d={outline} fill="#1b1b1b" opacity="0.2" transform="translate(0.1 0.11)" />
      <path d={outline} {fill} stroke="#1b1b1b" stroke-width="0.15" stroke-linejoin="round" />
      <g transform="translate(0 {FACE.dy}) scale({FACE.scale})">
        <ellipse cx="-0.55" cy="0.18" rx="0.11" ry="0.075" fill="#ff7a9c" opacity="0.5" />
        <ellipse cx="0.55" cy="0.18" rx="0.11" ry="0.075" fill="#ff7a9c" opacity="0.5" />
        <FaceEyes index={avatar.eyes} />
        <FaceMouth index={avatar.mouth} />
      </g>
    {:else if points}
      <polygon points={points.map(p => p.join(',')).join(' ')} {fill} stroke="#1b1b1b" stroke-width="0.14" stroke-linejoin="round" />
    {:else}
      <circle r="1" {fill} stroke="#1b1b1b" stroke-width="0.14" />
    {/if}
  </g>

  {#if faced && avatar.hat > 0}
    <g transform="translate(0 {HAT_Y})"><FaceHat index={avatar.hat} /></g>
  {/if}

  {#if !faced && size >= 18 && initial}
    <text
      x="0"
      y="0.05"
      text-anchor="middle"
      dominant-baseline="middle"
      font-size="1.05"
      font-weight="700"
      font-family="sans-serif"
      fill="#fff"
      stroke="#1b1b1b"
      stroke-width="0.12"
      paint-order="stroke">{initial}</text>
  {/if}
</svg>
