<script>
  import Card from '../Card.svelte'
  import SettingsModal from './SettingsModal.svelte'
  import SettingsSummary from './SettingsSummary.svelte'

  // What the game will be like. Everyone sees the same summary; the host also gets "Change", which
  // opens the controls in a dialog.
  let { session } = $props()

  let room = $derived(session.room)
  let isHost = $derived(session.isHost)
  let players = $derived(session.players)
  let hostName = $derived(players.find(p => p.id === room.host_id)?.name ?? 'The host')

  let editing = $state(false)
</script>

<Card class="!p-5">
  <div class="mb-3 flex items-center justify-between gap-3">
    <h3 class="font-display text-xl">Settings</h3>
    {#if isHost}
      <button
        type="button"
        id="edit-settings"
        onclick={() => (editing = true)}
        class="cursor-pointer rounded-[3px] border-2 border-riso-ink px-3 py-1 font-stamp text-xs transition hover:bg-riso-yellow">
        Change settings
      </button>
    {/if}
  </div>

  <div class="flex flex-col gap-3">
    <SettingsSummary {room} {players} {hostName} {isHost} />
  </div>
</Card>

{#if editing}
  <SettingsModal {session} onclose={() => (editing = false)} />
{/if}
