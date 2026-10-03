<script>
  import { onMount, onDestroy } from 'svelte'
  import { drawStroke, clear } from '../lib/render.js'

  // `store` holds the picture. Only the player whose turn it is (`canDraw`) can add to it.
  export let store
  export let canDraw = false
  export let me = ''
  export let color = '#263A6E'
  export let size = 2
  // called with each drawing event so it can be sent to the server
  export let send = () => {}

  // 40ms between batches: smooth enough for others to watch live, few enough messages
  const FLUSH_MS = 40
  const MAX_BATCH = 80
  // ignore pointer moves smaller than this fraction of the canvas: they add bytes, not detail
  const MIN_STEP = 0.0015

  let wrap
  // Two layers. Finished strokes are painted once on `canvas`. The stroke being drawn lives on
  // `live`, a transparent layer on top that is cleared and repainted whole as points arrive, so
  // it is always a single smooth path; when the stroke ends it moves down to `canvas`.
  let canvas
  let live
  let ctx
  let liveCtx
  let width = 0
  let height = 0
  let pen = null // the stroke being drawn right now: { id, pointerId, last, buffer, timer }
  let unsubscribe

  // Same rounding as the server (4 decimals). Without it the drawer's own screen would hold
  // slightly different points than everyone else's, and the line would look a hair different.
  const unit = n => Math.round(Math.min(1, Math.max(0, n)) * 10000) / 10000

  function resize() {
    // measure the canvas itself, not the frame around it: the frame's border isn't drawing area,
    // and a backing store of a different size than what's shown gets resampled (blurry lines)
    const rect = canvas.getBoundingClientRect()
    if (!rect.width) return
    const dpr = window.devicePixelRatio || 1
    width = rect.width
    height = rect.height
    canvas.width = Math.round(width * dpr)
    canvas.height = Math.round(height * dpr)
    live.width = canvas.width
    live.height = canvas.height
    ctx = canvas.getContext('2d')
    liveCtx = live.getContext('2d')
    // from here on we draw in CSS pixels, and the browser maps them to real (sharper) pixels
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    liveCtx.setTransform(dpr, 0, 0, dpr, 0, 0)
    repaint()
  }

  function repaint() {
    clear(ctx, width, height)
    clear(liveCtx, width, height)
    for (const stroke of store.strokes) drawStroke(stroke.done ? ctx : liveCtx, stroke, width, height)
  }

  onMount(() => {
    resize()
    const observer = new ResizeObserver(resize)
    observer.observe(canvas)

    unsubscribe = store.subscribe(change => {
      if (!ctx) return
      if (change.type === 'reset') {
        repaint()
      } else if (change.type === 'end') {
        drawStroke(ctx, change.stroke, width, height)
        clear(liveCtx, width, height)
      } else {
        // 'start' and 'points': the stroke in progress, repainted from its first point
        clear(liveCtx, width, height)
        drawStroke(liveCtx, change.stroke, width, height)
      }
    })

    return () => observer.disconnect()
  })

  onDestroy(() => {
    unsubscribe?.()
    if (pen) clearInterval(pen.timer)
  })

  function pointOf(event) {
    const rect = canvas.getBoundingClientRect()
    return [unit((event.clientX - rect.left) / rect.width), unit((event.clientY - rect.top) / rect.height)]
  }

  const newId = () => `${me.slice(0, 4)}${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`

  function flush() {
    while (pen && pen.buffer.length) send({ type: 'points', id: pen.id, points: pen.buffer.splice(0, MAX_BATCH) })
  }

  function begin(event) {
    if (!canDraw || pen || event.button > 0) return
    event.preventDefault()
    canvas.setPointerCapture(event.pointerId)

    const point = pointOf(event)
    pen = { id: newId(), pointerId: event.pointerId, last: point, buffer: [], timer: setInterval(flush, FLUSH_MS) }

    // draw it here at once, and tell the server; the server shows it to everyone else
    store.apply({ type: 'start', id: pen.id, player_id: me, color, size, points: [point] })
    send({ type: 'start', id: pen.id, size, x: point[0], y: point[1] })
  }

  function move(event) {
    if (!pen || event.pointerId !== pen.pointerId) return
    // a fast hand moves several pixels between events; the browser keeps the ones in between
    const samples = event.getCoalescedEvents?.() ?? []
    for (const sample of samples.length ? samples : [event]) {
      const point = pointOf(sample)
      if (Math.hypot(point[0] - pen.last[0], point[1] - pen.last[1]) < MIN_STEP) continue
      pen.last = point
      pen.buffer.push(point)
      store.apply({ type: 'points', id: pen.id, points: [point] })
    }
  }

  function finish() {
    if (!pen) return
    flush()
    clearInterval(pen.timer)
    store.apply({ type: 'end', id: pen.id })
    send({ type: 'end', id: pen.id })
    pen = null
  }

  function end(event) {
    if (pen && event.pointerId === pen.pointerId) finish()
  }

  // the turn ran out with the pen still down: close the stroke instead of leaving it open
  $: if (!canDraw && pen) finish()
</script>

<div
  bind:this={wrap}
  class="relative aspect-[4/3] w-full overflow-hidden rounded-[3px] border-2 bg-[#fffdf8] transition-shadow duration-300 {canDraw
    ? 'border-riso-ink shadow-[0_0_0_4px_rgb(255_232_0/0.9),6px_6px_0_rgb(0_0_0/0.15)]'
    : 'border-riso-ink/70'}">
  <canvas
    bind:this={canvas}
    id="board"
    aria-label="Shared drawing"
    data-can-draw={canDraw}
    class="absolute inset-0 h-full w-full {canDraw ? 'cursor-crosshair' : ''}"
    style="touch-action: {canDraw ? 'none' : 'auto'}"
    on:pointerdown={begin}
    on:pointermove={move}
    on:pointerup={end}
    on:pointercancel={end}
    on:lostpointercapture={end}></canvas>
  <canvas bind:this={live} id="board-live" aria-hidden="true" class="pointer-events-none absolute inset-0 h-full w-full"></canvas>
</div>
