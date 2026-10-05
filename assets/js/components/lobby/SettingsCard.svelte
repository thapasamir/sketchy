<script>
  import Button from '../Button.svelte'
  import Card from '../Card.svelte'
  import SettingsModal from './SettingsModal.svelte'
  import SettingsSummary from './SettingsSummary.svelte'

  // What the game will be like, and the button that moves things along. Everyone sees the same
  // summary. The host also gets "Change settings" (which opens the controls in a dialog) and the
  // "start" button; everyone else gets "I'm ready".
  let { session } = $props()

  let room = $derived(session.room)
  let isHost = $derived(session.isHost)
  let players = $derived(session.players)
  let hostName = $derived(players.find(p => p.id === room.host_id)?.name ?? 'The host')
  let missing = $derived(session.minPlayers - session.connectedCount)

  let editing = $state(false)
</script>

<Card class="flex flex-col gap-5">
  <h3 class="font-display text-2xl sm:text-3xl">Settings</h3>

  <SettingsSummary {room} {players} {hostName} {isHost} />

  {#if isHost}
    <Button id="edit-settings" class="w-full py-2.5 text-base" onclick={() => (editing = true)}>Change settings</Button>
  {/if}

  {#if session.actionError && !editing}
    <p class="font-stamp text-sm text-riso-stamp" role="alert">{session.actionError}</p>
  {/if}

  {#if isHost}
    <Button
      id="start-button"
      variant="yellow"
      class="mt-auto w-full py-4 text-xl"
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
    <div class="mt-auto">
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
</Card>

{#if editing}
  <SettingsModal {session} onclose={() => (editing = false)} />
{/if}
