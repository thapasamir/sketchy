<script>
  import { createEventDispatcher, onMount, onDestroy } from 'svelte'
  import Wordmark from '../components/Wordmark.svelte'
  import Button from '../components/Button.svelte'
  import Card from '../components/Card.svelte'
  import { joinRoom } from '../lib/socket.js'

  const dispatch = createEventDispatcher()

  export let roomCode = ''
  export let playerName = ''
  export let playerId = null // set when you created the room; null for the not-yet-built join flow

  // 'connecting' | 'live' | 'error' | 'preview'
  let status = playerId ? 'connecting' : 'preview'
  let errorMessage = ''
  let room = null
  let channel = null

  let rounds = 3
  let drawTime = 60

  // The server's room state is the source of truth. In preview mode (join flow not built yet)
  // we fake a one-player room so the screen still renders.
  $: players = room ? room.players : [{ id: 'preview', name: playerName }]
  $: hostId = room ? room.host_id : 'preview'
  $: code = room ? room.code : roomCode

  const reasons = {
    room_not_found: 'This room has closed.',
    not_a_member: 'You are not a player in this room.',
    timeout: 'Could not reach the server. Check your connection and try again.',
  }

  onMount(() => {
    if (!playerId) return

    channel = joinRoom(roomCode, playerId, {
      onJoined: r => {
        room = r
        status = 'live'
      },
      onError: reason => {
        errorMessage = reasons[reason] || 'Could not connect to the room.'
        status = 'error'
      },
    })
  })

  onDestroy(() => channel?.leave())

  const labelClass = 'mb-2 block font-stamp text-xs uppercase tracking-widest'
</script>

<main class="mx-auto flex min-h-dvh w-full max-w-4xl flex-col gap-8 px-4 py-6 sm:py-8">
  <header class="flex items-center justify-between gap-4">
    <Wordmark class="text-3xl sm:text-4xl" />
    <Button class="px-4 py-2.5 font-stamp text-sm sm:px-6" on:click={() => dispatch('back')}>← Leave</Button>
  </header>

  {#if status === 'error'}
    <Card class="mx-auto w-full max-w-sm text-center">
      <h3 class="mb-3 font-display text-2xl">Oops</h3>
      <p class="mb-6 text-riso-muted" role="alert">{errorMessage}</p>
      <Button variant="blue" class="w-full" on:click={() => dispatch('back')}>Back to start</Button>
    </Card>
  {:else if status === 'connecting'}
    <p class="text-center font-stamp text-riso-muted">Opening room…</p>
  {:else}
    {#if status === 'preview'}
      <p class="border-2 border-dashed border-riso-line p-3 text-center font-stamp text-sm text-riso-muted">
        Joining a room isn't built yet. This is a preview.
      </p>
    {/if}

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

        <h3 class="mb-4 mt-8 font-display text-2xl sm:text-3xl">Players ({players.length})</h3>
        <ul class="flex flex-col gap-2" id="player-list">
          {#each players as player (player.id)}
            <li
              class="rounded-[2px] border-l-4 p-3 {player.id === hostId
                ? 'border-riso-pink bg-riso-pink/5'
                : 'border-riso-blue bg-riso-blue/5'}">
              {player.name}
              {#if player.id === hostId}<span class="font-stamp text-xs text-riso-pink mix-blend-multiply">(Host)</span>{/if}
              {#if player.id === playerId}<span class="font-stamp text-xs text-riso-muted">(You)</span>{/if}
            </li>
          {/each}
        </ul>
      </Card>

      <Card class="flex flex-col gap-6">
        <h3 class="font-display text-2xl sm:text-3xl">Settings</h3>

        <div>
          <label for="rounds" class={labelClass}>Number of Rounds</label>
          <div class="mb-2 text-center font-display text-3xl text-riso-blue">{rounds}</div>
          <input id="rounds" type="range" class="riso-slider" min="2" max="4" bind:value={rounds} />
        </div>

        <div>
          <label for="drawtime" class={labelClass}>Draw Time (seconds)</label>
          <div class="mb-2 text-center font-display text-3xl text-riso-blue">{drawTime}s</div>
          <input id="drawtime" type="range" class="riso-slider" min="30" max="90" step="10" bind:value={drawTime} />
        </div>

        <Button
          variant="yellow"
          class="mt-auto w-full py-4 text-xl"
          disabled={players.length < 3}
          on:click={() => console.log('Start game')}>
          {players.length < 3 ? `Need ${3 - players.length} more players` : 'START GAME'}
        </Button>
      </Card>
    </div>
  {/if}
</main>
