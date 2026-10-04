<script>
  import { onMount } from 'svelte'

  // A number that counts from `from` up to `to`, starting after `delay` ms.
  export let from = 0
  export let to = 0
  export let delay = 0
  export let duration = 600

  let shown = from

  onMount(() => {
    // for anyone who asked for less motion, or when there is nothing to count
    if (from === to || window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      shown = to
      return
    }

    let frame
    const timer = setTimeout(() => {
      const started = performance.now()
      const step = now => {
        const t = Math.min(1, (now - started) / duration)
        // slows toward the end, so it settles instead of stopping dead
        shown = Math.round(from + (to - from) * (1 - Math.pow(1 - t, 3)))
        if (t < 1) frame = requestAnimationFrame(step)
      }
      frame = requestAnimationFrame(step)
    }, delay)

    return () => {
      clearTimeout(timer)
      cancelAnimationFrame(frame)
    }
  })
</script>

{shown}
