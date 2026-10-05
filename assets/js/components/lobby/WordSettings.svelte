<script>
  // Which words come up: how hard they may be, and which categories. Everyone sees the choice;
  // only the host can change it. `update(changes)` sends a change to the server.
  let { room, isHost, update } = $props()

  const DIFFICULTY_CHOICES = [
    ['easy', 'Easy only'],
    ['medium', 'Easy + medium'],
    ['all', 'All'],
  ]
  const labelClass = 'mb-2 block font-stamp text-xs uppercase tracking-widest'

  let allNames = $derived(room.words.categories)
  // the server says 'all' or a list; the chips always want a list
  let chosen = $derived(room.settings.categories === 'all' ? allNames : room.settings.categories)
  let difficulty = $derived(room.settings.difficulty)

  function toggleCategory(name) {
    const next = chosen.includes(name) ? chosen.filter(c => c !== name) : [...chosen, name]
    if (next.length === 0) return // at least one category stays chosen
    update({ categories: next.length === allNames.length ? 'all' : next })
  }
</script>

<details id="words-settings" class="group">
  <summary class="{labelClass} cursor-pointer">
    Words
    <span id="words-summary" class="normal-case text-riso-muted">
      · {room.settings.categories === 'all' ? 'all categories' : `${chosen.length} of ${allNames.length} categories`}, {room.words.pool} words
    </span>
  </summary>
  <div class="mt-2 grid grid-cols-3 gap-2" role="group" aria-label="How hard the words are">
    {#each DIFFICULTY_CHOICES as [value, label]}
      <button
        type="button"
        id="difficulty-{value}"
        aria-pressed={difficulty === value}
        disabled={!isHost}
        onclick={() => update({ difficulty: value })}
        class="min-h-11 cursor-pointer rounded-[3px] border-2 px-2 py-2 font-stamp text-xs transition disabled:cursor-default {difficulty === value
          ? 'border-riso-ink bg-riso-yellow'
          : 'border-riso-line bg-white/60 enabled:hover:border-riso-ink'} {!isHost && difficulty !== value ? 'opacity-60' : ''}">
        {label}
      </button>
    {/each}
  </div>
  <div class="mt-3 flex flex-wrap gap-2" role="group" aria-label="Categories">
    {#each allNames as name}
      <button
        type="button"
        data-category={name}
        aria-pressed={chosen.includes(name)}
        disabled={!isHost}
        onclick={() => toggleCategory(name)}
        class="min-h-9 cursor-pointer rounded-full border-2 px-3 py-1 font-stamp text-xs transition disabled:cursor-default {chosen.includes(name)
          ? 'border-riso-ink bg-riso-yellow'
          : 'border-riso-line bg-white/60 enabled:hover:border-riso-ink'} {!isHost && !chosen.includes(name) ? 'opacity-60' : ''}">
        {chosen.includes(name) ? '✓ ' : ''}{name}
      </button>
    {/each}
  </div>
  {#if isHost && room.settings.categories !== 'all'}
    <button type="button" id="categories-all" onclick={() => update({ categories: 'all' })} class="mt-2 cursor-pointer font-stamp text-xs underline">
      Select all
    </button>
  {/if}
</details>
