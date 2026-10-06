<script>
  import { REACTIONS } from '../lib/reactions.js'
  import Sticker from './Sticker.svelte'

  // `react` is called with a reaction's id
  export let react = () => {}

  // the server allows one every 0.4s; waiting a little here means a quick tapper isn't refused
  let cooling = false
  function tap(id) {
    if (cooling) return
    cooling = true
    react(id)
    setTimeout(() => (cooling = false), 450)
  }
</script>

<div id="reaction-bar" class="flex w-full shrink-0 items-center justify-between gap-1 lg:w-auto lg:justify-end" role="group" aria-label="React">
  {#each REACTIONS as reaction (reaction.id)}
    <button
      type="button"
      data-react={reaction.id}
      aria-label={reaction.label}
      on:click={() => tap(reaction.id)}
      class="grid h-11 w-11 min-w-0 shrink cursor-pointer place-items-center rounded-[3px] border-2 border-transparent p-0.5 transition lg:h-9 lg:w-9 hover:-rotate-6 hover:border-riso-line active:scale-90">
      <Sticker id={reaction.id} />
    </button>
  {/each}
</div>
