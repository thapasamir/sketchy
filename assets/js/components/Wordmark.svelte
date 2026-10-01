<script>
  // Two inks printed slightly out of line. --mx/--my (set by the landing page on pointer move)
  // slide the layers in opposite directions.
  let className = ''
  export { className as class }
  export let text = 'SKETCHY'
</script>

<span class="relative inline-block font-display leading-[0.9] tracking-tight {className}" role="img" aria-label={text}>
  <span
    aria-hidden="true"
    class="block text-riso-pink mix-blend-multiply transition-transform duration-150 ease-out"
    style="transform: translate(var(--mx, 0px), var(--my, 0px))">{text}</span>
  <span
    aria-hidden="true"
    class="absolute inset-0 text-riso-blue opacity-90 mix-blend-multiply transition-transform duration-150 ease-out"
    style="transform: translate(calc(4px - var(--mx, 0px)), calc(3px - var(--my, 0px)))">{text}</span>
</span>
