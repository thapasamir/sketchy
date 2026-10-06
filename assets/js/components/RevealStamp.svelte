<script>
  import { TIMING } from '../lib/cues.js'

  // At the result: an "IMPOSTER" stamp lands on the picture where the imposter began drawing, at
  // the same moment their name stamps into the result card (and the sound plays). It takes no taps
  // and is hidden from screen readers: the result card already says who it was.
  let { store, imposterId } = $props()

  // where their first line began, as 0..1 of the picture; nothing if they never drew
  let start = $derived(store.strokes.find(s => s.player_id === imposterId)?.points[0] ?? null)

  // keep the stamp fully on the picture, whichever edge the line began at
  const clamp = (n, low, high) => Math.min(high, Math.max(low, n))
</script>

{#if start}
  <div
    data-reveal-stamp
    aria-hidden="true"
    class="pointer-events-none absolute -translate-x-1/2 -translate-y-full"
    style="left:{clamp(start[0] * 100, 14, 86)}%; top:{clamp(start[1] * 100 - 3, 12, 100)}%">
    <span
      style="animation-delay:{TIMING.nameStart}ms"
      class="inline-block -rotate-6 animate-stamp whitespace-nowrap rounded-[2px] border-2 border-riso-pink bg-white/85 px-2 py-0.5 font-display text-sm uppercase tracking-wider text-riso-pink-ink shadow-[2px_2px_0_rgb(0_0_0/0.15)]">
      Imposter
    </span>
  </div>
{/if}
