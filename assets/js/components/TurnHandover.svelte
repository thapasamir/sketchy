<script>
  import { onMount } from 'svelte'
  import Marker from './Marker.svelte'

  // The pen has changed hands, and the picture says so: a ring in the new drawer's colour around it,
  // and their name at the top, for a moment. Over the picture, never in the way of a tap. (The
  // drawer themselves gets "Your turn!" instead, see TurnSplash.)
  let { player } = $props()

  let visible = $state(true)
  onMount(() => {
    const timer = setTimeout(() => (visible = false), 1700)
    return () => clearTimeout(timer)
  })
</script>

{#if visible && player}
  <div id="turn-handover" data-drawer={player.name} class="pointer-events-none absolute inset-0 z-10 animate-handover" aria-hidden="true">
    <div class="absolute inset-0 rounded-[3px] border-[6px]" style="border-color:{player.color ?? 'var(--color-riso-ink)'}"></div>
    <div class="absolute left-1/2 top-3 flex -translate-x-1/2 items-center gap-2 rounded-full border-2 border-riso-ink bg-riso-paper px-3 py-1 shadow-[3px_3px_0_rgb(0_0_0/0.15)]">
      <Marker {player} size={26} />
      <span class="max-w-40 truncate font-display text-sm">{player.name}</span>
    </div>
  </div>
{/if}
