<script>
  import Card from './Card.svelte'

  // Your secret: the word for the crew, the clue for the imposter. The biggest thing in the sidebar,
  // because it is what you glance back at while you draw. It can be hidden (someone may be looking
  // over your shoulder).
  export let secret
  export let hidden = false
</script>

<Card
  id="secret-card"
  class="order-4 shrink-0 !p-4 text-center shadow-[4px_4px_0_var(--color-riso-pink)] lg:order-1 lg:!p-5">
  <div class="mb-2 flex items-center justify-between gap-2 text-left">
    <div class="font-stamp text-sm text-riso-muted">
      Category <span id="secret-category" class="ml-1 text-riso-ink">{secret.category}</span>
    </div>
    <button
      type="button"
      id="secret-toggle"
      on:click={() => (hidden = !hidden)}
      class="cursor-pointer font-stamp text-xs text-riso-muted underline hover:text-riso-ink">
      {hidden ? 'show' : 'hide'}
    </button>
  </div>

  {#if hidden}
    <p class="py-4 font-stamp text-sm text-riso-muted">Your card is hidden.</p>
  {:else if secret.role === 'imposter'}
    <h3 id="secret-role" class="font-display text-2xl text-riso-pink mix-blend-multiply lg:text-3xl">You're the imposter</h3>
    <p class="mt-1 text-sm text-riso-muted">You don't know the word. Your clue:</p>
    <div
      id="secret-hint"
      class="mx-auto mt-2 inline-block border-2 border-dashed border-riso-ink bg-white/60 px-4 py-1.5 font-display text-xl">
      {secret.hint}
    </div>
  {:else}
    <h3 id="secret-role" class="font-stamp text-sm text-riso-muted">Your secret word</h3>
    <div id="secret-word" class="mt-1 break-words font-display text-3xl leading-tight text-riso-blue lg:text-4xl">{secret.word}</div>
  {/if}
</Card>
