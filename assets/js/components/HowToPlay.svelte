<script>
  import { createEventDispatcher, onMount, onDestroy } from 'svelte'
  import Button from './Button.svelte'

  const dispatch = createEventDispatcher()

  const steps = [
    {
      title: 'Get your secret',
      text: "Everyone is told the same secret word, except one player: the imposter. They only get the category and a small hint.",
      color: 'bg-riso-pink text-riso-paper',
    },
    {
      title: 'Draw it together',
      text: 'Take turns adding to one shared drawing, once or twice around the table. Show that you know the word, but not so clearly that the imposter can copy you.',
      color: 'bg-riso-blue text-white',
    },
    {
      title: 'Vote',
      text: 'When the drawing is done, everyone votes for who they think the imposter is. Chat opens for the vote, so argue your case. It is closed while people draw.',
      color: 'bg-riso-yellow text-riso-ink',
    },
    {
      title: 'One last guess',
      text: 'If the imposter is caught, they get one chance to guess the word and steal a point.',
      color: 'bg-riso-pink text-riso-paper',
    },
    {
      title: 'Score',
      text: 'Catch the imposter: +1 for each of the crew. Get away with it: +2 for the imposter. Guess the word after being caught: +1.',
      color: 'bg-riso-blue text-white',
    },
  ]

  let dialog
  let closeButton
  let opener

  onMount(() => {
    // remember where focus was, so closing puts it back (keyboard and screen reader users)
    opener = document.activeElement
    document.body.style.overflow = 'hidden'
    closeButton?.focus()
  })

  onDestroy(() => {
    document.body.style.overflow = ''
    opener?.focus?.()
  })

  const close = () => dispatch('close')

  function onKey(event) {
    if (event.key === 'Escape') {
      event.stopPropagation()
      close()
    } else if (event.key === 'Tab') {
      // keep Tab inside the dialog
      const items = [...dialog.querySelectorAll('button, [href], input, [tabindex]:not([tabindex="-1"])')].filter(el => !el.disabled)
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

<svelte:window on:keydown={onKey} />

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div
  class="fixed inset-0 z-50 flex items-end justify-center bg-riso-ink/45 p-0 backdrop-blur-[2px] animate-fade sm:items-center sm:p-6"
  on:click|self={close}>
  <div
    bind:this={dialog}
    id="how-to-play"
    role="dialog"
    aria-modal="true"
    aria-labelledby="how-to-play-title"
    class="flex max-h-[92dvh] w-full max-w-xl flex-col overflow-hidden rounded-t-[6px] border-2 border-riso-ink bg-riso-paper shadow-[0_20px_60px_rgb(0_0_0/0.3)] animate-rise sm:rounded-[4px]">
    <!-- the title and close button stay put; only the steps scroll; "Got it" is always in reach -->
    <div class="flex shrink-0 items-start justify-between gap-4 border-b-2 border-riso-ink/10 p-5 pb-4 sm:px-8 sm:pt-7">
      <div>
        <h2 id="how-to-play-title" class="font-display text-3xl sm:text-4xl">How to play</h2>
        <p class="mt-1 font-stamp text-sm text-riso-muted">3 to 8 players. One word. One imposter.</p>
      </div>
      <button
        bind:this={closeButton}
        type="button"
        aria-label="Close"
        on:click={close}
        class="grid h-11 w-11 shrink-0 cursor-pointer place-items-center rounded-[3px] border-2 border-riso-ink font-display text-xl transition hover:bg-riso-pink/10">
        ×
      </button>
    </div>

    <div id="how-to-play-body" class="min-h-0 flex-1 overflow-y-auto p-5 sm:px-8">
    <ol class="flex flex-col gap-4">
      {#each steps as step, i}
        <li class="flex gap-4">
          <span class="grid h-10 w-10 shrink-0 place-items-center rounded-full border-2 border-riso-ink font-display text-lg {step.color}">
            {i + 1}
          </span>
          <div class="min-w-0">
            <h3 class="font-display text-lg">{step.title}</h3>
            <p class="text-sm text-riso-muted">{step.text}</p>
          </div>
        </li>
      {/each}
    </ol>

    <div class="mt-6 grid gap-3 sm:grid-cols-2">
      <div class="border-2 border-dashed border-riso-blue bg-riso-blue/5 p-3">
        <div class="font-stamp text-sm text-riso-blue">If you know the word</div>
        <p class="mt-1 text-sm">Draw one part of it, not the whole thing. Be clear to your friends, vague to the imposter.</p>
      </div>
      <div class="border-2 border-dashed border-riso-pink bg-riso-pink/5 p-3">
        <div class="font-stamp text-sm text-riso-pink-ink">If you're the imposter</div>
        <p class="mt-1 text-sm">Watch the first drawer, then blend in. Your hint and the category are real clues.</p>
      </div>
    </div>

    </div>

    <div class="shrink-0 border-t-2 border-riso-ink/10 p-4 sm:px-8 sm:pb-6">
      <Button id="how-to-play-done" variant="yellow" class="w-full py-3.5 text-lg" on:click={close}>Got it</Button>
    </div>
  </div>
</div>
