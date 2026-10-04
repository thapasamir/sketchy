<script>
  import { onMount, onDestroy } from 'svelte'
  import Button from './Button.svelte'
  import Card from './Card.svelte'
  import DrawingBoard from './DrawingBoard.svelte'
  import VotePanel from './VotePanel.svelte'
  import GuessPanel from './GuessPanel.svelte'
  import ResultPanel from './ResultPanel.svelte'
  import ChatPanel from './ChatPanel.svelte'
  import Marker from './Marker.svelte'
  import ReactionBar from './ReactionBar.svelte'
  import ReactionLayer from './ReactionLayer.svelte'
  import { play } from '../lib/sound.js'
  import { tickFor } from '../lib/cues.js'

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
  // chat is open for the vote and after it (the server decides: see Chat.open?/1)
  export let messages = []
  export let sendChat = async () => true
  export let chatError = ''
  // emoji reactions floating over the picture, and how to send one
  export let reactions = []
  export let sendReaction = () => {}

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
  // someone who arrived mid-game only watches until the next round starts
  $: iAmWatching = !!me?.spectator
  $: watchers = room.players.filter(p => p.spectator)
  $: order = turn ? turn.order.map(id => byId[id]).filter(Boolean) : room.players.filter(p => !p.spectator)

  // --- looking back over the drawing ---
  //
  // Once the drawing is finished (the vote, the guess, the result) anyone can pick a player, from
  // the list under the picture or by tapping a line on it, and only their strokes stay clear.
  let focus = null
  $: looking = phase === 'voting' || phase === 'guess' || phase === 'result'
  $: if (!looking) focus = null
  $: contestants = room.players.filter(p => !p.spectator && p.color)
  const toggleFocus = id => (focus = focus === id || id === null ? null : id)

  // The server sends how long is left when the turn changes; we count down from there. Counting
  // locally is smooth, and it needs no shared clock between the browser and the server.
  let now = performance.now()
  let deadline = 0
  let total = 1
  let turnKey = ''
  $: if (stage) {
    deadline = performance.now() + stage.ms_left
    const key = `${phase}:${turn?.n}`
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

  // a tick for each of the last seconds, where the clock is pressing on you
  let lastTick = null
  $: {
    const tick = tickFor({ phase, myTurn, secondsLeft })
    if (tick && secondsLeft !== lastTick) play(tick)
    lastTick = secondsLeft
  }

  // a new banner pops in whenever the moment changes: a new turn, the vote, the guess, the result
  $: bannerKey = `${phase}:${turn?.n}`

  // --- full screen, for phones ---
  //
  // On a phone the drawing is the whole point of the game, and in the normal layout it gets a
  // third of the screen. So on your turn it takes over the whole screen (a slim bar with the timer
  // and your word, the picture, and the tools under your thumb), and it hands the screen back when
  // the turn is over. Anyone can also expand the picture to see it bigger.
  let narrow = false
  let immersive = false
  let immersiveAuto = false // true when it opened by itself for your turn (so it closes by itself)
  let handledTurn = null

  onMount(() => {
    const query = window.matchMedia('(max-width: 1023px)')
    const update = () => (narrow = query.matches)
    update()
    query.addEventListener('change', update)
    return () => query.removeEventListener('change', update)
  })

  // your turn, on a phone: the picture fills the screen (once per turn, so closing it stays closed)
  $: if (drawing && myTurn && narrow && turn.n !== handledTurn) {
    handledTurn = turn.n
    immersive = true
    immersiveAuto = true
  }
  // it never outlives the moment: when it is no longer your turn, or the drawing is over
  $: if (immersive && immersiveAuto && !myTurn) immersive = false
  $: if (immersive && phase !== 'drawing') immersive = false
  // and on a big screen (or after rotating to one) there is nothing to expand
  $: if (!narrow) immersive = false
  // no scrolling the page behind it
  $: if (typeof document !== 'undefined') document.body.style.overflow = immersive ? 'hidden' : ''

  function expand() {
    immersive = true
    immersiveAuto = false
  }

  function collapse() {
    immersive = false
    immersiveAuto = false
  }

  let ticker
  onMount(() => (ticker = setInterval(() => (now = performance.now()), 100)))
  onDestroy(() => {
    clearInterval(ticker)
    if (typeof document !== 'undefined') document.body.style.overflow = ''
  })

  function onKey(event) {
    if (myTurn && (event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'z') {
      event.preventDefault()
      undo()
    }
  }
</script>

<svelte:window on:keydown={onKey} />

<div class="grid items-start gap-6 lg:grid-cols-[minmax(0,1fr)_17rem] lg:grid-rows-[auto_1fr]">
  <section
    class="flex min-w-0 flex-col gap-3 lg:col-start-1 lg:row-span-2 lg:row-start-1 {immersive
      ? 'immersive-board animate-fade fixed inset-0 z-40 !gap-2 bg-riso-paper'
      : ''}"
    style={immersive
      ? 'height:100dvh; padding:max(0.5rem, env(safe-area-inset-top)) max(0.5rem, env(safe-area-inset-right)) max(0.5rem, env(safe-area-inset-bottom)) max(0.5rem, env(safe-area-inset-left))'
      : ''}>
    {#key bannerKey}
    <div
      id="turn-banner"
      data-phase={phase}
      data-my-turn={myTurn}
      class="overflow-hidden rounded-[3px] border-2 border-riso-ink {phase === 'guess' ? 'animate-shake' : 'animate-pop'} {myTurn ? 'bg-riso-yellow' : 'bg-white/60'}">
      <div class="flex items-center gap-3 {immersive ? 'px-3 py-2' : 'px-4 py-3'}">
        {#if drawing}
          <Marker player={drawer} size={30} />
          <div class="min-w-0 flex-1">
            <div class="font-stamp text-xs uppercase tracking-widest text-riso-muted" class:hidden={immersive}>
              Round {room.round} of {room.rounds}{#if turn.laps > 1}&nbsp;· Lap {turn.lap} of {turn.laps}{/if}
            </div>
            <div id="turn-text" class="font-display {immersive ? 'text-lg leading-tight' : 'truncate text-xl sm:text-2xl'}">
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
            class="font-display tabular-nums {immersive ? 'text-2xl' : 'text-3xl'} {hurry ? 'animate-pulse text-riso-stamp' : ''}">
            {secondsLeft}
          </div>
        {/if}
        {#if immersive}
          <button
            type="button"
            id="immersive-close"
            aria-label="Leave full screen"
            on:click={collapse}
            class="grid h-10 w-10 shrink-0 cursor-pointer place-items-center rounded-[3px] border-2 border-riso-ink bg-riso-paper font-display text-xl">
            ×
          </button>
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
    {/key}

    {#if iAmWatching}
      <p
        id="spectator-note"
        class="shrink-0 border-2 border-dashed border-riso-ink bg-riso-yellow/40 px-3 py-2 text-center font-stamp text-sm">
        You joined after the game began, so you're watching. You'll play from the next round.
      </p>
    {/if}

    <!-- on a phone the sidebar is far below the canvas, and you need your word while you draw -->
    {#if secret && !hidden && phase !== 'result'}
      <div id="secret-bar" class="flex shrink-0 items-center justify-between gap-3 border-2 border-riso-ink/70 bg-white/60 px-3 py-2 lg:hidden">
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

    <!-- The picture is square and as big as the space allows: the full width, but never taller than the screen
         (so it never needs scrolling to reach). Full screen: the biggest square that fits what is left. -->
    <div class="board-area">
      <div
        class="board-slot relative"
        style={immersive
          ? 'width:min(100%, calc(100dvh - 17rem)); margin-inline:auto'
          : 'width:min(100%, max(18rem, calc(100dvh - 17rem))); margin-inline:auto'}>
        <DrawingBoard
          {store}
          {send}
          me={playerId}
          color={me?.color}
          {size}
          canDraw={myTurn}
          pickable={looking}
          {focus}
          players={looking ? contestants : null}
          on:pick={e => toggleFocus(e.detail)} />
        <ReactionLayer {reactions} />

        {#if !immersive}
          <button
            type="button"
            id="expand-button"
            aria-label="Expand the drawing to full screen"
            on:click={expand}
            class="absolute right-2 top-2 grid h-10 w-10 cursor-pointer place-items-center rounded-[3px] border-2 border-riso-ink bg-riso-paper/90 transition hover:bg-white lg:hidden">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5" />
            </svg>
          </button>
        {/if}
      </div>
    </div>

    {#if looking}
      <div id="highlight-legend" class="shrink-0">
        <div class="flex flex-wrap gap-1.5" role="group" aria-label="Show one player's drawing">
          {#each contestants as player (player.id)}
            <button
              type="button"
              data-highlight={player.name}
              aria-pressed={focus === player.id}
              on:click={() => toggleFocus(player.id)}
              class="flex min-h-9 cursor-pointer items-center gap-1.5 rounded-full border-2 py-1 pl-1.5 pr-3 text-sm transition active:scale-[0.97] {focus === player.id
                ? 'border-riso-ink bg-riso-yellow'
                : 'border-riso-line bg-white/60 hover:border-riso-ink'} {focus && focus !== player.id ? 'opacity-60' : ''}">
              <Marker {player} size={22} />
              <span class="break-words">{player.name}</span>
            </button>
          {/each}
        </div>
        <p class="mt-1.5 font-stamp text-xs text-riso-muted">
          {focus ? 'Tap the name again, or empty paper, to see everything.' : 'Tap a name, or a line, to see only their drawing.'}
        </p>
      </div>
    {/if}

    {#if phase === 'drawing'}
      <div id="toolbar" class="flex min-h-[3.25rem] shrink-0 flex-wrap items-center gap-3">
        {#if myTurn}
          <div class="flex items-center gap-1.5" role="group" aria-label="Brush size">
            {#each BRUSHES as brush}
              <button
                type="button"
                data-brush={brush.size}
                aria-label={brush.label}
                aria-pressed={size === brush.size}
                on:click={() => {
                  size = brush.size
                  play('select')
                }}
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
          <p class="min-w-0 flex-1 font-stamp text-sm text-riso-muted">
            Watch closely. Does everyone's drawing match the word?
          </p>
          <ReactionBar react={sendReaction} />
        {/if}
      </div>
    {:else if phase === 'voting' || phase === 'result'}
      <div class="flex shrink-0 items-center justify-between gap-2">
        <span class="font-stamp text-xs text-riso-muted">React</span>
        <ReactionBar react={sendReaction} />
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
      {#if room.chat_open}
        <ChatPanel {messages} players={room.players} {playerId} send={sendChat} error={chatError} hint="Good round? Say so." />
      {/if}
    {:else}
    {#if phase === 'voting' && room.chat_open}
      <ChatPanel
        {messages}
        players={room.players}
        {playerId}
        send={sendChat}
        error={chatError}
        hint="Make your case. Who is the imposter?" />
    {/if}
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
            <Marker {player} size={22} />
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
      {#if watchers.length}
        <p id="watchers" class="mt-3 font-stamp text-xs text-riso-muted">
          Watching: {watchers.map(w => w.name + (w.id === playerId ? ' (you)' : '')).join(', ')}
        </p>
      {/if}
    </Card>

    {#if secret}
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
    {/if}
  </aside>
</div>
