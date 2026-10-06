<script>
  import Card from '../Card.svelte'
  import { TIMING } from '../../lib/cues.js'
  import { play } from '../../lib/sound.js'

  // The card each player reads while everyone else reads theirs. `secret` is null for someone who
  // arrived after the game began: they get no card, only a note.
  let { room, secret, secondsLeft } = $props()

  // the last three seconds are counted out loud: a big number that lands, and a tick
  let counting = $derived(secondsLeft >= 1 && secondsLeft <= 3)
  $effect(() => {
    if (counting) play(secondsLeft === 1 ? 'tickHigh' : 'tick')
  })
</script>

<Card id="secret-card" class="flex min-h-[min(30rem,70dvh)] animate-flip-in flex-col justify-center gap-4 text-center">
  {#if secret}
    <div class="font-stamp text-sm text-riso-muted">
      Round {room.round} of {room.rounds}
    </div>
    <div class="font-stamp text-sm text-riso-muted">
      Category
      <span id="secret-category" class="ml-1 text-riso-ink">{secret.category}</span>
    </div>

    {#if secret.role === 'imposter'}
      <h3
        id="secret-role"
        style="animation-delay:{TIMING.stampStart}ms"
        class="origin-center animate-stamp font-display text-3xl text-riso-pink mix-blend-multiply sm:text-4xl">
        You're the imposter
      </h3>
      <p class="text-riso-muted">You don't know the word. Here is a clue, so blend in:</p>
      <div id="secret-hint" class="mx-auto border-2 border-dashed border-riso-ink bg-white/60 px-5 py-3 font-display text-2xl">
        {secret.hint}
      </div>
      <p class="text-sm text-riso-muted">Watch what the others draw, and don't get caught.</p>
    {:else}
      <h3 id="secret-role" class="font-display text-xl text-riso-muted">Your secret word</h3>
      <div
        id="secret-word"
        style="animation-delay:500ms"
        class="animate-pop font-display text-4xl text-riso-blue sm:text-5xl">
        {secret.word}
      </div>
      <p class="text-sm text-riso-muted">
        You'll take turns adding to one shared drawing. Show you know the word, without making it too
        obvious. One of you doesn't know it.
      </p>
    {/if}
  {:else}
    <!-- no card: they arrived after the game began -->
    <h3 id="spectator-note" class="font-display text-2xl">You're watching</h3>
    <p class="text-sm text-riso-muted">
      The cards are being dealt for this round. You'll be dealt in from the next one.
    </p>
  {/if}

  <!-- the space is kept, so the card doesn't jump when the numbers start -->
  <div class="grid h-24 place-items-center" aria-hidden="true">
    {#if counting}
      {#key secondsLeft}
        <div id="reveal-count" class="animate-count font-display text-8xl leading-none text-riso-pink-ink">{secondsLeft}</div>
      {/key}
    {/if}
  </div>

  <p id="reveal-countdown" class="font-stamp text-sm text-riso-muted">
    Drawing starts in {secondsLeft}s
  </p>
</Card>
