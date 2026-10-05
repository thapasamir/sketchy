<script>
  import { fly } from 'svelte/transition'
  import Marker from '../Marker.svelte'

  // Who is here. Empty places are shown for the players the game still needs, so the list says how
  // close the room is to starting. `onkick(playerId)` is only called once the host has confirmed.
  let { players, hostId, playerId, canKick = false, onkick, onedit, minPlayers = 3 } = $props()

  // Removing someone takes two clicks so a slip can't kick a friend
  let confirming = $state(null)
  let timer

  function kick(player) {
    clearTimeout(timer)
    if (confirming === player.id) {
      confirming = null
      onkick(player.id)
    } else {
      confirming = player.id
      timer = setTimeout(() => (confirming = null), 3000)
    }
  }

  let missing = $derived(Math.max(0, minPlayers - players.length))
</script>

<div class="mb-3 flex items-baseline justify-between gap-3">
  <h3 class="font-display text-xl">Players</h3>
  <span class="font-stamp text-xs text-riso-muted">{players.length} here{missing > 0 ? `, ${minPlayers} needed` : ''}</span>
</div>

<ul class="flex flex-col gap-2" id="player-list">
  {#each players as player (player.id)}
    <li
      in:fly={{ y: 10, duration: 260 }}
      data-player={player.name}
      class="flex min-h-12 items-center justify-between gap-3 rounded-[2px] border-l-4 px-3 py-2 transition-opacity {player.id === hostId
        ? 'border-riso-pink bg-riso-pink/5'
        : 'border-riso-blue bg-riso-blue/5'} {player.connected ? '' : 'opacity-50'}">
      <span class="flex min-w-0 items-center gap-2.5">
        {#if player.id === playerId && onedit}
          <!-- your own marker is the way to change your look -->
          <button
            type="button"
            id="edit-avatar"
            aria-label="Change your look"
            title="Change your look"
            onclick={onedit}
            class="group relative shrink-0 cursor-pointer rounded-full transition hover:scale-110 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-riso-blue">
            <Marker {player} size={34} />
            <span aria-hidden="true" class="absolute -bottom-1 -right-1 grid h-4 w-4 place-items-center rounded-full border border-riso-ink bg-white text-[0.6rem] leading-none">✎</span>
          </button>
        {:else}
          <Marker {player} size={34} />
        {/if}
        <span class="min-w-0 break-words">
          {player.name}
          {#if player.id === hostId}<span class="font-stamp text-xs text-riso-pink mix-blend-multiply">(Host)</span>{/if}
          {#if player.id === playerId}<span class="font-stamp text-xs text-riso-muted">(You)</span>{/if}
          {#if !player.connected}<span class="font-stamp text-xs text-riso-muted">(away)</span>{/if}
          {#if player.ready && player.id !== hostId}<span class="font-stamp text-xs text-riso-blue">(ready)</span>{/if}
        </span>
      </span>

      {#if canKick && player.id !== playerId}
        <button
          type="button"
          data-kick={player.name}
          onclick={() => kick(player)}
          class="shrink-0 cursor-pointer rounded-[3px] border px-2.5 py-1 font-stamp text-xs {confirming === player.id
            ? 'border-riso-stamp bg-riso-stamp text-white'
            : 'border-riso-line text-riso-muted hover:border-riso-ink hover:text-riso-ink'}">
          {confirming === player.id ? 'Sure?' : 'Remove'}
        </button>
      {/if}
    </li>
  {/each}
</ul>

<!-- places still to fill (not list items: they are not players) -->
{#if missing > 0}
  <div class="mt-2 flex flex-col gap-2" aria-hidden="true">
    {#each Array(missing) as _, i}
      <div class="flex min-h-12 items-center rounded-[2px] border-2 border-dashed border-riso-line px-3 font-stamp text-xs text-riso-muted">
        Waiting for a player…
      </div>
    {/each}
  </div>
{/if}
