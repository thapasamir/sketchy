<script>
  import { onMount, onDestroy } from 'svelte'
  import Button from './Button.svelte'
  import Card from './Card.svelte'
  import DrawingBoard from './DrawingBoard.svelte'
  import VotePanel from './VotePanel.svelte'
  import GuessPanel from './GuessPanel.svelte'
  import ResultPanel from './ResultPanel.svelte'

  export let room
  export let secret
  export let playerId
  export let store
  export let send = () => {}
  export let undo = () => {}
  export let finishTurn = () => {}
  export let error = ''
  // who I voted for, and how to vote / guess (the voting and guessing phases)
  export let vote = null
  export let castVote = () => {}
  export let submitGuess = () => {}
  // the host can skip the wait after a round's result
  export let isHost = false
  export let nextRound = () => {}

  const BRUSHES = [
    { size: 1, label: 'Thin', px: 6 },
    { size: 2, label: 'Medium', px: 12 },
    { size: 3, label: 'Thick', px: 20 },
  ]

  let size = 2
  let hidden = false

  $: turn = room.turn
  $: phase = room.phase
  $: drawing = phase === 'drawing' && !!turn
  $: result = room.result
  $: iAmImposter = secret?.role === 'imposter'
  // whichever phase is timed says how long is left (turn, vote or guess)
  $: stage = drawing
    ? turn
    : phase === 'voting'
      ? room.vote
      : phase === 'guess'
        ? room.guess
        : phase === 'result' && result?.ms_left != null
          ? result
          : null
  $: byId = Object.fromEntries(room.players.map(p => [p.id, p]))
  $: drawer = turn ? byId[turn.player_id] : null
  $: me = byId[playerId]
  $: myTurn = drawing && turn.player_id === playerId
  $: order = turn ? turn.order.map(id => byId[id]).filter(Boolean) : room.players

  // The server sends how long is left when the turn changes; we count down from there. Counting
  // locally is smooth, and it needs no shared clock between the browser and the server.
  let now = performance.now()
  let deadline = 0
  let total = 1
  let turnKey = ''
  $: if (stage) {
    deadline = performance.now() + stage.ms_left
    const key = `${phase}:${turn?.player_id}:${turn?.lap}`
    if (key !== turnKey) {
      turnKey = key
      total = Math.max(stage.ms_left, 1)
    }
  }
  $: msLeft = Math.max(0, deadline - now)
  $: secondsLeft = Math.ceil(msLeft / 1000)
  $: hurry = !!stage && secondsLeft <= 5

  $: accusedName = result?.accused ? result.names[result.accused] : null
  $: guesserName = byId[room.guess?.guesser_id]?.name ?? 'The imposter'

  function outcomeTitle(result, iAmImposter) {
    switch (result.outcome) {
      case 'escaped':
        if (iAmImposter) return 'You got away with it!'
        return accusedName ? `${accusedName} was innocent. The imposter got away!` : 'No majority. The imposter got away!'
      case 'caught':
        return iAmImposter ? 'You were caught!' : 'You caught the imposter!'
      case 'guessed':
        return iAmImposter ? 'Caught, but you guessed the word!' : 'Caught, but they guessed the word!'
      default:
        return 'The imposter left. The crew wins!'
    }
  }

  let ticker
  onMount(() => (ticker = setInterval(() => (now = performance.now()), 100)))
  onDestroy(() => clearInterval(ticker))

  function onKey(event) {
    if (myTurn && (event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'z') {
      event.preventDefault()
      undo()
    }
  }
</script>

<svelte:window on:keydown={onKey} />

<div class="grid items-start gap-6 lg:grid-cols-[minmax(0,1fr)_17rem] lg:grid-rows-[auto_1fr]">
  <section class="flex min-w-0 flex-col gap-3 lg:col-start-1 lg:row-span-2 lg:row-start-1">
    <div
      id="turn-banner"
      data-phase={phase}
      data-my-turn={myTurn}
      class="overflow-hidden rounded-[3px] border-2 border-riso-ink {myTurn ? 'bg-riso-yellow' : 'bg-white/60'}">
      <div class="flex items-center gap-3 px-4 py-3">
        {#if drawing}
          <span
            class="h-6 w-6 shrink-0 rounded-full border-2 border-riso-ink"
            style="background:{drawer?.color}"
            aria-hidden="true"></span>
          <div class="min-w-0 flex-1">
            <div class="font-stamp text-xs uppercase tracking-widest text-riso-muted">
              Round {room.round} of {room.rounds}
            </div>
            <div id="turn-text" class="truncate font-display text-xl sm:text-2xl">
              {myTurn ? 'Your turn. Draw!' : `${drawer?.name ?? 'Someone'} is drawing`}
            </div>
          </div>
        {:else if phase === 'voting'}
          <div class="min-w-0 flex-1">
            <div class="font-stamp text-xs uppercase tracking-widest text-riso-muted">The drawing is finished</div>
            <div id="turn-text" class="font-display text-xl sm:text-2xl">Who was faking it?</div>
          </div>
        {:else if phase === 'guess'}
          <div class="min-w-0 flex-1">
            <div class="font-stamp text-xs uppercase tracking-widest text-riso-muted">The votes are in</div>
            <div id="turn-text" class="break-words font-display text-xl sm:text-2xl">
              {iAmImposter ? 'You were caught!' : `${guesserName} was caught!`}
            </div>
          </div>
        {:else}
          <div class="min-w-0 flex-1">
            <div class="font-stamp text-xs uppercase tracking-widest text-riso-muted">
              Round {room.round} of {room.rounds} over
            </div>
            <div id="turn-text" class="break-words font-display text-xl sm:text-2xl">
              {outcomeTitle(result, iAmImposter)}
            </div>
          </div>
        {/if}
        {#if stage}
          <div
            id="turn-timer"
            class="font-display text-3xl tabular-nums {hurry ? 'animate-pulse text-riso-stamp' : ''}">
            {secondsLeft}
          </div>
        {/if}
      </div>
      {#if stage}
        <div class="h-1.5 bg-riso-ink/10">
          <div
            class="h-full transition-[width] duration-100 ease-linear {hurry ? 'bg-riso-stamp' : 'bg-riso-ink'}"
            style="width:{(msLeft / total) * 100}%">
          </div>
        </div>
      {/if}
    </div>

    <!-- on a phone the sidebar is far below the canvas, and you need your word while you draw -->
    {#if secret && !hidden && phase !== 'result'}
      <div id="secret-bar" class="flex items-center justify-between gap-3 border-2 border-riso-ink/70 bg-white/60 px-3 py-2 lg:hidden">
        {#if secret.role === 'imposter'}
          <span class="min-w-0 truncate text-sm">
            <span class="font-display text-riso-pink mix-blend-multiply">Imposter</span>
            <span class="font-stamp text-xs text-riso-muted">clue:</span>
            {secret.hint}
          </span>
        {:else}
          <span class="min-w-0 truncate text-sm">
            <span class="font-stamp text-xs text-riso-muted">Your word:</span>
            <span class="font-display text-riso-blue">{secret.word}</span>
          </span>
        {/if}
        <span class="shrink-0 font-stamp text-xs text-riso-muted">{secret.category}</span>
      </div>
    {/if}

    <DrawingBoard {store} {send} me={playerId} color={me?.color} {size} canDraw={myTurn} />

    {#if phase === 'drawing'}
      <div id="toolbar" class="flex min-h-[3.25rem] flex-wrap items-center gap-3">
        {#if myTurn}
          <div class="flex items-center gap-1.5" role="group" aria-label="Brush size">
            {#each BRUSHES as brush}
              <button
                type="button"
                data-brush={brush.size}
                aria-label={brush.label}
                aria-pressed={size === brush.size}
                on:click={() => (size = brush.size)}
                class="grid h-11 w-11 cursor-pointer place-items-center rounded-[3px] border-2 transition {size === brush.size
                  ? 'border-riso-ink bg-white'
                  : 'border-transparent hover:border-riso-line'}">
                <span class="rounded-full" style="width:{brush.px}px;height:{brush.px}px;background:{me?.color}"></span>
              </button>
            {/each}
          </div>
          <Button id="undo-button" class="px-4 py-2 font-stamp text-sm" on:click={undo}>Undo</Button>
          <Button id="done-button" variant="blue" class="ml-auto px-5 py-2 text-base" on:click={finishTurn}>
            I'm done
          </Button>
        {:else}
          <p class="font-stamp text-sm text-riso-muted">
            Watch closely. Does everyone's drawing match the word?
          </p>
        {/if}
      </div>
    {/if}

    {#if error}
      <p class="font-stamp text-sm text-riso-stamp" role="alert">{error}</p>
    {/if}
  </section>

  <!-- under the canvas on a phone; at the top of the sidebar on a wide screen, where the canvas
       would push it below the fold and you'd have to scroll to vote against the clock -->
  {#if phase === 'voting' || phase === 'guess'}
    <div class="lg:col-start-2 lg:row-start-1">
      {#if phase === 'voting'}
        <VotePanel {room} {playerId} {vote} {castVote} />
      {:else}
        <GuessPanel {room} {playerId} {secret} {submitGuess} />
      {/if}
    </div>
  {/if}

  <aside class="flex flex-col gap-4 lg:col-start-2 lg:row-start-2">
    {#if phase === 'result'}
      <ResultPanel {room} {playerId} {isHost} {nextRound} />
    {:else}
    <Card class="!p-4">
      <h3 class="mb-3 font-display text-lg">{drawing ? 'Drawing order' : 'Players'}</h3>
      <ol id="turn-order" class="flex flex-col gap-1.5">
        {#each order as player, i (player.id)}
          <li
            data-player={player.name}
            data-drawing={drawing && player.id === turn.player_id}
            class="flex items-center gap-2.5 rounded-[2px] px-2.5 py-2 {drawing && player.id === turn.player_id
              ? 'bg-riso-yellow/70 ring-2 ring-riso-ink'
              : 'bg-riso-blue/5'} {player.connected ? '' : 'opacity-50'}">
            <span
              class="h-4 w-4 shrink-0 rounded-full border border-riso-ink/60"
              style="background:{player.color}"
              aria-hidden="true"></span>
            <span class="min-w-0 flex-1 break-words text-sm">
              {player.name}
              {#if player.id === playerId}<span class="font-stamp text-xs text-riso-muted">(You)</span>{/if}
              {#if !player.connected}<span class="font-stamp text-xs text-riso-muted">(away)</span>{/if}
            </span>
            {#if drawing && player.id === turn.player_id}
              <span class="font-stamp text-xs uppercase tracking-wider">drawing</span>
            {:else if phase === 'voting' && room.vote?.voted.includes(player.id)}
              <span data-voted class="font-stamp text-xs uppercase tracking-wider text-riso-blue">voted</span>
            {/if}
          </li>
        {/each}
      </ol>
    </Card>

    <Card id="secret-card" class="!p-4 text-center">
      <div class="mb-2 flex items-center justify-between gap-2 text-left">
        <div class="font-stamp text-xs uppercase tracking-widest text-riso-muted">
          Category <span id="secret-category" class="ml-1 text-riso-ink">{secret?.category}</span>
        </div>
        <button
          type="button"
          id="secret-toggle"
          on:click={() => (hidden = !hidden)}
          class="cursor-pointer font-stamp text-xs text-riso-muted underline hover:text-riso-ink">
          {hidden ? 'show' : 'hide'}
        </button>
      </div>

      {#if secret}
        {#if hidden}
          <p class="py-3 font-stamp text-sm text-riso-muted">Your card is hidden.</p>
        {:else if secret.role === 'imposter'}
          <h3 id="secret-role" class="font-display text-xl text-riso-pink mix-blend-multiply">You're the imposter</h3>
          <p class="mt-1 text-xs text-riso-muted">You don't know the word. Your clue:</p>
          <div
            id="secret-hint"
            class="mx-auto mt-2 inline-block border-2 border-dashed border-riso-ink bg-white/60 px-4 py-1.5 font-display text-lg">
            {secret.hint}
          </div>
        {:else}
          <h3 id="secret-role" class="font-stamp text-xs uppercase tracking-widest text-riso-muted">Your secret word</h3>
          <div id="secret-word" class="mt-1 break-words font-display text-2xl text-riso-blue">{secret.word}</div>
        {/if}
      {/if}
    </Card>
    {/if}
  </aside>
</div>
