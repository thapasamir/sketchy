<script>
  import Button from './Button.svelte'
  import Card from './Card.svelte'
  import CountUp from './CountUp.svelte'
  import Marker from './Marker.svelte'
  import { TIMING } from '../lib/cues.js'

  export let room
  export let playerId
  export let isHost = false
  export let nextRound = () => {}

  $: result = room.result
  $: name = id => result.names[id] ?? 'Someone'
  // only people who played (someone watching has no score yet)
  $: ranking = room.players.filter(p => !p.spectator).sort((a, b) => b.score - a.score)
  $: lastRound = room.round >= room.rounds
  $: top = ranking[0]?.score
  // highlight the leader(s), unless everyone is level (then it says nothing)
  $: leaders = ranking.filter(p => p.score === top).length
  $: showLeaders = top > 0 && leaders < ranking.length

  // who voted for this player, as the players themselves (someone who has since left is skipped)
  $: voters = id =>
    Object.entries(result.votes)
      .filter(([, target]) => target === id)
      .map(([voter]) => room.players.find(p => p.id === voter))
      .filter(Boolean)

  // The result is revealed in order, for suspense: the imposter's name stamps in first, then the
  // word, then how each person voted, then the points. (TIMING.nameStart is shared with the sounds.)
  const WORD_AT = TIMING.nameImpact + 300
  const GUESS_AT = WORD_AT + 400
  const VOTES_AT = GUESS_AT + 200
  const SCORES_AT = VOTES_AT + 300
  const STEP = 90
</script>

<div class="flex flex-col gap-4 lg:gap-3">
  <Card id="reveal-card" class="animate-rise !p-4 text-center lg:!p-3">
    <!-- side by side where it is narrow but wide enough (a phone), stacked in the sidebar -->
    <div class="grid grid-cols-2 gap-3 lg:block">
      <div>
        <div class="font-stamp text-xs uppercase tracking-widest text-riso-muted">The imposter was</div>
        <div id="reveal-imposter" class="mt-1 flex items-center justify-center gap-2">
          <span
            style="animation-delay:{TIMING.nameStart}ms"
            class="inline-flex animate-stamp items-center gap-2">
            <Marker player={room.players.find(p => p.id === result.imposter_id)} size={28} />
            <span class="break-words font-display text-2xl text-riso-pink mix-blend-multiply">{name(result.imposter_id)}</span>
          </span>
        </div>
      </div>
      <div>
        <div class="font-stamp text-xs uppercase tracking-widest text-riso-muted lg:mt-2">The word was</div>
        <div
          id="reveal-word"
          style="animation-delay:{WORD_AT}ms"
          class="mt-1 animate-pop break-words font-display text-2xl text-riso-blue">
          {result.word}
        </div>
        <div class="mt-1 font-stamp text-xs text-riso-muted">{result.category}</div>
      </div>
    </div>
    {#if result.guess}
      <div id="reveal-guess" style="animation-delay:{GUESS_AT}ms" class="mt-2 animate-rise font-stamp text-xs text-riso-muted">
        {name(result.imposter_id)} guessed: <b class="text-riso-ink">{result.guess}</b>
      </div>
    {/if}
  </Card>

  <!-- the scores, and under each name how they voted: one list instead of two -->
  <Card id="scoreboard" style="animation-delay:{VOTES_AT}ms" class="animate-rise !p-4 lg:!p-3">
    <h3 class="mb-2 font-display text-lg">Scores</h3>
    <ol class="flex flex-col gap-1.5 lg:gap-1">
      {#each ranking as player, i (player.id)}
        {@const gained = result.points[player.id] ?? 0}
        {@const at = SCORES_AT + 100 + i * STEP}
        {@const votedFor = result.votes[player.id]}
        <li
          data-player={player.name}
          data-score={player.score}
          class="flex items-center gap-2.5 rounded-[2px] px-2.5 py-2 lg:py-1.5 {player.score === top && showLeaders
            ? 'bg-riso-yellow/70 ring-2 ring-riso-ink'
            : 'bg-riso-blue/5'}">
          <Marker {player} size={22} />
          <span class="min-w-0 flex-1">
            <span class="block break-words text-sm">
              {player.name}
              {#if player.id === playerId}<span class="font-stamp text-xs text-riso-muted">(You)</span>{/if}
            </span>
            <span
              data-voter={player.name}
              style="animation-delay:{VOTES_AT + 100 + i * STEP}ms"
              class="block animate-fade font-stamp text-[0.7rem] leading-tight text-riso-muted">
              {#if votedFor}
                voted <b class={votedFor === result.imposter_id ? 'text-riso-pink-ink' : 'text-riso-ink'}>{name(votedFor)}</b>
                {#if votedFor === result.imposter_id}<span aria-label="correct">✓</span>{/if}
              {:else}
                didn't vote
              {/if}
            </span>
          </span>
          <!-- the votes this player got, arriving one by one as the faces of whoever cast them -->
          {#if voters(player.id).length}
            <span data-ballots={voters(player.id).length} class="flex shrink-0 -space-x-1.5" title="Votes from {voters(player.id).map(v => v.name).join(', ')}">
              {#each voters(player.id) as voter, k (voter.id)}
                <span data-ballot={voter.name} style="animation-delay:{VOTES_AT + 200 + i * STEP + k * 160}ms" class="animate-ballot rounded-full bg-riso-paper ring-2 ring-riso-paper">
                  <Marker player={voter} size={24} />
                </span>
              {/each}
            </span>
          {/if}
          {#if gained}
            <span data-gained style="animation-delay:{at + 300}ms" class="animate-pop font-stamp text-xs text-riso-blue">+{gained}</span>
          {/if}
          <span class="w-6 text-right font-display text-lg tabular-nums">
            <CountUp from={player.score - gained} to={player.score} delay={at + 300} />
          </span>
        </li>
      {/each}
    </ol>
  </Card>

  <Card id="next-card" class="!p-4 text-center lg:flex lg:flex-wrap lg:items-center lg:justify-between lg:gap-x-3 lg:gap-y-2 lg:!p-3 lg:text-left">
    <p id="next-text" class="font-stamp text-sm text-riso-muted">
      {#if lastRound}
        That was the last round. The final scores are next.
      {:else}
        Round {room.round + 1} of {room.rounds} is next.
      {/if}
    </p>
    {#if isHost}
      <Button id="next-round-button" variant="yellow" class="mt-3 w-full py-2.5 text-base lg:mt-0 lg:w-auto lg:shrink-0 lg:px-4" on:click={nextRound}>
        {lastRound ? 'Final scores now' : 'Next round now'}
      </Button>
    {/if}
  </Card>
</div>
