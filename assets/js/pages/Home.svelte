<script>
  import { createEventDispatcher, onMount } from 'svelte'
  import InkTrail from '../components/InkTrail.svelte'

  const dispatch = createEventDispatcher()

  let mode = null // 'create' or 'join'
  let roomCode = ''
  let playerName = ''
  let error = ''

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

<style>
  .container {
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 20px;
    background:
      radial-gradient(circle at 20% 30%, rgba(0,0,0,.12) 1px, transparent 2px),
      radial-gradient(circle at 70% 60%, rgba(255,255,255,.12) 1px, transparent 2px),
      linear-gradient(135deg, #F4F2EC 0%, #EFEDE6 100%);
    background-size: 9px 11px, 13px 7px, 100% 100%;
  }

  .hero {
    text-align: center;
    margin-bottom: 60px;
  }

  .logo {
    font-family: var(--f-display);
    font-size: clamp(48px, 12vw, 120px);
    line-height: 0.9;
    margin-bottom: 20px;
    position: relative;
    display: inline-block;
    letter-spacing: -0.02em;
  }

  .logo .pink {
    color: var(--riso-pink);
    mix-blend-mode: multiply;
    display: block;
    transform: translate(var(--mx, 0px), var(--my, 0px));
    transition: transform 0.15s ease-out;
  }

  .logo .blue {
    color: var(--riso-blue);
    mix-blend-mode: multiply;
    position: absolute;
    inset: 0;
    transform: translate(calc(4px - var(--mx, 0px)), calc(3px - var(--my, 0px)));
    transition: transform 0.15s ease-out;
    opacity: 0.9;
  }

  .tagline {
    font-size: 18px;
    color: #55574F;
    max-width: 400px;
    margin: 0 auto;
    font-family: var(--f-type);
  }

  .mode-select {
    display: flex;
    gap: 20px;
    margin-bottom: 40px;
    justify-content: center;
    flex-wrap: wrap;
  }

  .btn {
    padding: 16px 32px;
    font-size: 18px;
    border: 2px solid var(--riso-ink);
    background: transparent;
    color: var(--riso-ink);
    border-radius: 4px;
    transition: all 0.2s ease;
    min-width: 200px;
  }

  .btn:hover:not(:disabled) {
    transform: translate(-2px, -2px);
    box-shadow: 4px 4px 0 rgba(0, 0, 0, 0.1);
  }

  .btn-primary {
    background: var(--riso-pink);
    color: var(--riso-paper);
    border-color: var(--riso-pink);
    mix-blend-mode: multiply;
  }

  .form-card {
    background: rgba(255, 255, 255, 0.6);
    border: 2px solid var(--riso-ink);
    padding: 40px;
    border-radius: 4px;
    max-width: 400px;
    width: 100%;
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.08);
  }

  .form-group {
    margin-bottom: 24px;
  }

  .form-group label {
    display: block;
    font-family: var(--f-stamp);
    font-size: 14px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    margin-bottom: 8px;
    color: var(--riso-ink);
  }

  .form-group input {
    width: 100%;
    padding: 12px 14px;
    font-size: 16px;
    font-family: var(--f-type);
  }

  .form-group input::placeholder {
    color: #B9BBB0;
  }

  .error {
    color: #C8102E;
    font-size: 14px;
    margin-top: 8px;
    font-family: var(--f-stamp);
  }

  .form-actions {
    display: flex;
    gap: 12px;
    margin-top: 32px;
  }

  /* the landing buttons have a 200px minimum; form buttons must share the card width */
  .form-actions .btn {
    min-width: 0;
  }

  .btn-submit {
    flex: 1;
    background: var(--riso-blue);
    color: white;
    border-color: var(--riso-blue);
    padding: 14px 24px;
  }

  .btn-cancel {
    flex: 1;
    background: transparent;
    color: var(--riso-ink);
    border-color: var(--riso-ink);
    padding: 14px 24px;
  }

  .btn-submit:hover {
    transform: translate(-2px, -2px);
    box-shadow: 4px 4px 0 rgba(0, 120, 191, 0.3);
  }

  .btn-cancel:hover {
    background: rgba(255, 72, 176, 0.05);
  }

  .room-code-input {
    text-transform: uppercase;
    font-family: var(--f-stamp);
    font-size: 32px;
    text-align: center;
    letter-spacing: 8px;
    font-weight: bold;
    padding: 16px;
  }

  @media (max-width: 480px) {
    .container {
      padding: 16px;
    }

    .hero {
      margin-bottom: 40px;
    }

    .form-card {
      padding: 24px;
    }

    .mode-select {
      flex-direction: column;
      gap: 12px;
    }

    .btn {
      width: 100%;
      min-width: unset;
    }
  }
</style>

{#if mode === null}
  <InkTrail />
  <div class="container">
    <div class="hero">
      <div class="logo">
        <span class="pink">SKETCHY</span>
        <span class="blue">SKETCHY</span>
      </div>
      <p class="tagline">
        Draw things. Catch the imposter. Win together.
      </p>
    </div>

    <div class="mode-select">
      <button class="btn btn-primary" on:click={handleCreate}>
        Create Room
      </button>
      <button class="btn" on:click={handleJoin}>
        Join Room
      </button>
    </div>
  </div>
{:else if mode === 'create'}
  <div class="container">
    <div class="form-card">
      <h2 style="font-family: var(--f-display); font-size: 24px; margin-bottom: 24px;">
        <span style="color: var(--riso-pink); mix-blend-mode: multiply;">Create</span> Room
      </h2>

      <p style="margin-bottom: 24px; font-size: 14px; color: #55574F;">
        Share your room code with friends. Everyone draws, someone is the imposter.
      </p>

      <div class="form-group">
        <label for="name">Your Name</label>
        <input
          id="name"
          type="text"
          bind:value={playerName}
          placeholder="Enter your name"
          maxlength="20"
        />
      </div>

      <div class="form-actions">
        <button class="btn btn-submit" on:click={() => {
          if (playerName.trim()) {
            dispatch('join', { code: null, name: playerName.trim() })
          }
        }}>
          Create
        </button>
        <button class="btn btn-cancel" on:click={handleBack}>
          Back
        </button>
      </div>
    </div>
  </div>
{:else if mode === 'join'}
  <div class="container">
    <div class="form-card">
      <h2 style="font-family: var(--f-display); font-size: 24px; margin-bottom: 24px;">
        <span style="color: var(--riso-blue); mix-blend-mode: multiply;">Join</span> Room
      </h2>

      <div class="form-group">
        <label for="code">Room Code</label>
        <input
          id="code"
          type="text"
          bind:value={roomCode}
          placeholder="ABCD"
          maxlength="4"
          class="room-code-input"
        />
      </div>

      <div class="form-group">
        <label for="joinname">Your Name</label>
        <input
          id="joinname"
          type="text"
          bind:value={playerName}
          placeholder="Enter your name"
          maxlength="20"
        />
      </div>

      {#if error}
        <div class="error">❌ {error}</div>
      {/if}

      <div class="form-actions">
        <button class="btn btn-submit" on:click={submitJoin}>
          Join
        </button>
        <button class="btn btn-cancel" on:click={handleBack}>
          Back
        </button>
      </div>
    </div>
  </div>
{/if}
