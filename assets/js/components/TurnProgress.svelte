<script>
  import Card from './Card.svelte'
  import Marker from './Marker.svelte'
  import { progress, whenMine } from '../lib/progress.js'

  // The drawing order and how far it has got, in one card: a face and name for each player in the
  // order they draw, the one drawing now lit up, the ones who have drawn this lap faded; under it
  // "Turn 3 of 6", how long until your own turn, and who is only watching.
  let { room, playerId } = $props()

  let byId = $derived(Object.fromEntries(room.players.map(p => [p.id, p])))
  let me = $derived(byId[playerId])
  let info = $derived(
    progress({ order: room.turn?.order, laps: room.turn?.laps, turn: room.turn, playerId })
  )
  let laps = $derived(room.turn?.laps ?? 1)
  // each player once, in drawing order, with where they are in this lap
  let lap = $derived(info ? info.slots.filter(s => s.lap === room.turn.lap) : [])
  let upNext = $derived(info?.upNext ? byId[info.upNext] : null)
  let watchers = $derived(room.players.filter(p => p.spectator))
</script>

{#if info}
  <Card id="turn-progress" class="order-3 shrink-0 !p-4 lg:!p-4">
    <div class="mb-3 flex items-baseline justify-between gap-2">
      <h3 class="font-display text-lg">Turn {info.number} of {info.total}</h3>
      {#if laps > 1}
        <span class="font-stamp text-sm text-riso-muted">Lap {room.turn.lap} of {laps}</span>
      {/if}
    </div>

    <ol id="turn-order" class="flex flex-wrap items-start gap-x-1 gap-y-2" aria-label="Drawing order">
      {#each lap as slot, i (slot.id)}
        {@const player = byId[slot.id]}
        {#if player}
          <li
            data-player={player.name}
            data-drawing={slot.state === 'now'}
            data-turn-state={slot.state}
            class="flex w-[4.25rem] flex-col items-center gap-0.5 rounded-[3px] px-1 py-1.5 text-center transition {slot.state === 'now'
              ? 'bg-riso-yellow/70 ring-2 ring-riso-ink'
              : slot.state === 'done'
                ? 'opacity-45'
                : ''} {player.connected ? '' : 'opacity-50'}">
            <Marker {player} size={slot.state === 'now' ? 44 : 38} />
            <span class="w-full break-words text-xs leading-tight">
              {player.name}{#if player.id === playerId}<span class="font-stamp text-riso-muted"> (you)</span>{/if}
              {#if !player.connected}<span class="block font-stamp text-riso-muted">(away)</span>{/if}
            </span>
          </li>
          {#if i < lap.length - 1}
            <span class="mt-5 font-stamp text-riso-line" aria-hidden="true">›</span>
          {/if}
        {/if}
      {/each}
    </ol>

    <p id="turn-when" class="mt-3 font-stamp text-xs text-riso-muted">
      {#if me?.spectator}
        You're watching this round.
      {:else}
        {whenMine(info.turnsUntilMe)}
      {/if}
      {#if upNext && info.turnsUntilMe !== 1 && !me?.spectator}
        Next: <b class="text-riso-ink">{upNext.name}</b>.
      {/if}
    </p>
    {#if watchers.length}
      <p id="watchers" class="mt-1 font-stamp text-xs text-riso-muted">
        Watching: {watchers.map(w => w.name + (w.id === playerId ? ' (you)' : '')).join(', ')}
      </p>
    {/if}
  </Card>
{/if}
