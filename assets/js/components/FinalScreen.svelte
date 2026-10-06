<script>
  import Button from './Button.svelte'
  import Card from './Card.svelte'
  import Confetti from './Confetti.svelte'
  import ChatPanel from './ChatPanel.svelte'
  import Marker from './Marker.svelte'
  import { awards, recap, nameIn } from '../lib/awards.js'
  import { shareCard } from '../lib/sharecard.js'

  export let room
  export let playerId
  export let isHost = false
  export let playAgain = () => {}
  export let error = ''
  export let messages = []
  export let sendChat = async () => true
  export let chatError = ''

  $: ranking = room.players.filter(p => !p.spectator).sort((a, b) => b.score - a.score)
  $: winners = room.players.filter(p => room.final.winner_ids.includes(p.id))
  $: iWon = room.final.winner_ids.includes(playerId)
  $: hostName = room.players.find(p => p.id === room.host_id)?.name ?? 'The host'

  $: headline =
    winners.length === 0
      ? 'Nobody scored'
      : winners.length === 1
        ? `${winners[0].name} wins!`
        : `A tie: ${winners.map(w => w.name).join(' and ')}`

  // how the game went: a line per round, and the titles worth handing out
  $: rounds = room.final.rounds ?? []
  $: story = recap(rounds)
  $: titles = awards(rounds)
  $: byId = Object.fromEntries(room.players.map(p => [p.id, p]))
  // a player who has left still gets their name (from the round they played)
  const holder = id => byId[id] ?? { id, name: nameIn(rounds, id) }

  // the results as a picture to post
  let note = ''
  let sharing = false
  async function share() {
    sharing = true
    note = ''
    const result = await shareCard({
      headline,
      ranking: ranking.map(p => ({ name: p.name, score: p.score, winner: room.final.winner_ids.includes(p.id) })),
      rounds: room.final.rounds_played,
      url: location.origin,
    }).catch(() => 'failed')
    sharing = false
    note = { shared: 'Shared.', saved: 'Saved as a picture. Post it anywhere.', failed: "Couldn't make the picture." }[result] ?? ''
  }
</script>

{#if iWon}
  <Confetti />
{/if}

<!-- the results on the left and the chat beside them, like the game and the lobby -->
<div class="grid grid-cols-[minmax(0,1fr)] items-start gap-6 {room.chat_open ? 'lg:grid-cols-[minmax(0,1fr)_21rem]' : 'mx-auto max-w-2xl'}">
<div class="flex min-w-0 flex-col gap-4">
  <Card id="final-banner" class="text-center">
    <div class="font-stamp text-xs uppercase tracking-widest text-riso-muted">
      Game over after {room.final.rounds_played} {room.final.rounds_played === 1 ? 'round' : 'rounds'}
    </div>
    <h2
      id="final-headline"
      style="animation-delay:250ms"
      class="mt-2 animate-stamp break-words font-display text-3xl text-riso-pink mix-blend-multiply sm:text-4xl">
      {headline}
    </h2>
    {#if iWon}
      <p class="mt-2 font-stamp text-sm text-riso-muted">That's you. Well played.</p>
    {/if}
  </Card>

  {#if titles.length}
    <div id="final-awards" class="grid gap-3 sm:[grid-template-columns:repeat(var(--n),minmax(0,1fr))]" style="--n:{Math.min(titles.length, 3)}">
      {#each titles as award, i (award.key)}
        <Card data-award={award.key} class="animate-rise !p-3 text-center" style="animation-delay:{500 + i * 150}ms">
          <div class="font-stamp text-[0.7rem] uppercase tracking-widest text-riso-muted">{award.title}</div>
          <div class="mt-2 flex flex-wrap items-center justify-center gap-x-3 gap-y-1">
            {#each award.ids as id}
              <span class="flex items-center gap-1.5">
                <Marker player={holder(id)} size={34} />
                <b class="break-words font-display text-lg">{holder(id).name}</b>
              </span>
            {/each}
          </div>
          <p class="mt-1 font-stamp text-xs text-riso-muted">{award.blurb}</p>
        </Card>
      {/each}
    </div>
  {/if}

  <Card id="final-scores" class="!p-4">
    <h3 class="mb-3 font-display text-lg">Final scores</h3>
    <ol class="flex flex-col gap-1.5">
      {#each ranking as player, i (player.id)}
        <li
          data-player={player.name}
          data-score={player.score}
          style="animation-delay:{700 + i * 110}ms"
          data-winner={room.final.winner_ids.includes(player.id)}
          class="flex animate-rise items-center gap-2.5 rounded-[2px] px-2.5 py-2.5 {room.final.winner_ids.includes(player.id)
            ? 'bg-riso-yellow/70 ring-2 ring-riso-ink'
            : 'bg-riso-blue/5'} {player.connected ? '' : 'opacity-50'}">
          <span class="w-5 font-stamp text-sm text-riso-muted">{i + 1}</span>
          <Marker {player} size={34} />
          <span class="min-w-0 flex-1 break-words">
            {player.name}
            {#if player.id === playerId}<span class="font-stamp text-xs text-riso-muted">(You)</span>{/if}
          </span>
          <span class="font-display text-xl tabular-nums">{player.score}</span>
        </li>
      {/each}
    </ol>
  </Card>

  {#if story.length}
    <Card id="final-recap" class="!p-4">
      <h3 class="mb-3 font-display text-lg">How the rounds went</h3>
      <ol class="flex flex-col gap-1.5">
        {#each story as line (line.round)}
          <li data-round={line.round} data-crew-won={line.crewWon} class="flex flex-wrap items-baseline gap-x-3 gap-y-0.5 rounded-[2px] bg-riso-blue/5 px-2.5 py-2">
            <span class="w-14 shrink-0 font-stamp text-xs uppercase tracking-wider text-riso-muted">Round {line.round}</span>
            <span class="min-w-0 flex-1 text-sm">
              <b class="break-words font-display">{line.imposterName}</b> was the imposter. The word was
              <b class="break-words">{line.word}</b>.
            </span>
            <span class="shrink-0 font-stamp text-xs uppercase tracking-wider {line.crewWon ? 'text-riso-blue' : 'text-riso-stamp'}">{line.text}</span>
          </li>
        {/each}
      </ol>
    </Card>
  {/if}

  {#if error}
    <p class="text-center font-stamp text-sm text-riso-stamp" role="alert">{error}</p>
  {/if}

  <div class="flex flex-col gap-2">
    <Button id="share-results" class="w-full py-3 text-base" disabled={sharing} on:click={share}>
      {sharing ? 'Making the picture…' : 'Share the results'}
    </Button>
    {#if note}<p id="share-note" class="text-center font-stamp text-xs text-riso-muted" role="status">{note}</p>{/if}
  </div>

  {#if isHost}
    <Button id="play-again-button" variant="yellow" class="w-full py-4 text-xl" on:click={playAgain}>
      PLAY AGAIN
    </Button>
  {:else}
    <p id="final-wait" class="text-center font-stamp text-sm text-riso-muted">
      Waiting for {hostName} to start another game.
    </p>
  {/if}
</div>

{#if room.chat_open}
  <aside class="lg:sticky lg:top-4 lg:flex lg:h-[calc(100dvh-7rem)] lg:min-h-[26rem] lg:flex-col">
    <ChatPanel fill {messages} players={room.players} {playerId} send={sendChat} error={chatError} hint="Good game? Say so." />
  </aside>
{/if}
</div>
