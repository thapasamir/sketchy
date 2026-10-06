<script>
  import { fade } from 'svelte/transition'

  // "Time to vote!" across the middle of the screen for a moment, when the drawing ends. The vote
  // is where a round turns, and people looking at the picture miss the banner changing. It never
  // takes a tap: the vote is open underneath it. (GameScreen decides how long it stays.)
</script>

<div
  id="vote-splash"
  role="status"
  out:fade={{ duration: 250 }}
  class="pointer-events-none fixed inset-0 z-50 grid place-items-center bg-riso-pink/20 px-4">
  <div class="animate-pop rotate-[-2deg] border-4 border-riso-stamp bg-riso-paper px-8 py-5 text-center shadow-[6px_6px_0_rgb(0_0_0/0.2)]">
    <div class="font-stamp text-sm uppercase tracking-widest text-riso-stamp">The drawing is finished</div>
    <div class="font-display text-[clamp(2rem,8vw,3.5rem)] leading-none text-riso-stamp">Time to vote!</div>
    <div class="mt-2 font-stamp text-sm text-riso-ink">Who was faking it?</div>
  </div>
</div>
