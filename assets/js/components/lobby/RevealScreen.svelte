<script>
  import RevealCard from './RevealCard.svelte'

  // The moment everyone reads their own card (the word, or "you're the imposter"). It is the one
  // thing that matters for these few seconds, so it gets the whole screen: no room code, no player
  // list, nothing to scroll past to find it.
  let { room, secret, secondsLeft } = $props()
</script>

<div class="mx-auto flex w-full max-w-xl flex-1 flex-col justify-center pb-6">
  <RevealCard {room} {secret} {secondsLeft} />
</div>
