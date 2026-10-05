<script>
  import { fly } from 'svelte/transition'

  // `onkick(playerId)` is only called once the host has confirmed
  let { players, hostId, playerId, canKick = false, onkick } = $props()

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
</script>

<h3 class="mb-4 mt-8 font-display text-2xl sm:text-3xl">Players ({players.length})</h3>
<ul class="flex flex-col gap-2" id="player-list">
  {#each players as player (player.id)}
    <li
      in:fly={{ y: 10, duration: 260 }}
      data-player={player.name}
      class="flex items-center justify-between gap-3 rounded-[2px] border-l-4 p-3 transition-opacity {player.id === hostId
        ? 'border-riso-pink bg-riso-pink/5'
        : 'border-riso-blue bg-riso-blue/5'} {player.connected ? '' : 'opacity-50'}">
      <span class="min-w-0 break-words">
        {player.name}
        {#if player.id === hostId}<span class="font-stamp text-xs text-riso-pink mix-blend-multiply">(Host)</span>{/if}
        {#if player.id === playerId}<span class="font-stamp text-xs text-riso-muted">(You)</span>{/if}
        {#if !player.connected}<span class="font-stamp text-xs text-riso-muted">(away)</span>{/if}
        {#if player.ready && player.id !== hostId}<span class="font-stamp text-xs text-riso-blue">(ready)</span>{/if}
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
