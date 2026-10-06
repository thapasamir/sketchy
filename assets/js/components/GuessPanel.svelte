<script>
  import { onMount } from 'svelte'
  import Button from './Button.svelte'
  import Card from './Card.svelte'

  export let room
  export let playerId
  export let secret
  export let submitGuess = () => {}

  let text = ''
  let sent = false
  let input

  $: imposterName = room.players.find(p => p.id === room.guess?.guesser_id)?.name ?? 'The imposter'
  $: iAmCaught = room.guess?.guesser_id === playerId

  onMount(() => input?.focus())

  function submit() {
    if (!text.trim() || sent) return
    sent = true
    submitGuess(text.trim())
  }
</script>

<!-- red and pink like the vote: this is the moment the round turns on -->
<Card id="guess-panel" class="animate-rise !border-riso-stamp !bg-riso-pink/10 !p-4">
  <div class="-mx-4 -mt-4 mb-3 bg-riso-stamp px-4 py-1 font-stamp text-xs uppercase tracking-widest text-white">
    {iAmCaught ? 'Last chance' : 'The imposter is caught'}
  </div>

  {#if iAmCaught}
    <h3 class="font-display text-xl">Guess the secret word</h3>
    <p class="mt-1 text-sm text-riso-muted">Get it right and you still score a point.</p>

    <!-- what you have to go on, so you needn't scroll back for it -->
    <div class="mt-3 flex flex-wrap items-center gap-x-4 gap-y-1 font-stamp text-xs text-riso-muted">
      <span>Category <b id="guess-category" class="ml-1 text-sm text-riso-ink">{secret?.category}</b></span>
      {#if secret?.hint}<span>Your clue <b class="ml-1 text-sm text-riso-ink">{secret.hint}</b></span>{/if}
    </div>

    <form class="mt-3 flex flex-col gap-2 sm:flex-row lg:flex-col" on:submit|preventDefault={submit}>
      <input
        id="guess-input"
        bind:this={input}
        bind:value={text}
        maxlength="60"
        autocomplete="off"
        autocapitalize="off"
        enterkeyhint="send"
        placeholder="The word is…"
        disabled={sent}
        class="min-w-0 flex-1 rounded-[3px] border-2 border-riso-ink bg-white px-3 py-3 font-display text-2xl outline-none placeholder:font-type placeholder:text-base placeholder:text-riso-muted focus:border-riso-blue focus:ring-2 focus:ring-riso-blue/30" />
      <Button id="guess-button" variant="yellow" type="submit" class="w-full px-5 py-3 text-lg sm:w-auto lg:w-full" disabled={!text.trim() || sent}>
        {sent ? 'Sent' : text.trim() ? 'Guess' : 'Type a guess'}
      </Button>
    </form>
    <p id="guess-note" class="mt-2 font-stamp text-xs text-riso-muted">
      {sent ? 'Waiting for the result…' : 'One try. A small spelling slip is forgiven; a different word is not.'}
    </p>
  {:else}
    <h3 id="guess-wait" class="font-display text-xl">{imposterName} is guessing the word…</h3>
    <p class="mt-1 text-sm text-riso-muted">
      You caught them. If they guess the word they still win a point, so keep it to yourself.
    </p>
  {/if}
</Card>
