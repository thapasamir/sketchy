<script>
  import { muted, toggleMuted } from '../lib/sound.js'

  // Sound on/off, and the rules. Floating in the corner on the pages with no header; inside a
  // header (`inline`) in the room, where floating buttons would sit on top of the content as it
  // scrolls under them. `onhelp()` opens the rules.
  let { onhelp = () => {}, inline = false } = $props()

  const base =
    'grid cursor-pointer place-items-center rounded-[3px] border-2 border-riso-ink bg-riso-paper/95 text-riso-ink transition hover:bg-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-riso-blue'
  const floating = `h-11 w-11 shadow-[3px_3px_0_rgb(0_0_0/0.12)] hover:-translate-x-0.5 hover:-translate-y-0.5`
  // as big as the Leave button beside them, so they are as easy to hit
  const inHeader = 'h-11 w-11'
  let look = $derived(`${base} ${inline ? inHeader : floating}`)
</script>

<!-- (--dock-h: when the vote is pinned to the bottom of a phone, the floating ones ride above it) -->
<div
  id={inline ? 'header-controls' : undefined}
  class={inline ? 'flex gap-2' : 'fixed bottom-4 right-4 z-30 flex gap-2'}
  style={inline ? undefined : 'margin-bottom: calc(env(safe-area-inset-bottom) + var(--dock-h, 0px))'}>
  <button
    type="button"
    id="sound-toggle"
    class={look}
    aria-pressed={$muted}
    aria-label={$muted ? 'Sound is off. Turn sound on' : 'Sound is on. Turn sound off'}
    title={$muted ? 'Sound off' : 'Sound on'}
    onclick={toggleMuted}>
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path d="M4 9.5v5h3.5L12 18.5v-13L7.5 9.5H4z" fill="currentColor" />
      {#if $muted}
        <path d="M16 9.5l5 5M21 9.5l-5 5" />
      {:else}
        <path d="M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11" />
      {/if}
    </svg>
  </button>

  <button type="button" id="help-button" class="{look} font-display text-xl" aria-label="How to play" title="How to play" onclick={() => onhelp()}>
    ?
  </button>
</div>
