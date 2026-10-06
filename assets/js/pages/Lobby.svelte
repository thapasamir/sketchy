<script>
  import { onMount, onDestroy, untrack } from 'svelte'
  import Wordmark from '../components/Wordmark.svelte'
  import Button from '../components/Button.svelte'
  import Card from '../components/Card.svelte'
  import GameScreen from '../components/GameScreen.svelte'
  import FinalScreen from '../components/FinalScreen.svelte'
  import Toasts from '../components/Toasts.svelte'
  import ConnectionBanner from '../components/ConnectionBanner.svelte'
  import WaitingRoom from '../components/lobby/WaitingRoom.svelte'
  import { RoomSession } from '../lib/room-session.svelte.js'

  // This page is the frame: it joins the room (see RoomSession, which holds everything the server
  // says and everything we can ask of it) and picks the screen for the room's phase.
  // `onleave()` is called when the person leaves; `ongone(reason)` when the seat can't be used.
  let { roomCode = '', playerId, onleave, ongone } = $props()

  // A seat never changes while this page is open (leaving closes it), so the props are read once.
  const session = untrack(() => new RoomSession({ roomCode, playerId, onGone: reason => ongone(reason) }))

  onMount(() => session.connect())
  onDestroy(() => session.destroy())

  let room = $derived(session.room)
</script>

<ConnectionBanner state={session.connection} />
<Toasts notices={session.toasts.items} />

<main
  class="mx-auto flex min-h-dvh w-full flex-col gap-8 px-4 pb-24 pt-6 sm:pt-8 {session.status === 'live' ? 'max-w-6xl lg:max-w-7xl lg:!gap-4 lg:!pb-6 lg:!pt-4' : 'max-w-4xl'}">
  <header class="flex items-center justify-between gap-4">
    <Wordmark class="text-3xl sm:text-4xl" />
    <Button class="px-4 py-2.5 font-stamp text-sm sm:px-6" onclick={() => onleave()}>← Leave</Button>
  </header>

  {#if session.status === 'error'}
    <Card class="mx-auto w-full max-w-sm text-center">
      <h3 class="mb-3 font-display text-2xl">Oops</h3>
      <p class="mb-6 text-riso-muted" role="alert">{session.errorMessage}</p>
      <div class="flex gap-3">
        <Button variant="blue" class="min-w-0 flex-1" onclick={() => location.reload()}>Try again</Button>
        <Button class="min-w-0 flex-1" onclick={() => onleave()}>Leave</Button>
      </div>
    </Card>
  {:else if session.status === 'connecting'}
    <p class="text-center font-stamp text-riso-muted">Opening room…</p>
  {:else if session.finished}
    <FinalScreen
      {room}
      {playerId}
      isHost={session.isHost}
      playAgain={session.playAgain}
      error={session.actionError}
      messages={session.chat.messages}
      sendChat={session.chat.send}
      chatError={session.chat.error} />
  {:else if session.inGame}
    <GameScreen
      {room}
      secret={session.secret}
      {playerId}
      store={session.strokes}
      send={session.sendStroke}
      undo={session.undo}
      finishTurn={session.finishTurn}
      vote={session.vote}
      castVote={session.castVote}
      submitGuess={session.submitGuess}
      nextRound={session.nextRound}
      isHost={session.isHost}
      messages={session.chat.messages}
      sendChat={session.chat.send}
      chatError={session.chat.error}
      reactions={session.reactions.items}
      sendReaction={session.reactions.send}
      error={session.drawError || session.actionError} />
  {:else}
    <WaitingRoom {session} />
  {/if}
</main>
