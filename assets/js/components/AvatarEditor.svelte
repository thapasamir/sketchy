<script>
  import { untrack } from 'svelte'
  import Button from './Button.svelte'
  import Marker from './Marker.svelte'
  import { COUNTS, NAMES, cycle, withPart, randomAvatar } from '../lib/avatar.js'

  // Choosing a face: the big preview, and an arrow on each side for eyes, mouth and hat to go
  // through the choices (each is named, and it comes round at the ends), and a shuffle. The body
  // is the player's assigned colour, which is not up to them, with their own wobble (from their
  // `id`) so it is the body everyone else sees. `onchange(face)` is called with every change.
  let { face: start, color = '#ffe800', name = '', id = '', onchange } = $props()

  // The face being edited is kept here, and changes at once. (In a room the new face only comes back
  // from the server a moment later; taps made before then must build on this one, not on the old
  // one, or they would be lost.) While this is open nothing else changes the player's face.
  let face = $state(untrack(() => start))

  const ROWS = [
    ['eyes', 'Eyes'],
    ['mouth', 'Mouth'],
    ['hat', 'Hat'],
  ]

  const change = next => {
    face = next
    onchange(next)
  }
  const step = (part, by) => change(withPart(face, part, cycle(face[part], COUNTS[part], by)))
</script>

<div id="avatar-preview" class="mx-auto grid h-36 w-36 place-items-center rounded-[4px] border-2 border-riso-line bg-white/70">
  <Marker player={{ id, color, name, avatar: face }} size={120} />
</div>

<div class="mt-5 flex flex-col gap-2">
  {#each ROWS as [part, label]}
    <div class="flex items-center gap-2 rounded-[3px] border-2 border-riso-line bg-white/60 p-1.5" role="group" aria-label={label}>
      <button
        type="button"
        id="avatar-{part}-prev"
        aria-label="Previous {label.toLowerCase()}"
        onclick={() => step(part, -1)}
        class="grid h-11 w-11 shrink-0 cursor-pointer place-items-center rounded-[3px] border-2 border-riso-ink bg-white font-display text-xl transition hover:bg-riso-yellow active:scale-95">
        ‹
      </button>
      <div class="min-w-0 flex-1 text-center">
        <div class="font-stamp text-xs uppercase tracking-widest text-riso-muted">{label}</div>
        <div id="avatar-{part}-value" data-index={face[part]} class="font-display text-lg leading-tight">{NAMES[part][face[part]]}</div>
      </div>
      <button
        type="button"
        id="avatar-{part}-next"
        aria-label="Next {label.toLowerCase()}"
        onclick={() => step(part, 1)}
        class="grid h-11 w-11 shrink-0 cursor-pointer place-items-center rounded-[3px] border-2 border-riso-ink bg-white font-display text-xl transition hover:bg-riso-yellow active:scale-95">
        ›
      </button>
    </div>
  {/each}
</div>

<Button id="avatar-shuffle" class="mt-4 w-full px-4 py-2.5 font-stamp text-sm" onclick={() => change(randomAvatar())}>Shuffle</Button>
