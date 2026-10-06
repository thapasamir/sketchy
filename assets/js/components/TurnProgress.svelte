<script>
  import Card from './Card.svelte'
  import Marker from './Marker.svelte'
  import { progress, whenMine } from '../lib/progress.js'

  // How far the drawing has got: "Turn 3 of 6", a marker for each turn (who has drawn, who is
  // drawing, who is still to come) and, for a player, how long until their own turn.
  let { room, playerId } = $props()

  let byId = $derived(Object.fromEntries(room.players.map(p => [p.id, p])))
  let me = $derived(byId[playerId])
  let info = $derived(
    progress({ order: room.turn?.order, laps: room.turn?.laps, turn: room.turn, playerId })
  )
  let laps = $derived(room.turn?.laps ?? 1)
  // the turns grouped by lap, so a gap shows where one lap ends and the next begins
  let groups = $derived(
    info ? Array.from({ length: laps }, (_, i) => info.slots.filter(s => s.lap === i + 1)) : []
  )
  let upNext = $derived(info?.upNext ? byId[info.upNext] : null)
</script>

{#if info}
  <Card id="turn-progress" class="order-3 !p-4 lg:shrink-0 lg:!p-3">
    <div class="mb-2 flex items-baseline justify-between gap-2">
      <h3 class="font-display text-lg">Turn {info.number} of {info.total}</h3>
      {#if laps > 1}
        <span class="font-stamp text-sm text-riso-muted">Lap {room.turn.lap} of {laps}</span>
      {/if}
    </div>

    <div class="flex flex-wrap items-center gap-x-3 gap-y-1.5" role="img" aria-label="Turn {info.number} of {info.total}">
      {#each groups as group, g}
        {#if g > 0}<span class="h-5 w-px bg-riso-line" aria-hidden="true"></span>{/if}
        <div class="flex items-center gap-1">
          {#each group as slot}
            <span
              data-turn-state={slot.state}
              class="grid place-items-center rounded-full transition {slot.state === 'now'
                ? 'bg-riso-yellow p-0.5 ring-2 ring-riso-ink'
                : slot.state === 'done'
                  ? 'opacity-40'
                  : ''}">
              <Marker player={byId[slot.id]} size={slot.state === 'now' ? 24 : 20} />
            </span>
          {/each}
        </div>
      {/each}
    </div>

    <p id="turn-when" class="mt-2.5 font-stamp text-xs text-riso-muted">
      {#if me?.spectator}
        You're watching this round.
      {:else}
        {whenMine(info.turnsUntilMe)}
      {/if}
      {#if upNext && info.turnsUntilMe !== 1 && !me?.spectator}
        Next: <b class="text-riso-ink">{upNext.name}</b>.
      {/if}
    </p>
  </Card>
{/if}
