<script>
  import Button from '../Button.svelte'
  import Modal from '../Modal.svelte'
  import Segmented from '../Segmented.svelte'
  import WordSettings from './WordSettings.svelte'
  import { maxGameSeconds, describeLength, paceOf, turnsPerWord } from '../../lib/gametime.js'

  // The host's controls for the game. Every tap is sent at once (the lobby behind shows it
  // changing), so there is nothing to save: "Done" just closes this. Each setting says what it is,
  // shows what it is set to, and the bottom says what it all adds up to.
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
  let laps = $derived(room.settings.laps)
  let turns = $derived(turnsPerWord(players.length, room.laps_now))
  let length = $derived(
    describeLength(
      maxGameSeconds({ rounds: room.settings.rounds, drawTime: room.settings.draw_time, players: players.length, lapsNow: room.laps_now })
    )
  )

  const heading = 'font-stamp text-sm'
</script>

<Modal id="settings-dialog" title="Game settings" {onclose}>
  <section>
    <div class="flex items-baseline justify-between gap-3">
      <h3 class={heading}>Rounds</h3>
      <span class="font-display text-xl text-riso-blue">{room.settings.rounds}</span>
    </div>
    <p class="mb-2 font-stamp text-xs text-riso-muted">Every round is a new secret word, and a new imposter.</p>
    <Segmented id="rounds" label="Number of rounds" options={ROUNDS} value={room.settings.rounds} onselect={value => session.updateSettings({ rounds: value })} />
  </section>

  <section class="mt-6">
    <div class="flex items-baseline justify-between gap-3">
      <h3 class={heading}>Time per turn</h3>
      <span class="font-display text-xl text-riso-blue">{room.settings.draw_time} seconds</span>
    </div>
    <p class="mb-2 font-stamp text-xs text-riso-muted">{paceOf(room.settings.draw_time)}. A turn ends early when the drawer taps "I'm done".</p>
    <Segmented id="drawtime" label="Seconds per turn" options={SECONDS} value={room.settings.draw_time} onselect={value => session.updateSettings({ draw_time: value })} />
  </section>

  <section class="mt-6">
    <div class="flex items-baseline justify-between gap-3">
      <h3 id="laps-label" class={heading}>Laps per word</h3>
      <span class="font-display text-xl text-riso-blue">{laps === 'auto' ? 'Auto' : laps}</span>
    </div>
    <p class="mb-2 font-stamp text-xs text-riso-muted">How many times everyone draws on a word before the vote.</p>
    <Segmented id="laps" label="Laps per word" options={LAPS} value={laps} onselect={value => session.updateSettings({ laps: value })} />
    <p class="mt-2 font-stamp text-xs text-riso-muted">
      {#if laps === 'auto'}
        Auto: {room.laps_now} {room.laps_now === 1 ? 'lap' : 'laps'} with {players.length} {players.length === 1 ? 'player' : 'players'}, so {turns} {turns === 1 ? 'turn' : 'turns'} per word.
      {:else}
        Everyone draws {laps === 1 ? 'once' : 'twice'} per word, so {turns} {turns === 1 ? 'turn' : 'turns'}.
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
    <p id="game-length" class="mb-3 text-center font-stamp text-xs text-riso-muted">
      This game takes <b class="text-riso-ink">{length}</b>.
    </p>
    <Button id="settings-done" variant="yellow" class="w-full py-3 text-lg" onclick={onclose}>Done</Button>
  {/snippet}
</Modal>
