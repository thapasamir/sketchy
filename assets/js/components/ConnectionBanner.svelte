<script>
  // Says so when this browser has lost the game (a phone changing network, a lift, a tunnel), so
  // nobody sits at a frozen screen wondering. 'offline' stays until it mends; 'back' shows for a
  // moment. Out of the way of taps, and read out to a screen reader.
  let { state = 'online' } = $props()
</script>

<div id="connection" role="status" aria-live="polite" data-state={state} class="pointer-events-none fixed inset-x-0 top-0 z-[60] flex justify-center px-4 pt-2">
  {#if state === 'offline'}
    <div class="animate-rise flex items-center gap-2.5 rounded-full border-2 border-riso-stamp bg-white px-4 py-2 font-stamp text-sm text-riso-stamp shadow-[3px_3px_0_rgb(0_0_0/0.15)]">
      <span aria-hidden="true" class="h-2.5 w-2.5 animate-pulse rounded-full bg-riso-stamp"></span>
      Connection lost. Reconnecting…
    </div>
  {:else if state === 'back'}
    <div class="animate-rise flex items-center gap-2.5 rounded-full border-2 border-riso-blue bg-white px-4 py-2 font-stamp text-sm text-riso-blue shadow-[3px_3px_0_rgb(0_0_0/0.15)]">
      <span aria-hidden="true" class="h-2.5 w-2.5 rounded-full bg-riso-blue"></span>
      Back online
    </div>
  {/if}
</div>
