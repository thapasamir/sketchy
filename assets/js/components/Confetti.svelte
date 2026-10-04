<script>
  import { onMount } from 'svelte'

  // A burst of paper confetti in the game's inks, for a winner. It runs for a few seconds and
  // then removes itself; it never blocks clicks.
  export let count = 140
  const COLORS = ['#FF48B0', '#0078BF', '#FFE800', '#263A6E', '#C8102E']
  const SECONDS = 3.6

  let canvas

  onMount(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return

    const ctx = canvas.getContext('2d')
    const dpr = window.devicePixelRatio || 1
    const w = (canvas.width = window.innerWidth * dpr)
    const h = (canvas.height = window.innerHeight * dpr)

    // two cannons, one in each bottom corner, firing up and a little toward the middle
    const pieces = Array.from({ length: count }, (_, i) => {
      const direction = i % 2 === 0 ? 1 : -1 // +1: fired from the left, -1: from the right
      const lean = 0.1 + Math.random() * 0.8 // radians away from straight up
      const speed = (11 + Math.random() * 9) * dpr
      return {
        x: direction === 1 ? w * 0.06 : w * 0.94,
        y: h * 0.85,
        vx: Math.sin(lean) * speed * direction,
        vy: -Math.cos(lean) * speed,
        size: (6 + Math.random() * 7) * dpr,
        spin: Math.random() * Math.PI,
        spinSpeed: (Math.random() - 0.5) * 0.4,
        color: COLORS[Math.floor(Math.random() * COLORS.length)],
        flip: Math.random() * Math.PI,
      }
    })

    let frame
    const started = performance.now()
    const tick = now => {
      const age = (now - started) / 1000
      ctx.clearRect(0, 0, w, h)
      for (const p of pieces) {
        p.vy += 0.32 * dpr // gravity
        p.vx *= 0.992 // air
        p.x += p.vx
        p.y += p.vy
        p.spin += p.spinSpeed
        p.flip += 0.18
        ctx.save()
        ctx.globalAlpha = Math.min(1, Math.max(0, (SECONDS - age) / 0.8))
        ctx.translate(p.x, p.y)
        ctx.rotate(p.spin)
        // squashing the height as it tumbles reads as a flat piece of paper turning over
        ctx.scale(1, Math.cos(p.flip))
        ctx.fillStyle = p.color
        ctx.fillRect(-p.size / 2, -p.size / 4, p.size, p.size / 2)
        ctx.restore()
      }
      if (age < SECONDS) frame = requestAnimationFrame(tick)
      else ctx.clearRect(0, 0, w, h)
    }
    frame = requestAnimationFrame(tick)

    return () => cancelAnimationFrame(frame)
  })
</script>

<canvas
  bind:this={canvas}
  id="confetti"
  aria-hidden="true"
  class="pointer-events-none fixed inset-0 z-40 h-full w-full"></canvas>
