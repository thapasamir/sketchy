<script>
  import { onMount, onDestroy, untrack } from 'svelte'
  import { drawStroke, clear } from '../lib/render.js'
  import { timeline, shownAt } from '../lib/replay.js'
  import Marker from './Marker.svelte'

  // The drawing again, from a blank page: every stroke is drawn back in the order it was made,
  // each in its player's colour, with the name of whoever is drawing at the moment. It sits over
  // the picture and paints from a copy taken when it starts, so the real picture is untouched.
  // A tap anywhere ends it early.
  let { store, players, onclose } = $props()

  let base // finished strokes, painted once each
  let live // the stroke being drawn, repainted every frame
  let baseCtx
  let liveCtx
  let width = 0
  let height = 0
  let frame
  let closing
  let drawer = $state(null)

  // (a snapshot, taken once when the replay starts: it must not change under itself as it plays)
  const strokes = untrack(() => store.strokes.filter(s => s.points.length).map(s => ({ ...s, points: [...s.points] })))
  const plan = timeline(strokes)
  const byId = untrack(() => Object.fromEntries(players.map(p => [p.id, p])))

  function resize() {
    const rect = base.getBoundingClientRect()
    if (!rect.width) return
    const dpr = window.devicePixelRatio || 1
    width = rect.width
    height = rect.height
    for (const c of [base, live]) {
      c.width = Math.round(width * dpr)
      c.height = Math.round(height * dpr)
    }
    baseCtx = base.getContext('2d')
    liveCtx = live.getContext('2d')
    baseCtx.setTransform(dpr, 0, 0, dpr, 0, 0)
    liveCtx.setTransform(dpr, 0, 0, dpr, 0, 0)
    // a resize in the middle: paint what has been shown so far again
    painted = 0
    clear(baseCtx, width, height)
  }

  // how many strokes are already on `base`
  let painted = 0
  let start = 0

  function tick(now) {
    if (!start) start = now
    const { done, current, count, finished } = shownAt(plan, now - start)

    // strokes that have just been finished move down to the base layer
    for (; painted < done; painted++) drawStroke(baseCtx, strokes[painted], width, height)

    clear(liveCtx, width, height)
    if (current !== null) {
      drawStroke(liveCtx, { ...strokes[current], points: strokes[current].points.slice(0, count) }, width, height)
      const id = strokes[current].player_id
      if (drawer?.id !== id) drawer = byId[id] ?? null
    }

    if (finished) closing = setTimeout(onclose, 700)
    else frame = requestAnimationFrame(tick)
  }

  onMount(() => {
    resize()
    const observer = new ResizeObserver(resize)
    observer.observe(base)
    frame = requestAnimationFrame(tick)
    return () => observer.disconnect()
  })

  onDestroy(() => {
    cancelAnimationFrame(frame)
    clearTimeout(closing)
  })
</script>

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div id="replay" class="absolute inset-0 z-10 cursor-pointer bg-[#fffdf8]" onclick={onclose}>
  <canvas bind:this={base} class="absolute inset-0 h-full w-full" aria-hidden="true"></canvas>
  <canvas bind:this={live} class="absolute inset-0 h-full w-full" aria-hidden="true"></canvas>

  <div class="absolute inset-x-0 bottom-0 flex items-center justify-between gap-2 bg-riso-ink/85 px-3 py-2 text-riso-paper">
    <span id="replay-who" class="flex min-w-0 items-center gap-2 font-stamp text-sm">
      {#if drawer}
        <Marker player={drawer} size={26} />
        <span class="truncate">{drawer.name}</span>
      {:else}
        Replaying the drawing
      {/if}
    </span>
    <span class="shrink-0 font-stamp text-xs uppercase tracking-wider opacity-80">Tap to skip</span>
  </div>
</div>
