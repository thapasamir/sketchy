<script>
  import { shapePoints } from '../lib/render.js'

  // A player's colour and shape, with their initial inside when it is big enough to read. Colour
  // is never the only clue: the shape and the letter say who it is too.
  export let player
  export let size = 20

  $: points = shapePoints(player?.shape)
  $: initial = (player?.name ?? '').trim().charAt(0).toUpperCase()
</script>

<svg
  width={size}
  height={size}
  viewBox="-1.15 -1.15 2.3 2.3"
  class="shrink-0"
  data-marker={player?.shape ?? 'circle'}
  aria-hidden="true">
  {#if points}
    <polygon points={points.map(p => p.join(',')).join(' ')} fill={player?.color ?? '#b9bbb0'} stroke="#1b1b1b" stroke-width="0.14" stroke-linejoin="round" />
  {:else}
    <circle r="1" fill={player?.color ?? '#b9bbb0'} stroke="#1b1b1b" stroke-width="0.14" />
  {/if}
  {#if size >= 18 && initial}
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
