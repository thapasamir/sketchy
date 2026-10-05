<script>
  import Segmented from '../Segmented.svelte'
  import { chosenCategories, tapCategory } from '../../lib/categories.js'

  // The host's choice of words, inside the settings dialog: how hard they may be, and which
  // categories. The long list of categories is folded away behind a one-line summary.
  // `update(changes)` sends a change to the server.
  let { room, update } = $props()

  const DIFFICULTY_CHOICES = [
    ['easy', 'Easy only'],
    ['medium', 'Easy + medium'],
    ['all', 'All'],
  ]
  const DIFFICULTY_HINT = {
    easy: 'Simple things that are quick to draw.',
    medium: 'A mix of simple and trickier words.',
    all: 'Anything, including words that are hard to draw.',
  }
  const heading = 'font-stamp text-xs uppercase tracking-widest'

  let allNames = $derived(room.words.categories)
  let everything = $derived(room.settings.categories === 'all')
  let chosen = $derived(chosenCategories(room.settings.categories, allNames))

  // a short line for the folded list: "All 16 categories", or which ones
  let summary = $derived(
    everything
      ? `All ${allNames.length} categories`
      : chosen.length <= 2
        ? chosen.join(' and ')
        : `${chosen.length} of ${allNames.length} categories`
  )

  function pick(name) {
    const next = tapCategory(room.settings.categories, allNames, name)
    if (next !== null) update({ categories: next })
  }
</script>

<section>
  <h3 class="{heading} mb-0.5">How hard are the words</h3>
  <p class="mb-2 font-stamp text-xs text-riso-muted">{DIFFICULTY_HINT[room.settings.difficulty]}</p>
  <Segmented id="difficulty" label="How hard the words are" options={DIFFICULTY_CHOICES} value={room.settings.difficulty} onselect={value => update({ difficulty: value })} />
</section>

<details id="categories-section" class="group mt-6">
  <summary
    class="flex min-h-14 cursor-pointer list-none items-center justify-between gap-3 rounded-[3px] border-2 border-riso-line bg-white/60 px-3 py-2 transition hover:border-riso-ink group-open:border-riso-ink [&::-webkit-details-marker]:hidden">
    <span class="min-w-0">
      <span class="block {heading}">Categories</span>
      <!-- (how many words that leaves is kept in data-pool, for tests; it isn't something to show) -->
      <span id="words-pool" data-pool={room.words.pool} class="block truncate font-stamp text-xs text-riso-muted">{summary}</span>
    </span>
    <span class="shrink-0 font-stamp text-xs underline group-open:hidden">Choose</span>
    <span aria-hidden="true" class="hidden shrink-0 font-stamp text-sm group-open:inline">▴</span>
  </summary>

  <div class="mt-3">
    <div class="mb-2 flex items-center justify-between gap-3">
      <p id="categories-hint" class="font-stamp text-xs text-riso-muted">
        {everything ? 'Tap one to play only that, then tap more to add.' : 'Tap to add or remove a category.'}
      </p>
      {#if !everything}
        <button type="button" id="categories-all" onclick={() => update({ categories: 'all' })} class="shrink-0 cursor-pointer font-stamp text-xs underline">
          Select all
        </button>
      {/if}
    </div>

    <div class="grid grid-cols-2 gap-1.5" role="group" aria-label="Categories">
      {#each allNames as name}
        {@const on = chosen.includes(name)}
        <button
          type="button"
          data-category={name}
          aria-pressed={on}
          onclick={() => pick(name)}
          class="flex min-h-11 cursor-pointer items-center gap-2 rounded-[3px] border-2 px-3 py-1.5 text-left transition active:scale-[0.97] {everything
            ? 'border-transparent bg-riso-yellow/30 hover:bg-riso-yellow/50'
            : on
              ? 'border-riso-ink bg-riso-yellow shadow-[2px_2px_0_rgb(0_0_0/0.18)]'
              : 'border-transparent bg-riso-ink/[0.06] text-riso-muted hover:bg-riso-ink/[0.12]'}">
          <span class="min-w-0 flex-1 font-stamp text-xs leading-tight">{name}</span>
          {#if on && !everything}<span aria-hidden="true" class="shrink-0 text-sm">✓</span>{/if}
        </button>
      {/each}
    </div>
  </div>
</details>
