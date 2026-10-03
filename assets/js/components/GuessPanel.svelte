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

<Card id="guess-panel" class="!p-4">
  {#if iAmCaught}
    <h3 class="font-display text-lg">One last chance</h3>
    <p class="mt-1 text-sm text-riso-muted">
      Guess the secret word and you still score. Category: <b>{secret?.category}</b>.
    </p>
    <form class="mt-3 flex flex-col gap-2 sm:flex-row lg:flex-col" on:submit|preventDefault={submit}>
      <input
        id="guess-input"
        bind:this={input}
        bind:value={text}
        maxlength="60"
        autocomplete="off"
        autocapitalize="off"
        placeholder="The word is…"
        disabled={sent}
        class="min-w-0 flex-1 rounded-[3px] border-2 border-riso-ink bg-white/80 px-3 py-2.5 text-base outline-none focus:border-riso-blue focus:ring-2 focus:ring-riso-blue/30" />
      <Button id="guess-button" variant="yellow" type="submit" class="px-5 py-2.5 text-base" disabled={!text.trim() || sent}>
        {sent ? 'Sent' : 'Guess'}
      </Button>
    </form>
  {:else}
    <h3 id="guess-wait" class="font-display text-lg">{imposterName} is guessing the word…</h3>
    <p class="mt-1 text-sm text-riso-muted">
      You caught them. If they guess the word they still win a point, so keep it to yourself.
    </p>
  {/if}
</Card>
