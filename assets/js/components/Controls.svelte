<script>
  import { createEventDispatcher } from 'svelte'
  import { muted, toggleMuted } from '../lib/sound.js'

  const dispatch = createEventDispatcher()

  const button =
    'grid h-11 w-11 cursor-pointer place-items-center rounded-[3px] border-2 border-riso-ink bg-riso-paper/95 text-riso-ink shadow-[3px_3px_0_rgb(0_0_0/0.12)] transition hover:-translate-x-0.5 hover:-translate-y-0.5 hover:bg-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-riso-blue'
</script>

<!-- Always within reach: sound on/off, and the rules. Fixed to the corner, out of the way of play. -->
<div class="fixed bottom-4 right-4 z-30 flex gap-2" style="margin-bottom: env(safe-area-inset-bottom)">
  <button
    type="button"
    id="sound-toggle"
    class={button}
    aria-pressed={$muted}
    aria-label={$muted ? 'Sound is off. Turn sound on' : 'Sound is on. Turn sound off'}
    title={$muted ? 'Sound off' : 'Sound on'}
    on:click={toggleMuted}>
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path d="M4 9.5v5h3.5L12 18.5v-13L7.5 9.5H4z" fill="currentColor" />
      {#if $muted}
        <path d="M16 9.5l5 5M21 9.5l-5 5" />
      {:else}
        <path d="M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11" />
      {/if}
    </svg>
  </button>

  <button
    type="button"
    id="help-button"
    class="{button} font-display text-xl"
    aria-label="How to play"
    title="How to play"
    on:click={() => dispatch('help')}>
    ?
  </button>
</div>
