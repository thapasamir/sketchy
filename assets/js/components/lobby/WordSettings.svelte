<script>
  // Which words come up: how hard they may be, and which categories. Everyone sees the choice;
  // only the host can change it. `update(changes)` sends a change to the server.
  let { room, isHost, update } = $props()

  const DIFFICULTY_CHOICES = [
    ['easy', 'Easy only'],
    ['medium', 'Easy + medium'],
    ['all', 'All'],
  ]

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
  <!-- looks like what it is: something you open -->
  <summary
    class="flex min-h-12 cursor-pointer list-none items-center justify-between gap-3 rounded-[3px] border-2 border-riso-line bg-white/60 px-3 py-2 transition hover:border-riso-ink group-open:border-riso-ink [&::-webkit-details-marker]:hidden">
    <span class="min-w-0">
      <span class="block font-stamp text-xs uppercase tracking-widest">Words</span>
      <span id="words-summary" class="block font-stamp text-xs text-riso-muted">
        {room.settings.categories === 'all' ? 'All categories' : `${chosen.length} of ${allNames.length} categories`} · {room.words.pool} words
      </span>
    </span>
    <span aria-hidden="true" class="shrink-0 font-stamp text-sm transition group-open:rotate-180">▾</span>
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
