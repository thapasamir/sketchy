<script>
  import Button from './Button.svelte'
  import Card from './Card.svelte'
  import Confetti from './Confetti.svelte'
  import ChatPanel from './ChatPanel.svelte'

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
</script>

{#if iWon}
  <Confetti />
{/if}

<div class="mx-auto flex w-full max-w-lg flex-col gap-4">
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
          <span class="h-4 w-4 shrink-0 rounded-full border border-riso-ink/60" style="background:{player.color}" aria-hidden="true"></span>
          <span class="min-w-0 flex-1 break-words">
            {player.name}
            {#if player.id === playerId}<span class="font-stamp text-xs text-riso-muted">(You)</span>{/if}
          </span>
          <span class="font-display text-xl tabular-nums">{player.score}</span>
        </li>
      {/each}
    </ol>
  </Card>

  {#if room.chat_open}
    <ChatPanel {messages} players={room.players} {playerId} send={sendChat} error={chatError} hint="Good game? Say so." />
  {/if}

  {#if error}
    <p class="text-center font-stamp text-sm text-riso-stamp" role="alert">{error}</p>
  {/if}

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
