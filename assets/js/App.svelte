<script>
  import Home from './pages/Home.svelte'
  import Lobby from './pages/Lobby.svelte'

  let currentPage = 'home'
  let roomCode = null
  let playerName = null

  function handleJoinRoom(e) {
    roomCode = e.detail.code
    playerName = e.detail.name
    currentPage = 'lobby'
  }

  function handleBackHome() {
    currentPage = 'home'
    roomCode = null
    playerName = null
  }
</script>

<style global>
  :root {
    --riso-paper: #F4F2EC;
    --riso-pink: #FF48B0;
    --riso-blue: #0078BF;
    --riso-yellow: #FFE800;
    --riso-ink: #263A6E;

    --f-display: "Bowlby One", "Arial Black", Impact, sans-serif;
    --f-type: "Courier Prime", "Courier New", monospace;
    --f-stamp: "Special Elite", "Courier New", monospace;
  }

  * {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
  }

  body {
    background: linear-gradient(135deg, #F4F2EC 0%, #EFEDE6 100%);
    color: var(--riso-ink);
    font-family: var(--f-type);
    min-height: 100vh;
  }

  :global(button) {
    font-family: var(--f-display);
    cursor: pointer;
    border: none;
    border-radius: 2px;
    transition: all 0.2s ease;
  }

  :global(input) {
    font-family: var(--f-type);
    border: 2px solid var(--riso-ink);
    padding: 10px 12px;
    border-radius: 2px;
  }
</style>

{#if currentPage === 'home'}
  <Home on:join={handleJoinRoom} />
{:else if currentPage === 'lobby'}
  <Lobby {roomCode} {playerName} on:back={handleBackHome} />
{/if}
