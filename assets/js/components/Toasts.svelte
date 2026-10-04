<script>
  // short messages that fade by themselves: [{ id, text, kind: 'good' | 'warn' | 'info' }]
  export let notices = []

  const tone = {
    good: 'border-riso-blue',
    warn: 'border-riso-stamp',
    info: 'border-riso-ink',
  }
</script>

<!-- At the top, above everything, and never in the way of a tap. A screen reader reads each one out. -->
<div
  id="notices"
  role="status"
  aria-live="polite"
  class="pointer-events-none fixed left-1/2 top-3 z-50 flex w-[min(92vw,26rem)] -translate-x-1/2 flex-col gap-2">
  {#each notices as notice (notice.id)}
    <div
      data-notice={notice.kind}
      class="animate-rise rounded-[3px] border-2 bg-white px-4 py-2.5 text-center font-stamp text-sm shadow-[3px_3px_0_rgb(0_0_0/0.12)] {tone[notice.kind] ?? tone.info}">
      {notice.text}
    </div>
  {/each}
</div>
