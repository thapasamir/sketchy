<script>
  let className = ''
  export { className as class }
  export let variant = 'outline' // 'pink' | 'blue' | 'yellow' | 'outline'
  export let type = 'button'
  export let disabled = false

  const variants = {
    pink: 'border-riso-pink bg-riso-pink text-riso-paper mix-blend-multiply enabled:hover:shadow-[4px_4px_0_rgb(255_72_176/0.35)]',
    blue: 'border-riso-blue bg-riso-blue text-white enabled:hover:shadow-[4px_4px_0_rgb(0_120_191/0.3)]',
    yellow: 'border-riso-ink bg-riso-yellow text-riso-ink mix-blend-multiply enabled:hover:shadow-[4px_4px_0_rgb(0_0_0/0.15)]',
    outline: 'border-riso-ink bg-transparent text-riso-ink enabled:hover:bg-riso-pink/5 enabled:hover:shadow-[4px_4px_0_rgb(0_0_0/0.1)]',
  }
</script>

<button
  {type}
  {disabled}
  {...$$restProps}
  on:click
  class="cursor-pointer rounded-[3px] border-2 px-6 py-3.5 font-display text-lg transition duration-200 enabled:hover:-translate-x-0.5 enabled:hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-50 {variants[variant]} {className}"
>
  <slot />
</button>
