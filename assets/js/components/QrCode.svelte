<script>
  import { qrPath } from '../lib/qr.js'

  // What the code opens, e.g. the invite link for a room
  export let text
  // what a screen reader hears instead of the picture
  export let label = 'QR code'

  // Error correction M: a smudged screen or a slightly angled camera still scans.
  $: drawing = qrPath(text, 'M')
</script>

<!-- White all round (the "quiet zone" a scanner needs), dark squares in the game's ink. -->
<svg
  viewBox="0 0 {drawing.box} {drawing.box}"
  role="img"
  aria-label={label}
  shape-rendering="crispEdges"
  class="block h-auto w-full rounded-[2px] bg-white">
  <path d={drawing.path} fill="#1b2a52" />
</svg>
