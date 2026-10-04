<script>
  import { REACTIONS } from '../lib/reactions.js'

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

<div id="reaction-bar" class="flex shrink-0 items-center gap-1" role="group" aria-label="React">
  {#each REACTIONS as reaction (reaction.id)}
    <button
      type="button"
      data-react={reaction.id}
      aria-label={reaction.label}
      on:click={() => tap(reaction.id)}
      class="grid h-11 w-11 cursor-pointer place-items-center rounded-[3px] border-2 border-transparent text-2xl transition lg:h-9 lg:w-9 lg:text-xl hover:border-riso-line active:scale-90">
      <span aria-hidden="true">{reaction.emoji}</span>
    </button>
  {/each}
</div>
