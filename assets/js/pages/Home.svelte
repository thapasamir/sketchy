<script>
  import { createEventDispatcher, onMount } from 'svelte'
  import InkTrail from '../components/InkTrail.svelte'
  import Wordmark from '../components/Wordmark.svelte'
  import Button from '../components/Button.svelte'
  import Card from '../components/Card.svelte'
  import { createGuestUser, registerUser, loginUser, createRoom } from '../lib/api.js'
  import { loadUser, saveUser, clearUser } from '../lib/session.js'

  const dispatch = createEventDispatcher()

  let mode = null // null = landing, 'guest', 'auth-form', 'room-form'
  let authMode = 'register' // 'register' | 'login'
  let roomCode = ''
  let playerName = ''
  let username = ''
  let email = ''
  let password = ''
  let error = ''
  let busy = false
  let user = loadUser() // who this browser already is, if anyone
  if (user) {
    mode = 'room-form'
    playerName = user.username || ''
  }

  const labelClass = 'mb-2 block font-stamp text-sm uppercase tracking-widest'
  const inputClass =
    'w-full rounded-[3px] border-2 border-riso-ink bg-white px-3.5 py-3 font-type text-base placeholder:text-riso-line focus:outline-2 focus:outline-offset-2 focus:outline-riso-blue'

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

  async function handlePlayAsGuest() {
    error = ''
    busy = true
    try {
      const { user_id } = await createGuestUser()
      user = { userId: user_id, userType: 'guest' }
      saveUser(user)
      mode = 'room-form'
    } catch (e) {
      error = e.message
    } finally {
      busy = false
    }
  }

  function handleAuth() {
    mode = 'auth-form'
    authMode = 'register'
    error = ''
    username = ''
    email = ''
    password = ''
  }

  async function submitRegister() {
    error = ''
    if (!username.trim()) {
      error = 'Username is required'
      return
    }
    if (!email.trim()) {
      error = 'Email is required'
      return
    }
    if (!password.trim()) {
      error = 'Password is required'
      return
    }

    busy = true
    try {
      const { user_id } = await registerUser(username.trim(), email.trim(), password)
      user = { userId: user_id, userType: 'registered', username: username.trim() }
      saveUser(user)
      playerName = user.username
      mode = 'room-form'
    } catch (e) {
      error = e.message
    } finally {
      busy = false
    }
  }

  async function submitLogin() {
    error = ''
    if (!username.trim()) {
      error = 'Username is required'
      return
    }
    if (!password.trim()) {
      error = 'Password is required'
      return
    }

    busy = true
    try {
      const { user_id } = await loginUser(username.trim(), password)
      user = { userId: user_id, userType: 'registered', username: username.trim() }
      saveUser(user)
      playerName = user.username
      mode = 'room-form'
    } catch (e) {
      error = e.message
    } finally {
      busy = false
    }
  }

  async function submitCreateRoom() {
    error = ''
    if (!playerName.trim()) {
      error = 'Please enter your name'
      return
    }

    busy = true
    try {
      const result = await createRoom(playerName.trim())
      dispatch('join', { code: result.code, name: playerName.trim(), playerId: result.player_id })
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

  function switchUser() {
    clearUser()
    user = null
    mode = null
    playerName = ''
    error = ''
  }

  function handleBack() {
    if (mode === 'room-form') {
      switchUser()
    } else if (mode === 'auth-form') {
      mode = null
      username = ''
      email = ''
      password = ''
      error = ''
    } else {
      mode = null
      error = ''
    }
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
      <Button variant="pink" class="sm:min-w-52" disabled={busy} on:click={handlePlayAsGuest}>
        {busy ? 'Joining…' : 'Play as Guest'}
      </Button>
      <Button class="sm:min-w-52" on:click={handleAuth}>Register / Login</Button>
    </div>
  </main>
{:else if mode === 'auth-form'}
  <main class="flex min-h-dvh items-center justify-center px-4 py-8">
    <Card class="w-full max-w-lg">
      {#if authMode === 'register'}
        <h2 class="mb-4 font-display text-2xl">
          <span class="text-riso-pink mix-blend-multiply">Create</span> Account
        </h2>
        <p class="mb-6 text-sm text-riso-muted">
          Save your profile for leaderboards and stats (optional for playing).
        </p>

        <div class="sm:grid sm:grid-cols-2 sm:gap-x-4">
        <div class="mb-5">
          <label for="reg-username" class={labelClass}>Username</label>
        <input
          id="reg-username"
          type="text"
          bind:value={username}
          placeholder="3–20 characters"
          maxlength="20"
          class={inputClass} />
        </div>

        <div class="mb-5">
          <label for="reg-email" class={labelClass}>Email</label>
        <input
          id="reg-email"
          type="email"
          bind:value={email}
          placeholder="your@email.com"
          class={inputClass} />
        </div>
        </div>

        <div class="mb-5">
          <label for="reg-password" class={labelClass}>Password</label>
        <input
          id="reg-password"
          type="password"
          bind:value={password}
          placeholder="6+ characters"
          class={inputClass} />
        </div>

        {#if error}
          <p class="mt-3 font-stamp text-sm text-riso-stamp" role="alert">{error}</p>
        {/if}

        <div class="mt-8 flex gap-3">
          <Button variant="blue" class="min-w-0 flex-1" disabled={busy} on:click={submitRegister}>
            {busy ? 'Creating…' : 'Create'}
          </Button>
          <Button class="min-w-0 flex-1" on:click={handleBack}>Back</Button>
        </div>

        <button type="button" on:click={() => (authMode = 'login')} class="mt-6 block text-sm text-riso-blue underline hover:no-underline">
          Already have an account? Login
        </button>
      {:else}
        <h2 class="mb-4 font-display text-2xl">
          <span class="text-riso-blue mix-blend-multiply">Login</span>
        </h2>
        <p class="mb-6 text-sm text-riso-muted">
          Access your account and see your stats.
        </p>

        <div class="mb-5">
          <label for="login-username" class={labelClass}>Username</label>
        <input
          id="login-username"
          type="text"
          bind:value={username}
          placeholder="Enter your username"
          class={inputClass} />
        </div>

        <div class="mb-5">
          <label for="login-password" class={labelClass}>Password</label>
        <input
          id="login-password"
          type="password"
          bind:value={password}
          placeholder="Enter your password"
          class={inputClass} />
        </div>

        {#if error}
          <p class="mt-3 font-stamp text-sm text-riso-stamp" role="alert">{error}</p>
        {/if}

        <div class="mt-8 flex gap-3">
          <Button variant="blue" class="min-w-0 flex-1" disabled={busy} on:click={submitLogin}>
            {busy ? 'Logging in…' : 'Login'}
          </Button>
          <Button class="min-w-0 flex-1" on:click={handleBack}>Back</Button>
        </div>

        <button type="button" on:click={() => (authMode = 'register')} class="mt-6 block text-sm text-riso-blue underline hover:no-underline">
          Don't have an account? Register
        </button>
      {/if}
    </Card>
  </main>
{:else if mode === 'room-form'}
  <main class="flex min-h-dvh items-center justify-center px-4 py-8">
    <Card class="w-full max-w-sm">
      <div class="mb-4 flex items-center justify-between">
        <h2 class="font-display text-2xl">
          <span class="text-riso-pink mix-blend-multiply">Create</span> Room
        </h2>
        <button type="button" on:click={switchUser} class="text-sm text-riso-muted underline hover:text-riso-ink">
          Not {user?.username || 'you'}?
        </button>
      </div>

      <p class="mb-6 text-sm text-riso-muted">
        Playing as {user?.userType === 'registered' ? user.username : 'a guest'}. Share your room code with friends.
        Everyone draws, someone is the imposter.
      </p>

      <label for="name" class={labelClass}>Your Name (for this game)</label>
      <input id="name" type="text" bind:value={playerName} placeholder="Enter your name" maxlength="20" class={inputClass} />

      {#if error}
        <p class="mt-3 font-stamp text-sm text-riso-stamp" role="alert">{error}</p>
      {/if}

      <div class="mt-8 flex gap-3">
        <Button variant="blue" class="min-w-0 flex-1" disabled={busy} on:click={submitCreateRoom}>
          {busy ? 'Creating…' : 'Create'}
        </Button>
        <Button class="min-w-0 flex-1" on:click={handleBack}>Back</Button>
      </div>
    </Card>
  </main>
{/if}
