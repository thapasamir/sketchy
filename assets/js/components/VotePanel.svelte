<script>
  import Card from './Card.svelte'
  import Marker from './Marker.svelte'

  export let room
  export let playerId
  // who I voted for (or null), and what to do when I pick someone
  export let vote = null
  export let castVote = () => {}
  // which player's drawing is picked out on the picture (or null), and how to pick one: looking at
  // someone's lines and voting for them are two steps, so they are two buttons
  export let focus = null
  export let look = () => {}
  // on a phone the players list (with its own "watching" line) sits under the vote instead
  export let showWatchers = false

  // Only the people playing the round vote and are voted for. Someone who arrived mid-game is
  // watching: they can see the vote happen, but have no vote.
  $: contestants = room.players.filter(p => !p.spectator)
  $: iAmWatching = room.players.find(p => p.id === playerId)?.spectator
  $: candidates = contestants.filter(p => p.id !== playerId)
  $: voted = room.vote?.voted ?? []
  $: here = contestants.filter(p => p.connected).length

  // who the vote is still waiting for (only worth saying once I have voted myself)
  $: waiting = contestants.filter(p => p.connected && !voted.includes(p.id)).map(p => p.name)
  $: waitingText =
    waiting.length <= 3 ? waiting.join(', ') : `${waiting.slice(0, 2).join(', ')} and ${waiting.length - 2} more`
</script>

<!-- red and pink, unlike everything else on the screen, so the vote can't be missed -->
<Card id="vote-panel" class="animate-rise !border-riso-stamp !bg-riso-pink/10 !p-4 lg:!p-3">
  <div class="-mx-4 -mt-4 mb-3 bg-riso-stamp px-4 py-1 font-stamp text-xs uppercase tracking-widest text-white lg:-mx-3 lg:-mt-3">
    Vote now
  </div>
  <div class="flex items-baseline justify-between gap-3">
    <h3 class="font-display text-lg">Who is the imposter?</h3>
    <span id="vote-count" class="shrink-0 font-stamp text-xs text-riso-muted">{voted.length} of {here} voted</span>
  </div>

  {#if iAmWatching}
    <p id="vote-watching" class="mt-3 font-stamp text-sm text-riso-muted">
      You're watching this round, so you don't vote. You'll play from the next one.
    </p>
  {:else}
    <!-- what to do, before the list, in the order you do it -->
    <ol id="vote-steps" class="mb-3 mt-1 flex flex-col gap-0.5 font-stamp text-xs text-riso-muted">
      <li><b class="text-riso-ink">1.</b> Tap a name to see only what they drew.</li>
      <li><b class="text-riso-ink">2.</b> Press <b class="text-riso-ink">Vote</b> for the one who doesn't fit the word.</li>
    </ol>

    <div class="flex flex-col gap-1.5">
      {#each candidates as player (player.id)}
        {@const mine = vote === player.id}
        {@const looking = focus === player.id}
        <div
          data-vote-row={player.name}
          class="flex items-stretch gap-1.5 rounded-[3px] border-2 transition {mine
            ? 'border-riso-ink bg-riso-yellow/60 shadow-[3px_3px_0_rgb(0_0_0/0.15)]'
            : looking
              ? 'border-riso-ink bg-white'
              : 'border-riso-line bg-white/60'} {player.connected ? '' : 'opacity-60'}">
          <button
            type="button"
            data-highlight={player.name}
            aria-pressed={looking}
            aria-label="Show only {player.name}'s drawing"
            on:click={() => look(player.id)}
            class="flex min-h-12 min-w-0 flex-1 cursor-pointer items-center gap-2.5 rounded-[2px] py-1.5 pl-2.5 pr-1 text-left active:scale-[0.99] lg:min-h-11">
            <Marker {player} size={26} />
            <span class="min-w-0 flex-1">
              <span class="block break-words text-sm">{player.name}</span>
              {#if looking}
                <span class="block font-stamp text-[0.7rem] uppercase tracking-wider text-riso-muted">showing their drawing</span>
              {:else if voted.includes(player.id)}
                <span data-voted class="block font-stamp text-[0.7rem] uppercase tracking-wider text-riso-blue">has voted</span>
              {/if}
            </span>
          </button>
          <button
            type="button"
            data-vote={player.name}
            aria-pressed={mine}
            aria-label={mine ? `You voted for ${player.name}` : `Vote for ${player.name}`}
            on:click={() => castVote(player.id)}
            class="m-1 min-h-11 min-w-20 shrink-0 cursor-pointer rounded-[2px] border-2 px-3 font-display text-sm transition active:scale-[0.96] {mine
              ? 'animate-pop border-riso-ink bg-riso-ink text-riso-paper'
              : 'border-riso-ink bg-riso-yellow hover:bg-riso-yellow/80'}">
            {mine ? 'Voted ✓' : 'Vote'}
          </button>
        </div>
      {/each}
    </div>

    <p id="vote-status" class="mt-3 font-stamp text-xs text-riso-muted">
      {#if vote}
        <span id="vote-waiting">{waiting.length ? `Waiting for ${waitingText}.` : 'Everyone has voted.'}</span>
        You can change your vote until time runs out.
      {:else}
        You can change your vote until time runs out.
      {/if}
    </p>
  {/if}
  {#if showWatchers && room.players.some(p => p.spectator)}
    <p id="watchers" class="mt-2 font-stamp text-xs text-riso-muted">
      Watching: {room.players.filter(p => p.spectator).map(w => w.name + (w.id === playerId ? ' (you)' : '')).join(', ')}
    </p>
  {/if}
</Card>
