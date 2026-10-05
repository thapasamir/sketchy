<script>
  // A row of buttons where exactly one is chosen: for a handful of fixed choices, where a slider
  // would make you aim for a number. `options` is [[value, label], ...]; each button's id is
  // `${id}-${value}`.
  let { options, value, onselect, id, label } = $props()
</script>

<!-- the chosen one stands out (yellow, outlined, with a little shadow); the others are quiet until
     pointed at, so a row of seven doesn't shout -->
<div role="group" aria-label={label} class="grid gap-1.5" style="grid-template-columns: repeat({options.length}, minmax(0, 1fr))">
  {#each options as [option, text]}
    <button
      type="button"
      id="{id}-{option}"
      aria-pressed={value === option}
      onclick={() => onselect(option)}
      class="min-h-11 cursor-pointer rounded-[3px] border-2 px-1 py-2 font-stamp text-sm transition active:scale-[0.97] {value === option
        ? 'border-riso-ink bg-riso-yellow shadow-[2px_2px_0_rgb(0_0_0/0.18)]'
        : 'border-transparent bg-riso-ink/[0.06] hover:bg-riso-ink/[0.12]'}">
      {text}
    </button>
  {/each}
</div>
