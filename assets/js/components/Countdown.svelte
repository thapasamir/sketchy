<script>
  import { urgencyOf, fractionLeft } from '../lib/countdown.js'

  // The clock: a ring that empties, with the seconds in the middle. It changes colour as time runs
  // short (calm, then pink, then red and throbbing), so it can be read from the corner of your eye.
  export let secondsLeft = 0
  export let msLeft = 0
  export let totalMs = 1
  export let phase = 'drawing'
  export let size = 56

  const STROKE = 6
  $: radius = (size - STROKE) / 2
  $: circumference = 2 * Math.PI * radius
  $: urgency = urgencyOf({ phase, secondsLeft, totalMs })
  $: filled = fractionLeft(msLeft, totalMs)

  const COLORS = { calm: 'var(--color-riso-ink)', warn: 'var(--color-riso-pink)', urgent: 'var(--color-riso-stamp)' }
</script>

<div
  data-urgency={urgency}
  class="relative shrink-0 {urgency === 'urgent' ? 'animate-pulse' : ''}"
  style="width:{size}px;height:{size}px">
  <svg width={size} height={size} viewBox="0 0 {size} {size}" class="-rotate-90" aria-hidden="true">
    <circle cx={size / 2} cy={size / 2} r={radius} fill="white" fill-opacity="0.7" stroke="currentColor" stroke-opacity="0.12" stroke-width={STROKE} />
    <circle
      cx={size / 2}
      cy={size / 2}
      r={radius}
      fill="none"
      stroke={COLORS[urgency]}
      stroke-width={STROKE}
      stroke-linecap="round"
      stroke-dasharray={circumference}
      stroke-dashoffset={circumference * (1 - filled)}
      style="transition: stroke-dashoffset 100ms linear, stroke 300ms" />
  </svg>
  <span
    id="turn-timer"
    class="absolute inset-0 grid place-items-center font-display tabular-nums leading-none"
    style="font-size:{size * 0.42}px; color:{COLORS[urgency]}">{secondsLeft}</span>
</div>
