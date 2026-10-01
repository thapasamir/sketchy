<script>
  import { onMount } from 'svelte'

  let canvas
  const LIFE = 1300 // ms a scribble stays visible
  let points = []
  let raf = null

  onMount(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return

    const ctx = canvas.getContext('2d')
    let w = 0, h = 0

    function resize() {
      const dpr = window.devicePixelRatio || 1
      w = window.innerWidth
      h = window.innerHeight
      canvas.width = w * dpr
      canvas.height = h * dpr
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    }

    // One pass per ink. The second ink is nudged so the two never line up, like a misprint.
    function strokeLayer(color, dx, dy, now) {
      ctx.strokeStyle = color
      ctx.lineCap = 'round'
      for (let i = 1; i < points.length; i++) {
        const a = points[i - 1], b = points[i]
        const age = (now - b.t) / LIFE
        if (age >= 1 || b.t - a.t > 80) continue // gap in movement = lift the pen
        ctx.globalAlpha = (1 - age) * 0.85
        ctx.lineWidth = 3 + (1 - age) * 7
        ctx.beginPath()
        ctx.moveTo(a.x + dx, a.y + dy)
        ctx.lineTo(b.x + dx, b.y + dy)
        ctx.stroke()
      }
    }

    function frame(now) {
      points = points.filter(p => now - p.t < LIFE)
      ctx.clearRect(0, 0, w, h)
      ctx.globalCompositeOperation = 'multiply'
      strokeLayer('#FF48B0', 3, 2, now)
      strokeLayer('#0078BF', -3, -2, now)
      ctx.globalAlpha = 1
      raf = points.length > 1 ? requestAnimationFrame(frame) : null
      if (!raf) ctx.clearRect(0, 0, w, h)
    }

    function onMove(e) {
      // tiny jitter so a straight drag still looks hand-drawn
      points.push({ x: e.clientX + (Math.random() - 0.5) * 3, y: e.clientY + (Math.random() - 0.5) * 3, t: performance.now() })
      if (!raf) raf = requestAnimationFrame(frame)
    }

    resize()
    window.addEventListener('resize', resize)
    window.addEventListener('pointermove', onMove)
    return () => {
      window.removeEventListener('resize', resize)
      window.removeEventListener('pointermove', onMove)
      if (raf) cancelAnimationFrame(raf)
    }
  })
</script>

<canvas
  bind:this={canvas}
  aria-hidden="true"
  class="pointer-events-none fixed inset-0 z-10 h-screen w-screen mix-blend-multiply"
></canvas>
