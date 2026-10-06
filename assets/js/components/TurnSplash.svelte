<script>
  import { fade } from 'svelte/transition'

  // "Your turn!" across the screen for a moment, with what to draw, when the pen comes to you. People
  // look away while others draw, so the turn has to announce itself, and the word is right there so
  // there is no hunting for it. It never takes a tap: the pen is already yours underneath it.
  export let secret = null
</script>

<div
  id="turn-splash"
  role="status"
  out:fade={{ duration: 250 }}
  class="pointer-events-none fixed inset-x-0 top-1/4 z-50 grid place-items-center px-4">
  <div class="animate-pop rotate-[1.5deg] border-4 border-riso-ink bg-riso-yellow px-8 py-4 text-center shadow-[6px_6px_0_rgb(0_0_0/0.2)]">
    <div class="font-display text-[clamp(2rem,9vw,3.5rem)] leading-none">Your turn!</div>
    {#if secret}
      <div class="mt-2 font-stamp text-sm">
        {#if secret.role === 'imposter'}
          Blend in. Your clue: <b class="font-display text-base">{secret.hint}</b>
        {:else}
          Draw: <b class="font-display text-xl text-riso-blue">{secret.word}</b>
        {/if}
      </div>
    {/if}
  </div>
</div>
