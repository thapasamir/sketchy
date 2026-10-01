<script>
  import { createEventDispatcher } from 'svelte'

  const dispatch = createEventDispatcher()

  export let roomCode = ''
  export let playerName = ''

  let players = [playerName]
  let rounds = 3
  let drawTime = 60
</script>

<style>
  .lobby {
    min-height: 100vh;
    padding: 24px;
    background: linear-gradient(135deg, #F4F2EC 0%, #EFEDE6 100%);
  }

  .header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 40px;
  }

  .code-display {
    text-align: center;
    background: rgba(255, 255, 255, 0.6);
    border: 2px solid var(--riso-ink);
    padding: 20px;
    border-radius: 4px;
  }

  .code-label {
    font-family: var(--f-stamp);
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    color: #55574F;
    margin-bottom: 8px;
  }

  .code-value {
    font-family: var(--f-display);
    font-size: 48px;
    color: var(--riso-pink);
    mix-blend-mode: multiply;
    letter-spacing: 8px;
  }

  .back-btn {
    padding: 12px 24px;
    background: transparent;
    border: 2px solid var(--riso-ink);
    color: var(--riso-ink);
    font-family: var(--f-stamp);
    cursor: pointer;
    border-radius: 2px;
  }

  .back-btn:hover {
    background: rgba(255, 72, 176, 0.05);
  }

  .content {
    max-width: 800px;
    margin: 0 auto;
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 32px;
  }

  .card {
    background: rgba(255, 255, 255, 0.6);
    border: 2px solid var(--riso-ink);
    padding: 32px;
    border-radius: 4px;
  }

  .card h3 {
    font-family: var(--f-display);
    font-size: 28px;
    margin-bottom: 20px;
    color: var(--riso-ink);
  }

  .players-list {
    list-style: none;
    margin-bottom: 24px;
  }

  .players-list li {
    padding: 12px;
    background: rgba(0, 120, 191, 0.05);
    border-left: 3px solid var(--riso-blue);
    margin-bottom: 8px;
    font-family: var(--f-type);
    border-radius: 2px;
  }

  .players-list li.host {
    background: rgba(255, 72, 176, 0.05);
    border-left-color: var(--riso-pink);
  }

  .players-list li.host::after {
    content: " (Host)";
    font-family: var(--f-stamp);
    font-size: 12px;
    color: var(--riso-pink);
    mix-blend-mode: multiply;
  }

  .settings-group {
    margin-bottom: 24px;
  }

  .settings-group label {
    display: block;
    font-family: var(--f-stamp);
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    margin-bottom: 8px;
    color: var(--riso-ink);
  }

  .setting-value {
    font-family: var(--f-display);
    font-size: 32px;
    color: var(--riso-blue);
    text-align: center;
  }

  .slider {
    width: 100%;
    height: 6px;
    border-radius: 3px;
    background: #B9BBB0;
    outline: none;
    -webkit-appearance: none;
    appearance: none;
  }

  .slider::-webkit-slider-thumb {
    -webkit-appearance: none;
    appearance: none;
    width: 24px;
    height: 24px;
    border-radius: 50%;
    background: var(--riso-pink);
    cursor: pointer;
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.2);
  }

  .slider::-moz-range-thumb {
    width: 24px;
    height: 24px;
    border-radius: 50%;
    background: var(--riso-pink);
    cursor: pointer;
    border: none;
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.2);
  }

  .start-btn {
    width: 100%;
    padding: 18px;
    background: var(--riso-yellow);
    border: 2px solid var(--riso-ink);
    color: var(--riso-ink);
    font-family: var(--f-display);
    font-size: 20px;
    cursor: pointer;
    border-radius: 2px;
    mix-blend-mode: multiply;
    transition: all 0.2s ease;
  }

  .start-btn:hover {
    transform: translate(-2px, -2px);
    box-shadow: 4px 4px 0 rgba(0, 0, 0, 0.15);
  }

  .start-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
    transform: none;
  }

  @media (max-width: 640px) {
    .content {
      grid-template-columns: 1fr;
    }

    .code-value {
      font-size: 36px;
    }

    .card h3 {
      font-size: 20px;
    }

    .setting-value {
      font-size: 24px;
    }
  }
</style>

<div class="lobby">
  <div class="header">
    <h1 style="font-family: var(--f-display); font-size: 32px;">
      <span style="color: var(--riso-pink); mix-blend-mode: multiply;">SKETCHY</span>
    </h1>
    <button class="back-btn" on:click={() => dispatch('back')}>
      ← Leave
    </button>
  </div>

  <div class="content">
    <div class="card">
      <h3>Room Code</h3>
      <div class="code-display">
        <div class="code-label">Share this</div>
        <div class="code-value">{roomCode || 'ABCD'}</div>
      </div>

      <h3 style="margin-top: 32px;">Players ({players.length})</h3>
      <ul class="players-list">
        {#each players as player, i}
          <li class={i === 0 ? 'host' : ''}>{player}</li>
        {/each}
      </ul>
    </div>

    <div class="card">
      <h3>Settings</h3>

      <div class="settings-group">
        <label for="rounds">Number of Rounds</label>
        <div class="setting-value">{rounds}</div>
        <input
          id="rounds"
          type="range"
          class="slider"
          min="2"
          max="4"
          bind:value={rounds}
        />
      </div>

      <div class="settings-group">
        <label for="drawtime">Draw Time (seconds)</label>
        <div class="setting-value">{drawTime}s</div>
        <input
          id="drawtime"
          type="range"
          class="slider"
          min="30"
          max="90"
          step="10"
          bind:value={drawTime}
        />
      </div>

      <button
        class="start-btn"
        disabled={players.length < 3}
        on:click={() => console.log('Start game')}
      >
        {players.length < 3 ? `Need ${3 - players.length} more players` : 'START GAME'}
      </button>
    </div>
  </div>
</div>
