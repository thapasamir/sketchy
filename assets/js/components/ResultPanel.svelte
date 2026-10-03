<script>
  import Card from './Card.svelte'

  export let room
  export let playerId

  $: result = room.result
  $: name = id => result.names[id] ?? 'Someone'
  $: colorOf = id => room.players.find(p => p.id === id)?.color ?? '#999'
  $: voters = Object.keys(result.votes)
  $: ranking = [...room.players].sort((a, b) => b.score - a.score)
  $: top = ranking[0]?.score
  // highlight the leader(s), unless everyone is level (then it says nothing)
  $: leaders = ranking.filter(p => p.score === top).length
  $: showLeaders = top > 0 && leaders < ranking.length
</script>

<div class="flex flex-col gap-4">
  <Card id="reveal-card" class="!p-4 text-center">
    <div class="font-stamp text-xs uppercase tracking-widest text-riso-muted">The imposter was</div>
    <div id="reveal-imposter" class="mt-1 flex items-center justify-center gap-2">
      <span class="h-5 w-5 rounded-full border border-riso-ink/60" style="background:{colorOf(result.imposter_id)}" aria-hidden="true"></span>
      <span class="break-words font-display text-2xl text-riso-pink mix-blend-multiply">{name(result.imposter_id)}</span>
    </div>
    <div class="mt-3 font-stamp text-xs uppercase tracking-widest text-riso-muted">The word was</div>
    <div id="reveal-word" class="mt-1 break-words font-display text-2xl text-riso-blue">{result.word}</div>
    <div class="mt-1 font-stamp text-xs text-riso-muted">{result.category}</div>
    {#if result.guess}
      <div id="reveal-guess" class="mt-3 font-stamp text-xs text-riso-muted">
        {name(result.imposter_id)} guessed: <b class="text-riso-ink">{result.guess}</b>
      </div>
    {/if}
  </Card>

  <Card id="votes-card" class="!p-4">
    <h3 class="mb-2 font-display text-lg">Who voted for whom</h3>
    {#if voters.length === 0}
      <p class="font-stamp text-sm text-riso-muted">Nobody voted.</p>
    {:else}
      <ul class="flex flex-col gap-1.5">
        {#each voters as voter}
          <li data-voter={name(voter)} class="flex items-center gap-2 text-sm">
            <span class="min-w-0 break-words">{name(voter)}</span>
            <span class="text-riso-muted" aria-hidden="true">→</span>
            <span class="min-w-0 break-words {result.votes[voter] === result.imposter_id ? 'font-bold text-riso-pink' : ''}">
              {name(result.votes[voter])}
            </span>
          </li>
        {/each}
      </ul>
    {/if}
  </Card>

  <Card id="scoreboard" class="!p-4">
    <h3 class="mb-2 font-display text-lg">Scores</h3>
    <ol class="flex flex-col gap-1.5">
      {#each ranking as player (player.id)}
        <li
          data-player={player.name}
          data-score={player.score}
          class="flex items-center gap-2.5 rounded-[2px] px-2.5 py-2 {player.score === top && showLeaders
            ? 'bg-riso-yellow/70 ring-2 ring-riso-ink'
            : 'bg-riso-blue/5'}">
          <span class="h-4 w-4 shrink-0 rounded-full border border-riso-ink/60" style="background:{player.color}" aria-hidden="true"></span>
          <span class="min-w-0 flex-1 break-words text-sm">
            {player.name}
            {#if player.id === playerId}<span class="font-stamp text-xs text-riso-muted">(You)</span>{/if}
          </span>
          {#if result.points[player.id]}
            <span data-gained class="font-stamp text-xs text-riso-blue">+{result.points[player.id]}</span>
          {/if}
          <span class="w-6 text-right font-display text-lg tabular-nums">{player.score}</span>
        </li>
      {/each}
    </ol>
  </Card>
</div>
