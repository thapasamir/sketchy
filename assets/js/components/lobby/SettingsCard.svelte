<script>
  import Button from '../Button.svelte'
  import Card from '../Card.svelte'
  import WordSettings from './WordSettings.svelte'

  // The game's settings and the button that moves things along: "start" for the host, "I'm ready"
  // for everyone else. Everyone sees the settings; only the host can change them.
  let { session } = $props()

  const LAP_CHOICES = [
    ['auto', 'Auto'],
    [1, '1'],
    [2, '2'],
  ]
  const labelClass = 'mb-2 block font-stamp text-xs uppercase tracking-widest'

  let room = $derived(session.room)
  let isHost = $derived(session.isHost)
  let players = $derived(session.players)

  // The sliders show whatever the server says; they follow the host's finger until it does.
  let rounds = $derived(room.settings.rounds)
  let drawTime = $derived(room.settings.draw_time)
  let laps = $derived(room.settings.laps)
  let turnsPerWord = $derived(players.length * (room.laps_now ?? 1))

  const saveSliders = () => session.updateSettings({ rounds: Number(rounds), draw_time: Number(drawTime) })

  let missing = $derived(session.minPlayers - session.connectedCount)
</script>

<Card class="flex flex-col gap-6">
  <div class="flex items-baseline justify-between gap-3">
    <h3 class="font-display text-2xl sm:text-3xl">Settings</h3>
    {#if !isHost}
      <span class="font-stamp text-xs uppercase tracking-widest text-riso-muted">Host decides</span>
    {/if}
  </div>

  <div>
    <label for="rounds" class={labelClass}>Number of rounds</label>
    <div id="rounds-value" class="mb-2 text-center font-display text-3xl text-riso-blue">{rounds}</div>
    <input
      id="rounds"
      type="range"
      class="riso-slider disabled:opacity-60"
      min="2"
      max="4"
      disabled={!isHost}
      bind:value={rounds}
      onchange={saveSliders} />
  </div>

  <div>
    <label for="drawtime" class={labelClass}>Seconds per turn</label>
    <div id="drawtime-value" class="mb-2 text-center font-display text-3xl text-riso-blue">{drawTime}s</div>
    <input
      id="drawtime"
      type="range"
      class="riso-slider disabled:opacity-60"
      min="30"
      max="90"
      step="10"
      disabled={!isHost}
      bind:value={drawTime}
      onchange={saveSliders} />
  </div>

  <div>
    <div id="laps-label" class={labelClass}>Laps per word</div>
    <div class="grid grid-cols-3 gap-2" role="group" aria-labelledby="laps-label">
      {#each LAP_CHOICES as [value, label]}
        <button
          type="button"
          id="laps-{value}"
          aria-pressed={laps === value}
          disabled={!isHost}
          onclick={() => session.updateSettings({ laps: value })}
          class="min-h-11 cursor-pointer rounded-[3px] border-2 px-3 py-2 font-stamp text-sm transition disabled:cursor-default {laps === value
            ? 'border-riso-ink bg-riso-yellow'
            : 'border-riso-line bg-white/60 enabled:hover:border-riso-ink'} {!isHost && laps !== value ? 'opacity-60' : ''}">
          {label}
        </button>
      {/each}
    </div>
    <p id="laps-hint" class="mt-2 font-stamp text-xs text-riso-muted">
      {#if laps === 'auto'}
        Auto: {room.laps_now} {room.laps_now === 1 ? 'lap' : 'laps'} with {players.length} {players.length === 1 ? 'player' : 'players'}, so {turnsPerWord} {turnsPerWord === 1 ? 'turn' : 'turns'} per word.
      {:else}
        Everyone draws {laps === 1 ? 'once' : 'twice'} per word, so {turnsPerWord} {turnsPerWord === 1 ? 'turn' : 'turns'}.
      {/if}
    </p>
  </div>

  <WordSettings {room} {isHost} update={session.updateSettings} />

  {#if session.actionError}
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
