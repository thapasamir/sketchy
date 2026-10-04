<script>
  import Card from './Card.svelte'

  export let room
  export let playerId
  // who I voted for (or null), and what to do when I pick someone
  export let vote = null
  export let castVote = () => {}

  // Only the people playing the round vote and are voted for. Someone who arrived mid-game is
  // watching: they can see the vote happen, but have no vote.
  $: contestants = room.players.filter(p => !p.spectator)
  $: iAmWatching = room.players.find(p => p.id === playerId)?.spectator
  $: candidates = contestants.filter(p => p.id !== playerId)
  $: voted = room.vote?.voted ?? []
  $: here = contestants.filter(p => p.connected).length
</script>

<Card id="vote-panel" class="animate-rise !p-4">
  <div class="mb-3 flex items-baseline justify-between gap-3">
    <h3 class="font-display text-lg">Who is the imposter?</h3>
    <span id="vote-count" class="font-stamp text-xs text-riso-muted">{voted.length} of {here} voted</span>
  </div>

  {#if iAmWatching}
    <p id="vote-watching" class="font-stamp text-sm text-riso-muted">
      You're watching this round, so you don't vote. You'll play from the next one.
    </p>
  {:else}
  <div class="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-1">
    {#each candidates as player (player.id)}
      <button
        type="button"
        data-vote={player.name}
        aria-pressed={vote === player.id}
        on:click={() => castVote(player.id)}
        class="flex min-h-12 cursor-pointer items-center gap-2.5 rounded-[3px] border-2 px-3 py-2 text-left transition active:scale-[0.97] {vote === player.id
          ? 'animate-pop border-riso-ink bg-riso-yellow shadow-[3px_3px_0_rgb(0_0_0/0.15)]'
          : 'border-riso-line bg-white/60 hover:border-riso-ink'} {player.connected ? '' : 'opacity-60'}">
        <span
          class="h-5 w-5 shrink-0 rounded-full border border-riso-ink/60"
          style="background:{player.color}"
          aria-hidden="true"></span>
        <span class="min-w-0 flex-1 break-words text-sm">{player.name}</span>
        {#if vote === player.id}
          <span class="font-stamp text-xs uppercase tracking-wider">your vote</span>
        {/if}
      </button>
    {/each}
  </div>

    <p class="mt-3 font-stamp text-xs text-riso-muted">
      {#if vote}
        You can change your vote until time runs out.
      {:else}
        Look at the picture. Whose drawing doesn't fit the word?
      {/if}
    </p>
  {/if}
</Card>
