<script>
  import { onMount } from 'svelte'

  // A dialog over the page: a title and close button that stay put, a body that scrolls, and an
  // optional footer that is always in reach. Escape and a tap outside close it, Tab stays inside it,
  // and focus goes back to where it was when it closes. On a phone it slides up from the bottom.
  let { title, id = 'dialog', onclose, children, footer } = $props()

  let dialog
  let closeButton

  onMount(() => {
    const opener = document.activeElement
    document.body.style.overflow = 'hidden'
    closeButton?.focus()
    return () => {
      document.body.style.overflow = ''
      opener?.focus?.()
    }
  })

  function onKey(event) {
    if (event.key === 'Escape') {
      event.stopPropagation()
      onclose()
    } else if (event.key === 'Tab') {
      const items = [...dialog.querySelectorAll('button, [href], input, summary, [tabindex]:not([tabindex="-1"])')].filter(el => !el.disabled)
      if (!items.length) return
      const first = items[0]
      const last = items[items.length - 1]
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault()
        last.focus()
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault()
        first.focus()
      }
    }
  }
</script>

<svelte:window onkeydown={onKey} />

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div
  class="animate-fade fixed inset-0 z-50 flex items-end justify-center bg-riso-ink/45 backdrop-blur-[2px] sm:items-center sm:p-6"
  onclick={e => e.target === e.currentTarget && onclose()}>
  <div
    bind:this={dialog}
    {id}
    role="dialog"
    aria-modal="true"
    aria-labelledby="{id}-title"
    class="animate-rise flex max-h-[92dvh] w-full max-w-xl flex-col overflow-hidden rounded-t-[6px] border-2 border-riso-ink bg-riso-paper shadow-[0_20px_60px_rgb(0_0_0/0.3)] sm:rounded-[4px]">
    <div class="flex shrink-0 items-center justify-between gap-4 border-b-2 border-riso-ink/10 px-5 py-4 sm:px-7">
      <h2 id="{id}-title" class="font-display text-2xl sm:text-3xl">{title}</h2>
      <button
        bind:this={closeButton}
        type="button"
        aria-label="Close"
        onclick={onclose}
        class="grid h-11 w-11 shrink-0 cursor-pointer place-items-center rounded-[3px] border-2 border-riso-ink font-display text-xl transition hover:bg-riso-pink/10">
        ×
      </button>
    </div>

    <div class="min-h-0 flex-1 overflow-y-auto px-5 py-5 sm:px-7">
      {@render children()}
    </div>

    {#if footer}
      <div class="shrink-0 border-t-2 border-riso-ink/10 p-4 sm:px-7">
        {@render footer()}
      </div>
    {/if}
  </div>
</div>
