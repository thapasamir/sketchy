<script>
  import Button from '../Button.svelte'

  // The one thing to do next: "start" for the host, "I'm ready" for everyone else.
  let { session } = $props()

  let missing = $derived(session.minPlayers - session.connectedCount)
</script>

{#if session.actionError}
  <p class="font-stamp text-sm text-riso-stamp" role="alert">{session.actionError}</p>
{/if}

{#if session.isHost}
  <Button
    id="start-button"
    variant="yellow"
    class="w-full py-4 text-xl"
    disabled={!session.canStart}
    onclick={session.startGame}>
    {#if missing > 0}
      Need {missing} more {missing === 1 ? 'player' : 'players'}
    {:else if session.waitingFor > 0}
      Waiting for {session.waitingFor} to get ready
    {:else}
      START GAME
    {/if}
  </Button>
{:else}
  <div>
    <Button
      id="ready-button"
      variant={session.myReady ? 'blue' : 'yellow'}
      class="w-full py-4 text-xl"
      onclick={session.toggleReady}>
      {session.myReady ? 'Ready (tap to undo)' : "I'M READY"}
    </Button>
    <p class="mt-3 text-center font-stamp text-xs text-riso-muted">
      {#if missing > 0}
        Need {missing} more {missing === 1 ? 'player' : 'players'} before the host can start.
      {:else}
        The host starts once everyone is ready.
      {/if}
    </p>
  </div>
{/if}
