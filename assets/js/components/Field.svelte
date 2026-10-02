<script>
  import { focus } from '../lib/focus.js'

  export let id
  export let label
  export let value = ''
  export let type = 'text'
  export let placeholder = ''
  export let maxlength = undefined
  export let autocomplete = undefined
  export let autofocus = false
  export let inputClass = ''
  let className = 'mb-5'
  export { className as class }
</script>

<div class={className}>
  <label for={id} class="mb-2 block font-stamp text-sm uppercase tracking-widest">{label}</label>
  <input
    {id}
    {type}
    {placeholder}
    {maxlength}
    {autocomplete}
    bind:value
    use:focus={autofocus}
    on:input
    class="w-full rounded-[3px] border-2 border-riso-ink bg-white px-3.5 py-3 font-type text-base placeholder:text-riso-line focus:outline-2 focus:outline-offset-2 focus:outline-riso-blue {inputClass}" />
</div>
