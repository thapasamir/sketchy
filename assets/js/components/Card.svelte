<script>
  let className = ''
  export { className as class }
</script>

<div {...$$restProps} class="rounded-[4px] border-2 border-riso-ink bg-white/60 p-6 shadow-[0_8px_24px_rgb(0_0_0/0.08)] sm:p-8 {className}">
  <slot />
</div>
