<script>
  import Sticker from './Sticker.svelte'

  // Reactions floating up over the picture. They don't take taps (the drawing underneath still
  // does) and are hidden from screen readers, who'd only hear a stream of names.
  export let reactions = []
</script>

<div class="pointer-events-none absolute inset-0 overflow-hidden" aria-hidden="true" data-reactions>
  {#each reactions as item (item.key)}
    <span data-reaction data-reaction-id={item.id} class="animate-float absolute bottom-2 flex -translate-x-1/2 flex-col items-center" style="left:{item.x}%">
      <span class="block h-14 w-14 drop-shadow" style="transform:rotate({(item.key % 5) * 6 - 12}deg)"><Sticker id={item.id} /></span>
      <span class="mt-0.5 max-w-24 truncate rounded-[2px] bg-riso-ink/70 px-1.5 font-stamp text-[0.65rem] text-white">{item.name}</span>
    </span>
  {/each}
</div>
