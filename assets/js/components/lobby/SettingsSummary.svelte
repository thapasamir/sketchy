<script>
  import { chosenCategories } from '../../lib/categories.js'

  // What the host has chosen, for everyone who can't change it: plain facts, not controls that
  // look like they should work. `hostName` is who decides.
  let { room, players, hostName, isHost = false } = $props()

  const DIFFICULTY = { easy: 'Easy only', medium: 'Easy + medium', all: 'Easy to hard' }

  let laps = $derived(room.settings.laps)
  let turnsPerWord = $derived(players.length * (room.laps_now ?? 1))
  let everything = $derived(room.settings.categories === 'all')
  let chosen = $derived(chosenCategories(room.settings.categories, room.words.categories))
</script>

<dl class="flex flex-col divide-y divide-riso-line rounded-[3px] border-2 border-riso-line bg-white/60">
  <div class="flex items-baseline justify-between gap-4 px-3 py-2.5">
    <dt class="font-stamp text-xs uppercase tracking-widest">Rounds</dt>
    <dd id="rounds-value" class="font-display text-2xl text-riso-blue">{room.settings.rounds}</dd>
  </div>
  <div class="flex items-baseline justify-between gap-4 px-3 py-2.5">
    <dt class="font-stamp text-xs uppercase tracking-widest">Time per turn</dt>
    <dd id="drawtime-value" class="font-display text-2xl text-riso-blue">{room.settings.draw_time}s</dd>
  </div>
  <div class="px-3 py-2.5">
    <div class="flex items-baseline justify-between gap-4">
      <dt class="font-stamp text-xs uppercase tracking-widest">Laps per word</dt>
      <dd id="laps-value" class="font-display text-2xl text-riso-blue">{laps === 'auto' ? 'Auto' : laps}</dd>
    </div>
    <p id="laps-hint" class="mt-1 font-stamp text-xs text-riso-muted">
      {#if laps === 'auto'}
        Auto: {room.laps_now} {room.laps_now === 1 ? 'lap' : 'laps'} with {players.length} {players.length === 1 ? 'player' : 'players'}, so {turnsPerWord} {turnsPerWord === 1 ? 'turn' : 'turns'} per word.
      {:else}
        Everyone draws {laps === 1 ? 'once' : 'twice'} per word, so {turnsPerWord} {turnsPerWord === 1 ? 'turn' : 'turns'}.
      {/if}
    </p>
  </div>
  <div class="px-3 py-2.5">
    <div class="flex items-baseline justify-between gap-4">
      <dt class="font-stamp text-xs uppercase tracking-widest">Words</dt>
      <dd id="words-value" class="font-stamp text-sm">{DIFFICULTY[room.settings.difficulty] ?? ''}</dd>
    </div>
    <dd id="words-summary" class="mt-1.5 flex flex-wrap gap-1.5">
      {#if everything}
        <span class="rounded-full border border-riso-line bg-white/70 px-2.5 py-0.5 font-stamp text-xs">All categories · {room.words.pool} words</span>
      {:else}
        {#each chosen as name}
          <span data-chosen-category={name} class="rounded-full border border-riso-ink bg-riso-yellow/50 px-2.5 py-0.5 font-stamp text-xs">{name}</span>
        {/each}
        <span class="px-1 py-0.5 font-stamp text-xs text-riso-muted">{room.words.pool} words</span>
      {/if}
    </dd>
  </div>
</dl>

{#if !isHost}
  <p id="host-decides" class="font-stamp text-xs text-riso-muted">
    <b class="text-riso-ink">{hostName}</b> chooses these. They change live if the host changes them.
  </p>
{/if}
