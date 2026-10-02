<script>
  import { createEventDispatcher, onMount } from 'svelte'
  import InkTrail from '../components/InkTrail.svelte'
  import Wordmark from '../components/Wordmark.svelte'
  import Button from '../components/Button.svelte'
  import Card from '../components/Card.svelte'
  import { createRoom } from '../lib/api.js'

  const dispatch = createEventDispatcher()

  let mode = null // null = landing, 'create' or 'join'
  let roomCode = ''
  let playerName = ''
  let error = ''
  let busy = false

  const labelClass = 'mb-2 block font-stamp text-sm uppercase tracking-widest'
  const inputClass =
    'w-full rounded-[3px] border-2 border-riso-ink bg-white px-3.5 py-3 font-type text-base placeholder:text-riso-line focus:outline-2 focus:outline-offset-2 focus:outline-riso-blue'

  // Logo misprint: the two inks slide in opposite directions as the pointer moves
  onMount(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return
    const root = document.documentElement
    function onMove(e) {
      const nx = (e.clientX / window.innerWidth - 0.5) * 2
      const ny = (e.clientY / window.innerHeight - 0.5) * 2
      root.style.setProperty('--mx', (nx * 7).toFixed(1) + 'px')
      root.style.setProperty('--my', (ny * 5).toFixed(1) + 'px')
    }
    window.addEventListener('pointermove', onMove)
    return () => window.removeEventListener('pointermove', onMove)
  })

  function handleCreate() {
    // TODO: Call backend to create room
    mode = 'create'
  }

  function handleJoin() {
    mode = 'join'
  }

  async function submitCreate() {
    error = ''
    if (!playerName.trim()) {
      error = 'Please enter your name'
      return
    }

    busy = true
    try {
      const { code, player_id } = await createRoom(playerName.trim())
      dispatch('join', { code, name: playerName.trim(), playerId: player_id })
    } catch (e) {
      error = e.message
    } finally {
      busy = false
    }
  }

  function submitJoin() {
    error = ''

    if (!playerName.trim()) {
      error = 'Please enter your name'
      return
    }

    if (!roomCode.trim() || roomCode.length !== 4) {
      error = 'Room code must be 4 letters'
      return
    }

    dispatch('join', {
      code: roomCode.toUpperCase(),
      name: playerName.trim()
    })
  }

  function handleBack() {
    mode = null
    error = ''
    roomCode = ''
    playerName = ''
  }
</script>

{#if mode === null}
  <InkTrail />
  <main class="flex min-h-dvh flex-col items-center justify-center px-4 py-10">
    <div class="mb-12 text-center">
      <Wordmark class="text-[clamp(3rem,13vw,7.5rem)]" />
      <p class="mx-auto mt-5 max-w-sm text-balance text-lg text-riso-muted">
        Draw things. Catch the imposter. Win together.
      </p>
    </div>

    <div class="flex w-full max-w-sm flex-col gap-3 sm:w-auto sm:max-w-none sm:flex-row sm:gap-5">
      <Button variant="pink" class="sm:min-w-52" on:click={handleCreate}>Create Room</Button>
      <Button class="sm:min-w-52" on:click={handleJoin}>Join Room</Button>
    </div>
  </main>
{:else}
  <main class="flex min-h-dvh items-center justify-center px-4 py-8">
    <Card class="w-full max-w-sm">
      {#if mode === 'create'}
        <h2 class="mb-4 font-display text-2xl">
          <span class="text-riso-pink mix-blend-multiply">Create</span> Room
        </h2>
        <p class="mb-6 text-sm text-riso-muted">
          Share your room code with friends. Everyone draws, someone is the imposter.
        </p>

        <label for="name" class={labelClass}>Your Name</label>
        <input id="name" type="text" bind:value={playerName} placeholder="Enter your name" maxlength="20" class={inputClass} />

        {#if error}
          <p class="mt-3 font-stamp text-sm text-riso-stamp" role="alert">{error}</p>
        {/if}

        <div class="mt-8 flex gap-3">
          <Button variant="blue" class="min-w-0 flex-1" disabled={busy} on:click={submitCreate}>
            {busy ? 'Creating…' : 'Create'}
          </Button>
          <Button class="min-w-0 flex-1" on:click={handleBack}>Back</Button>
        </div>
      {:else}
        <h2 class="mb-6 font-display text-2xl">
          <span class="text-riso-blue mix-blend-multiply">Join</span> Room
        </h2>

        <div class="mb-6">
          <label for="code" class={labelClass}>Room Code</label>
          <input
            id="code"
            type="text"
            bind:value={roomCode}
            placeholder="ABCD"
            maxlength="4"
            autocapitalize="characters"
            class="{inputClass} pl-[0.5em] text-center font-stamp text-3xl font-bold uppercase tracking-[0.5em]" />
        </div>

        <label for="joinname" class={labelClass}>Your Name</label>
        <input id="joinname" type="text" bind:value={playerName} placeholder="Enter your name" maxlength="20" class={inputClass} />

        {#if error}
          <p class="mt-3 font-stamp text-sm text-riso-stamp" role="alert">{error}</p>
        {/if}

        <div class="mt-8 flex gap-3">
          <Button variant="blue" class="min-w-0 flex-1" on:click={submitJoin}>Join</Button>
          <Button class="min-w-0 flex-1" on:click={handleBack}>Back</Button>
        </div>
      {/if}
    </Card>
  </main>
{/if}
