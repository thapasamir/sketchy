<script>
  import Home from './pages/Home.svelte'
  import Lobby from './pages/Lobby.svelte'

  let currentPage = 'home'
  let roomCode = null
  let playerName = null
  let playerId = null

  function handleJoinRoom(e) {
    roomCode = e.detail.code
    playerName = e.detail.name
    playerId = e.detail.playerId ?? null
    currentPage = 'lobby'
  }

  function handleBackHome() {
    currentPage = 'home'
    roomCode = null
    playerName = null
    playerId = null
  }
</script>

{#if currentPage === 'home'}
  <Home on:join={handleJoinRoom} />
{:else if currentPage === 'lobby'}
  <Lobby {roomCode} {playerName} {playerId} on:back={handleBackHome} />
{/if}
