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

{#if currentPage === 'home'}
  <Home on:join={handleJoinRoom} />
{:else if currentPage === 'lobby'}
  <Lobby {roomCode} {playerName} on:back={handleBackHome} />
{/if}
