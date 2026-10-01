<script>
  import { createEventDispatcher } from 'svelte'
  import Wordmark from '../components/Wordmark.svelte'
  import Button from '../components/Button.svelte'
  import Card from '../components/Card.svelte'

  const dispatch = createEventDispatcher()

  export let roomCode = ''
  export let playerName = ''

  let players = [playerName]
  let rounds = 3
  let drawTime = 60

  const labelClass = 'mb-2 block font-stamp text-xs uppercase tracking-widest'
</script>

<main class="mx-auto flex min-h-dvh w-full max-w-4xl flex-col gap-8 px-4 py-6 sm:py-8">
  <header class="flex items-center justify-between gap-4">
    <Wordmark class="text-3xl sm:text-4xl" />
    <Button class="px-4 py-2.5 font-stamp text-sm sm:px-6" on:click={() => dispatch('back')}>← Leave</Button>
  </header>

  <div class="grid gap-6 md:grid-cols-2">
    <Card>
      <h3 class="mb-5 font-display text-2xl sm:text-3xl">Room Code</h3>
      <div class="border-2 border-riso-ink bg-white/60 p-5 text-center">
        <div class="mb-2 font-stamp text-xs uppercase tracking-widest text-riso-muted">Share this</div>
        <div class="pl-[0.2em] font-display text-4xl tracking-[0.2em] text-riso-pink mix-blend-multiply sm:text-5xl">
          {roomCode || 'ABCD'}
        </div>
      </div>

      <h3 class="mb-4 mt-8 font-display text-2xl sm:text-3xl">Players ({players.length})</h3>
      <ul class="flex flex-col gap-2">
        {#each players as player, i}
          <li
            class="rounded-[2px] border-l-4 p-3 {i === 0
              ? 'border-riso-pink bg-riso-pink/5'
              : 'border-riso-blue bg-riso-blue/5'}">
            {player}
            {#if i === 0}<span class="font-stamp text-xs text-riso-pink mix-blend-multiply">(Host)</span>{/if}
          </li>
        {/each}
      </ul>
    </Card>

    <Card class="flex flex-col gap-6">
      <h3 class="font-display text-2xl sm:text-3xl">Settings</h3>

      <div>
        <label for="rounds" class={labelClass}>Number of Rounds</label>
        <div class="mb-2 text-center font-display text-3xl text-riso-blue">{rounds}</div>
        <input id="rounds" type="range" class="riso-slider" min="2" max="4" bind:value={rounds} />
      </div>

      <div>
        <label for="drawtime" class={labelClass}>Draw Time (seconds)</label>
        <div class="mb-2 text-center font-display text-3xl text-riso-blue">{drawTime}s</div>
        <input id="drawtime" type="range" class="riso-slider" min="30" max="90" step="10" bind:value={drawTime} />
      </div>

      <Button
        variant="yellow"
        class="mt-auto w-full py-4 text-xl"
        disabled={players.length < 3}
        on:click={() => console.log('Start game')}>
        {players.length < 3 ? `Need ${3 - players.length} more players` : 'START GAME'}
      </Button>
    </Card>
  </div>
</main>
