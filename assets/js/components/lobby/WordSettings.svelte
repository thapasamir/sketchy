<script>
  import Segmented from '../Segmented.svelte'
  import { chosenCategories, tapCategory } from '../../lib/categories.js'

  // The host's choice of words, inside the settings dialog: how hard they may be, and which
  // categories. `update(changes)` sends a change to the server.
  let { room, update } = $props()

  const DIFFICULTY_CHOICES = [
    ['easy', 'Easy only'],
    ['medium', 'Easy + medium'],
    ['all', 'All'],
  ]

  let allNames = $derived(room.words.categories)
  let everything = $derived(room.settings.categories === 'all')
  let chosen = $derived(chosenCategories(room.settings.categories, allNames))

  function pick(name) {
    const next = tapCategory(room.settings.categories, allNames, name)
    if (next !== null) update({ categories: next })
  }
</script>

<section>
  <div class="mb-2 font-stamp text-xs uppercase tracking-widest">How hard are the words</div>
  <Segmented id="difficulty" label="How hard the words are" options={DIFFICULTY_CHOICES} value={room.settings.difficulty} onselect={value => update({ difficulty: value })} />
</section>

<section class="mt-6">
  <div class="mb-1 flex items-center justify-between gap-3">
    <span class="font-stamp text-xs uppercase tracking-widest">Categories</span>
    <span id="words-pool" class="font-stamp text-xs text-riso-muted">
      {everything ? 'All categories' : `${chosen.length} of ${allNames.length}`} · {room.words.pool} words
    </span>
  </div>
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

  <div class="grid grid-cols-2 gap-2" role="group" aria-label="Categories">
    {#each allNames as name}
      {@const on = chosen.includes(name)}
      <button
        type="button"
        data-category={name}
        aria-pressed={on}
        onclick={() => pick(name)}
        class="flex min-h-11 cursor-pointer items-center gap-2 rounded-[3px] border-2 px-3 py-1.5 text-left transition active:scale-[0.97] {everything
          ? 'border-riso-line bg-riso-yellow/25 hover:border-riso-ink'
          : on
            ? 'border-riso-ink bg-riso-yellow'
            : 'border-riso-line bg-white/60 text-riso-muted hover:border-riso-ink'}">
        <span class="min-w-0 flex-1 font-stamp text-xs leading-tight">{name}</span>
        {#if on && !everything}<span aria-hidden="true" class="shrink-0 text-sm">✓</span>{/if}
      </button>
    {/each}
  </div>
</section>
