<script>
  import Button from '../Button.svelte'
  import Modal from '../Modal.svelte'
  import Segmented from '../Segmented.svelte'
  import WordSettings from './WordSettings.svelte'

  // The host's controls for the game. Every tap is sent at once (the lobby behind shows it
  // changing), so there is nothing to save: "Done" just closes this.
  let { session, onclose } = $props()

  const ROUNDS = [2, 3, 4].map(n => [n, String(n)])
  const SECONDS = [30, 40, 50, 60, 70, 80, 90].map(n => [n, `${n}s`])
  const LAPS = [
    ['auto', 'Auto'],
    [1, '1'],
    [2, '2'],
  ]

  let room = $derived(session.room)
  let players = $derived(session.players)
  let turnsPerWord = $derived(players.length * (room.laps_now ?? 1))
  let laps = $derived(room.settings.laps)
</script>

<Modal id="settings-dialog" title="Game settings" {onclose}>
  <section>
    <div class="mb-2 font-stamp text-xs uppercase tracking-widest">Rounds</div>
    <Segmented id="rounds" label="Number of rounds" options={ROUNDS} value={room.settings.rounds} onselect={value => session.updateSettings({ rounds: value })} />
  </section>

  <section class="mt-6">
    <div class="mb-2 font-stamp text-xs uppercase tracking-widest">Time per turn</div>
    <Segmented id="drawtime" label="Seconds per turn" options={SECONDS} value={room.settings.draw_time} onselect={value => session.updateSettings({ draw_time: value })} />
  </section>

  <section class="mt-6">
    <div id="laps-label" class="mb-2 font-stamp text-xs uppercase tracking-widest">Laps per word</div>
    <Segmented id="laps" label="Laps per word" options={LAPS} value={laps} onselect={value => session.updateSettings({ laps: value })} />
    <p class="mt-2 font-stamp text-xs text-riso-muted">
      {#if laps === 'auto'}
        Auto: {room.laps_now} {room.laps_now === 1 ? 'lap' : 'laps'} with {players.length} {players.length === 1 ? 'player' : 'players'}, so {turnsPerWord} {turnsPerWord === 1 ? 'turn' : 'turns'} per word.
      {:else}
        Everyone draws {laps === 1 ? 'once' : 'twice'} per word, so {turnsPerWord} {turnsPerWord === 1 ? 'turn' : 'turns'}.
      {/if}
    </p>
  </section>

  <div class="mt-6 border-t-2 border-riso-ink/10 pt-6">
    <WordSettings {room} update={session.updateSettings} />
  </div>

  {#snippet footer()}
    {#if session.actionError}
      <p class="mb-2 font-stamp text-sm text-riso-stamp" role="alert">{session.actionError}</p>
    {/if}
    <Button id="settings-done" variant="yellow" class="w-full py-3 text-lg" onclick={onclose}>Done</Button>
  {/snippet}
</Modal>
