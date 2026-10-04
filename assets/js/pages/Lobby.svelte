<script>
  import { createEventDispatcher, onMount, onDestroy } from 'svelte'
  import Wordmark from '../components/Wordmark.svelte'
  import Button from '../components/Button.svelte'
  import Card from '../components/Card.svelte'
  import GameScreen from '../components/GameScreen.svelte'
  import FinalScreen from '../components/FinalScreen.svelte'
  import ChatPanel from '../components/ChatPanel.svelte'
  import { append, load as loadChat, save as saveChat, clear as clearChat } from '../lib/chatlog.js'
  import { createStrokeStore } from '../lib/strokes.js'
  import { fly } from 'svelte/transition'
  import { play } from '../lib/sound.js'
  import { cuesFor, TIMING } from '../lib/cues.js'
  import { joinRoom } from '../lib/socket.js'

  const dispatch = createEventDispatcher()

  export let roomCode = ''
  export let playerId

  // 'connecting' | 'live' | 'error'
  let status = 'connecting'
  let errorMessage = ''
  let room = null
  // What THIS player may know about the round (the word, or the imposter's hint). The server
  // sends it only to this player; it is never part of the shared room.
  let secret = null
  // who I voted for (only the server and I know)
  let vote = null
  let channel = null
  // the shared picture; lives here (not in the board) so strokes aren't lost between screens
  const strokes = createStrokeStore()
  let drawError = ''
  let actionError = ''
  let copied = ''

  // The server's room state is the source of truth; every update replaces it wholesale.
  $: players = room ? room.players : []
  $: isHost = room?.host_id === playerId
  $: code = room ? room.code : roomCode
  $: connectedCount = players.filter(p => p.connected).length
  $: minPlayers = room?.min_players ?? 3
  $: playing = !!room && room.phase !== 'lobby'
  $: revealing = room?.phase === 'reveal'
  $: inGame = ['drawing', 'voting', 'guess', 'result'].includes(room?.phase)
  $: finished = room?.phase === 'final'

  // countdown while everyone reads their card
  let secondsLeft = 0
  let countdown
  let lastPhase
  $: if (room && room.phase !== lastPhase) {
    lastPhase = room.phase
    clearInterval(countdown)
    if (room.phase === 'reveal') {
      secondsLeft = room.reveal_seconds
      countdown = setInterval(() => secondsLeft > 0 && (secondsLeft -= 1), 1000)
    }
  }
  $: me = players.find(p => p.id === playerId)
  $: myReady = !!me?.ready
  // everyone who is here, isn't the host, and hasn't said ready (away players don't hold things up)
  $: waitingFor = players.filter(p => p.id !== room?.host_id && p.connected && !p.ready).length
  $: canStart = isHost && connectedCount >= minPlayers && waitingFor === 0

  // Removing someone takes two clicks so a slip can't kick a friend
  let confirmKick = null
  let confirmTimer

  // The sliders show whatever the server says; only the host can move them.
  let rounds = 3
  let drawTime = 60
  // how many times everyone draws per word: 'auto', 1 or 2
  let laps = 'auto'
  $: if (room) {
    rounds = room.settings.rounds
    drawTime = room.settings.draw_time
    laps = room.settings.laps
  }
  $: turnsPerWord = players.length * (room?.laps_now ?? 1)
  const LAP_CHOICES = [
    ['auto', 'Auto'],
    [1, '1'],
    [2, '2'],
  ]

  // --- chat ---
  //
  // The server only relays chat, so this browser keeps the conversation: it starts from what was
  // saved (a refresh doesn't lose it) and is cleared when you leave the room.
  let messages = loadChat(roomCode, playerId)
  let chatError = ''

  const chatErrors = {
    chat_closed: "Chat is closed right now. It's back during the vote.",
    too_fast: 'Slow down a little.',
    empty: 'Type something first.',
    too_long: 'That message is too long.',
    not_a_member: "You're not in this room any more.",
  }

  function onChat(message) {
    messages = append(messages, message)
    saveChat(roomCode, playerId, messages)
    if (message.player_id !== playerId) play('message')
  }

  // resolves true if the room took the message, so the box is cleared only then
  function sendChat(text) {
    chatError = ''
    return new Promise(resolve => {
      channel
        .push('chat', { text })
        .receive('ok', () => resolve(true))
        .receive('error', ({ reason }) => {
          chatError = chatErrors[reason] ?? 'Could not send that.'
          resolve(false)
        })
        .receive('timeout', () => {
          chatError = 'Could not reach the server.'
          resolve(false)
        })
    })
  }

  // a note about an earlier problem shouldn't outlive the moment chat closes
  $: if (room && !room.chat_open) chatError = ''

  // --- sound and attention ---

  let cueTimers = []

  // Every change to the room comes through here: work out what it should sound like (see
  // lib/cues.js), play it, and update the screen.
  function applyUpdate(next, nextSecret, nextVote) {
    const cues = cuesFor(room, next, playerId, nextSecret)
    room = next
    secret = nextSecret
    vote = nextVote

    const myTurn = next.phase === 'drawing' && next.turn?.player_id === playerId
    if (!myTurn) restoreTitle()

    for (const cue of cues) {
      if (cue.delay) cueTimers.push(setTimeout(() => play(cue.name), cue.delay))
      else play(cue.name)
      if (cue.attention) attention()
    }
  }

  // When it is your turn and you're looking at something else, say so: a buzz on a phone, and the
  // tab's title in the tab bar.
  let originalTitle = ''
  function attention() {
    navigator.vibrate?.(70)
    if (document.hidden) {
      originalTitle ||= document.title
      document.title = 'Your turn! · Sketchy'
    }
  }

  function restoreTitle() {
    if (originalTitle) {
      document.title = originalTitle
      originalTitle = ''
    }
  }

  const onVisibility = () => !document.hidden && restoreTitle()

  const reasons = {
    room_not_found: 'That room has closed. Start a new one or join another.',
    not_a_member: "You're not a player in that room.",
    timeout: 'Could not reach the server. Check your connection and try again.',
  }

  const actionErrors = {
    not_host: 'Only the host can do that.',
    not_all_ready: 'Everyone needs to be ready first.',
    not_a_member: 'That player has already left.',
    host_cannot: "The host can't do that.",
    invalid_settings: "Those settings aren't allowed.",
    not_enough_players: `Need at least ${minPlayers} connected players to start.`,
    game_in_progress: 'The game has already started.',
    not_voting: 'The voting is over.',
    cannot_vote_self: "You can't vote for yourself.",
    not_imposter: 'Only the imposter can guess.',
    invalid_guess: 'Type a word or two.',
    not_guessing: 'The guessing is over.',
    not_result: 'That can only be done after a round.',
    not_finished: 'The game is not over yet.',
  }

  onMount(() => {
    document.addEventListener('visibilitychange', onVisibility)
    channel = joinRoom(roomCode, playerId, {
      onJoined: (r, s, picture, v) => {
        room = r
        secret = s
        vote = v
        strokes.load(picture)
        status = 'live'
      },
      onUpdate: applyUpdate,
      onDraw: event => strokes.apply(event),
      onChat,
      onKicked: () => dispatch('gone', 'The host removed you from the room.'),
      onError: reason => {
        const message = reasons[reason] || 'Could not connect to the room.'
        // A closed room or a seat that isn't yours can't be fixed by retrying: go home and say why.
        if (reason === 'timeout') {
          errorMessage = message
          status = 'error'
        } else {
          dispatch('gone', message)
        }
      },
    })
  })

  // Leaving the screen on purpose (Leave button, browser Back, room closed) frees the seat right
  // away. Closing the tab or refreshing skips this, so the server keeps the seat for a grace
  // period and you can come straight back.
  onDestroy(() => {
    clearInterval(countdown)
    cueTimers.forEach(clearTimeout)
    restoreTitle()
    document.removeEventListener('visibilitychange', onVisibility)
    // leaving for good ends this conversation (a refresh doesn't come through here)
    clearChat(roomCode, playerId)
    channel?.push('leave', {})
    channel?.leave()
  })

  function send(event, payload = {}) {
    actionError = ''
    channel
      .push(event, payload)
      .receive('error', ({ reason }) => (actionError = actionErrors[reason] || 'Something went wrong.'))
      .receive('timeout', () => (actionError = reasons.timeout))
  }

  const drawErrors = {
    not_your_turn: '',
    too_many_strokes: 'That is enough strokes for one turn.',
    canvas_full: 'The canvas is full.',
    stroke_too_long: 'That stroke got too long. Lift the pen and start a new one.',
  }

  // The drawer's own screen is drawn before the server has agreed to anything. If the server
  // refused part of it (the turn ran out mid-stroke, too many strokes), that part is on this
  // screen only. Asking for the server's picture puts everyone back on the same one.
  function resync() {
    channel.push('sync', {}).receive('ok', ({ strokes: picture }) => strokes.load(picture))
  }

  // Strokes are sent without waiting for an answer; the server only answers to refuse.
  function sendStroke(event) {
    channel.push('draw', event).receive('error', ({ reason }) => {
      drawError = drawErrors[reason] ?? ''
      resync()
    })
  }

  // when the pen leaves my hands, make sure my screen matches the real picture
  let hadPen = false
  $: {
    const hasPen = room?.phase === 'drawing' && room.turn?.player_id === playerId
    if (hadPen && !hasPen && channel) resync()
    hadPen = hasPen
  }

  function undo() {
    drawError = ''
    channel.push('undo', {}).receive('ok', event => strokes.apply(event))
  }

  const finishTurn = () => channel.push('finish_turn', {})

  function castVote(targetId) {
    play('select')
    vote = targetId // show it at once; the server's answer arrives right behind
    send('vote', { target_id: targetId })
  }

  const submitGuess = text => send('guess', { text })

  // a complaint about one turn shouldn't follow you into the next
  $: turnKey = room?.turn ? `${room.turn.player_id}:${room.turn.lap}` : ''
  $: if (turnKey !== undefined) drawError = ''

  // A new round (and a new game) starts with an empty canvas. The server has already cleared its
  // copy; this clears the one in this browser.
  $: if (room && (room.phase === 'reveal' || room.phase === 'lobby')) strokes.load([])

  const nextRound = () => send('next_round')
  const playAgain = () => send('play_again')

  const toggleReady = () => {
    play('select')
    send('set_ready', { ready: !myReady })
  }

  function kick(player) {
    clearTimeout(confirmTimer)
    if (confirmKick === player.id) {
      confirmKick = null
      send('kick', { player_id: player.id })
    } else {
      confirmKick = player.id
      confirmTimer = setTimeout(() => (confirmKick = null), 3000)
    }
  }

  const saveSettings = () => send('update_settings', { rounds: Number(rounds), draw_time: Number(drawTime) })
  const setLaps = value => send('update_settings', { laps: value })

  async function copy(text, key) {
    try {
      await navigator.clipboard.writeText(text)
    } catch {
      const box = document.createElement('textarea')
      box.value = text
      document.body.append(box)
      box.select()
      document.execCommand('copy')
      box.remove()
    }
    copied = key
    setTimeout(() => copied === key && (copied = ''), 1500)
  }

  const labelClass = 'mb-2 block font-stamp text-xs uppercase tracking-widest'
</script>

<main
  class="mx-auto flex min-h-dvh w-full flex-col gap-8 px-4 pb-24 pt-6 sm:pt-8 {inGame ? 'max-w-6xl' : 'max-w-4xl'}">
  <header class="flex items-center justify-between gap-4">
    <Wordmark class="text-3xl sm:text-4xl" />
    <Button class="px-4 py-2.5 font-stamp text-sm sm:px-6" on:click={() => dispatch('leave')}>← Leave</Button>
  </header>

  {#if status === 'error'}
    <Card class="mx-auto w-full max-w-sm text-center">
      <h3 class="mb-3 font-display text-2xl">Oops</h3>
      <p class="mb-6 text-riso-muted" role="alert">{errorMessage}</p>
      <div class="flex gap-3">
        <Button variant="blue" class="min-w-0 flex-1" on:click={() => location.reload()}>Try again</Button>
        <Button class="min-w-0 flex-1" on:click={() => dispatch('leave')}>Leave</Button>
      </div>
    </Card>
  {:else if status === 'connecting'}
    <p class="text-center font-stamp text-riso-muted">Opening room…</p>
  {:else}
    {#if finished}
      <FinalScreen {room} {playerId} {isHost} {playAgain} error={actionError} {messages} {sendChat} {chatError} />
    {:else if inGame}
      <GameScreen
        {room}
        {secret}
        {playerId}
        store={strokes}
        send={sendStroke}
        {undo}
        {finishTurn}
        {vote}
        {castVote}
        {submitGuess}
        {nextRound}
        {isHost}
        {messages}
        {sendChat}
        {chatError}
        error={drawError || actionError} />
    {:else}
    <div class="grid gap-6 md:grid-cols-2">
      <Card>
        <h3 class="mb-5 font-display text-2xl sm:text-3xl">Room Code</h3>
        <div class="border-2 border-riso-ink bg-white/60 p-5 text-center">
          <div class="mb-2 font-stamp text-xs uppercase tracking-widest text-riso-muted">Share this</div>
          <div
            id="room-code"
            class="pl-[0.2em] font-display text-4xl tracking-[0.2em] text-riso-pink mix-blend-multiply sm:text-5xl">
            {code}
          </div>
        </div>

        <div class="mt-3 flex gap-3">
          <Button class="min-w-0 flex-1 px-3 py-2.5 font-stamp text-sm" on:click={() => copy(code, 'code')}>
            {copied === 'code' ? 'Copied!' : 'Copy code'}
          </Button>
          <Button
            variant="blue"
            class="min-w-0 flex-1 px-3 py-2.5 font-stamp text-sm"
            on:click={() => copy(`${location.origin}/room/${code}`, 'link')}>
            {copied === 'link' ? 'Copied!' : 'Copy invite link'}
          </Button>
        </div>

        <h3 class="mb-4 mt-8 font-display text-2xl sm:text-3xl">Players ({players.length})</h3>
        <ul class="flex flex-col gap-2" id="player-list">
          {#each players as player (player.id)}
            <li
              in:fly={{ y: 10, duration: 260 }}
              data-player={player.name}
              class="flex items-center justify-between gap-3 rounded-[2px] border-l-4 p-3 transition-opacity {player.id === room.host_id
                ? 'border-riso-pink bg-riso-pink/5'
                : 'border-riso-blue bg-riso-blue/5'} {player.connected ? '' : 'opacity-50'}">
              <span class="min-w-0 break-words">
                {player.name}
                {#if player.id === room.host_id}<span class="font-stamp text-xs text-riso-pink mix-blend-multiply">(Host)</span>{/if}
                {#if player.id === playerId}<span class="font-stamp text-xs text-riso-muted">(You)</span>{/if}
                {#if !player.connected}<span class="font-stamp text-xs text-riso-muted">(away)</span>{/if}
                {#if player.ready && player.id !== room.host_id}<span class="font-stamp text-xs text-riso-blue">(ready)</span>{/if}
              </span>

              {#if isHost && player.id !== playerId && !playing}
                <button
                  type="button"
                  data-kick={player.name}
                  on:click={() => kick(player)}
                  class="shrink-0 cursor-pointer rounded-[3px] border px-2.5 py-1 font-stamp text-xs {confirmKick === player.id
                    ? 'border-riso-stamp bg-riso-stamp text-white'
                    : 'border-riso-line text-riso-muted hover:border-riso-ink hover:text-riso-ink'}">
                  {confirmKick === player.id ? 'Sure?' : 'Remove'}
                </button>
              {/if}
            </li>
          {/each}
        </ul>
      </Card>

      {#if playing}
        <Card id="secret-card" class="flex animate-flip-in flex-col justify-center gap-4 text-center">
          {#if secret}
            <div class="font-stamp text-xs uppercase tracking-widest text-riso-muted">
              Round {room.round} of {room.rounds}
            </div>
            <div class="font-stamp text-xs uppercase tracking-widest text-riso-muted">
              Category
              <span id="secret-category" class="ml-1 text-riso-ink">{secret.category}</span>
            </div>

            {#if secret.role === 'imposter'}
              <h3
                id="secret-role"
                style="animation-delay:{TIMING.stampStart}ms"
                class="origin-center animate-stamp font-display text-3xl text-riso-pink mix-blend-multiply sm:text-4xl">
                You're the imposter
              </h3>
              <p class="text-riso-muted">You don't know the word. Here is a clue, so blend in:</p>
              <div id="secret-hint" class="mx-auto border-2 border-dashed border-riso-ink bg-white/60 px-5 py-3 font-display text-2xl">
                {secret.hint}
              </div>
              <p class="text-sm text-riso-muted">Watch what the others draw, and don't get caught.</p>
            {:else}
              <h3 id="secret-role" class="font-display text-xl text-riso-muted">Your secret word</h3>
              <div
                id="secret-word"
                style="animation-delay:500ms"
                class="animate-pop font-display text-4xl text-riso-blue sm:text-5xl">
                {secret.word}
              </div>
              <p class="text-sm text-riso-muted">
                You'll take turns adding to one shared drawing. Show you know the word, without making it too
                obvious. One of you doesn't know it.
              </p>
            {/if}
          {/if}

          <p id="reveal-countdown" class="font-stamp text-sm uppercase tracking-widest text-riso-muted">
            Drawing starts in {secondsLeft}s
          </p>
        </Card>
      {:else}
        <Card class="flex flex-col gap-6">
          <div class="flex items-baseline justify-between gap-3">
            <h3 class="font-display text-2xl sm:text-3xl">Settings</h3>
            {#if !isHost}
              <span class="font-stamp text-xs uppercase tracking-widest text-riso-muted">Host decides</span>
            {/if}
          </div>

          <div>
            <label for="rounds" class={labelClass}>Number of rounds</label>
            <div id="rounds-value" class="mb-2 text-center font-display text-3xl text-riso-blue">{rounds}</div>
            <input
              id="rounds"
              type="range"
              class="riso-slider disabled:opacity-60"
              min="2"
              max="4"
              disabled={!isHost}
              bind:value={rounds}
              on:change={saveSettings} />
          </div>

          <div>
            <label for="drawtime" class={labelClass}>Seconds per turn</label>
            <div id="drawtime-value" class="mb-2 text-center font-display text-3xl text-riso-blue">{drawTime}s</div>
            <input
              id="drawtime"
              type="range"
              class="riso-slider disabled:opacity-60"
              min="30"
              max="90"
              step="10"
              disabled={!isHost}
              bind:value={drawTime}
              on:change={saveSettings} />
          </div>

          <div>
            <div id="laps-label" class={labelClass}>Laps per word</div>
            <div class="grid grid-cols-3 gap-2" role="group" aria-labelledby="laps-label">
              {#each LAP_CHOICES as [value, label]}
                <button
                  type="button"
                  id="laps-{value}"
                  aria-pressed={laps === value}
                  disabled={!isHost}
                  on:click={() => setLaps(value)}
                  class="min-h-11 cursor-pointer rounded-[3px] border-2 px-3 py-2 font-stamp text-sm transition disabled:cursor-default {laps === value
                    ? 'border-riso-ink bg-riso-yellow'
                    : 'border-riso-line bg-white/60 enabled:hover:border-riso-ink'} {!isHost && laps !== value ? 'opacity-60' : ''}">
                  {label}
                </button>
              {/each}
            </div>
            <p id="laps-hint" class="mt-2 font-stamp text-xs text-riso-muted">
              {#if laps === 'auto'}
                Auto: {room.laps_now} {room.laps_now === 1 ? 'lap' : 'laps'} with {players.length} {players.length === 1 ? 'player' : 'players'}, so {turnsPerWord} {turnsPerWord === 1 ? 'turn' : 'turns'} per word.
              {:else}
                Everyone draws {laps === 1 ? 'once' : 'twice'} per word, so {turnsPerWord} {turnsPerWord === 1 ? 'turn' : 'turns'}.
              {/if}
            </p>
          </div>

          {#if actionError}
            <p class="font-stamp text-sm text-riso-stamp" role="alert">{actionError}</p>
          {/if}

          {#if isHost}
            <Button
              id="start-button"
              variant="yellow"
              class="mt-auto w-full py-4 text-xl"
              disabled={!canStart}
              on:click={() => send('start')}>
              {#if connectedCount < minPlayers}
                Need {minPlayers - connectedCount} more {minPlayers - connectedCount === 1 ? 'player' : 'players'}
              {:else if waitingFor > 0}
                Waiting for {waitingFor} to get ready
              {:else}
                START GAME
              {/if}
            </Button>
          {:else}
            <div class="mt-auto">
              <Button
                id="ready-button"
                variant={myReady ? 'blue' : 'yellow'}
                class="w-full py-4 text-xl"
                on:click={toggleReady}>
                {myReady ? 'Ready (tap to undo)' : "I'M READY"}
              </Button>
              <p class="mt-3 text-center font-stamp text-xs text-riso-muted">
                {#if connectedCount < minPlayers}
                  Need {minPlayers - connectedCount} more {minPlayers - connectedCount === 1 ? 'player' : 'players'} before the host can start.
                {:else}
                  The host starts once everyone is ready.
                {/if}
              </p>
            </div>
          {/if}
        </Card>
      {/if}

      <!-- while waiting for friends. (Closed while cards are read: see Chat.open?/1 on the server.) -->
      {#if room.chat_open}
        <div class="md:col-span-2">
          <ChatPanel
            {messages}
            {players}
            {playerId}
            send={sendChat}
            error={chatError}
            hint="Say hi while you wait for everyone." />
        </div>
      {/if}
    </div>
    {/if}
  {/if}
</main>
