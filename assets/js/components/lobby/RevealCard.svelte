<script>
  import Card from '../Card.svelte'
  import { TIMING } from '../../lib/cues.js'

  // The card each player reads while everyone else reads theirs. `secret` is null for someone who
  // arrived after the game began: they get no card, only a note.
  let { room, secret, secondsLeft } = $props()
</script>

<Card id="secret-card" class="flex animate-flip-in flex-col justify-center gap-4 text-center">
  {#if secret}
    <div class="font-stamp text-xs uppercase tracking-widest text-riso-muted">
      Round {room.round} of {room.rounds}
    </div>
    <div class="font-stamp text-xs uppercase tracking-widest text-riso-muted">
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

  <p id="reveal-countdown" class="font-stamp text-sm uppercase tracking-widest text-riso-muted">
    Drawing starts in {secondsLeft}s
  </p>
</Card>
