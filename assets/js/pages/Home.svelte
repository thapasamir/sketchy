<script>
  import { createEventDispatcher, onMount } from 'svelte'
  import InkTrail from '../components/InkTrail.svelte'
  import Wordmark from '../components/Wordmark.svelte'
  import Button from '../components/Button.svelte'
  import HomeScene from '../components/HomeScene.svelte'
  import { createGuestUser } from '../lib/api.js'
  import { FAQ } from '../lib/faq.js'
  import { trackMisprint } from '../lib/misprint.js'

  const dispatch = createEventDispatcher()

  // set when someone opened an invite link like /room/ABCD
  export let inviteCode = ''
  export let notice = '' // e.g. "Your session expired"

  let busy = false
  let error = ''

  onMount(trackMisprint)

  async function playAsGuest() {
    error = ''
    busy = true
    try {
      const { user_id, token } = await createGuestUser()
      dispatch('authed', { userId: user_id, userType: 'guest', token })
    } catch (e) {
      error = e.message
      busy = false
    }
  }
</script>

<InkTrail />
<main class="flex min-h-dvh flex-col items-center justify-center px-4 py-10">
  <div class="mb-10 text-center">
    <h1 class="sr-only">Sketchy: the free imposter drawing game</h1>
    <Wordmark class="text-[clamp(3rem,13vw,7.5rem)]" />
    <p class="mx-auto mt-5 max-w-sm text-balance text-lg text-riso-muted">
      Draw things. Catch the imposter. Win together.
    </p>
  </div>

  {#if notice}
    <p class="mb-6 max-w-sm text-center font-stamp text-sm text-riso-stamp" role="status">{notice}</p>
  {/if}

  {#if inviteCode}
    <p class="mb-6 max-w-sm border-2 border-dashed border-riso-ink bg-riso-yellow/40 px-4 py-3 text-center font-stamp text-sm">
      You're invited to room <strong class="tracking-widest">{inviteCode}</strong>.
      Jump in as a guest, or sign in first.
    </p>
  {/if}

  <div class="mb-8"><HomeScene /></div>

  <div class="flex w-full max-w-sm flex-col gap-3 sm:w-auto sm:max-w-none sm:flex-row sm:gap-5">
    <Button variant="pink" class="sm:min-w-52" disabled={busy} on:click={playAsGuest}>
      {busy ? 'One sec…' : 'Play as Guest'}
    </Button>
    <Button class="sm:min-w-52" on:click={() => dispatch('auth', 'login')}>Log in / Sign up</Button>
  </div>

  <p class="mt-4 font-stamp text-xs uppercase tracking-widest text-riso-muted">Free · 3 to 8 players · phones welcome</p>

  {#if error}
    <p class="mt-5 font-stamp text-sm text-riso-stamp" role="alert">{error}</p>
  {/if}

  <button
    type="button"
    id="home-how-to-play"
    class="mt-8 cursor-pointer font-stamp text-sm text-riso-muted underline decoration-riso-line underline-offset-4 transition hover:text-riso-ink hover:decoration-riso-ink"
    on:click={() => dispatch('help')}>
    New here? How to play
  </button>
</main>

<!-- what the game is, in words: for people deciding whether to try it, and for search engines -->
<section id="home-about" class="mx-auto w-full max-w-2xl px-4 pb-16 pt-4">
  <h2 class="font-display text-2xl">A drawing game where one of you is lying</h2>
  <p class="mt-3 text-riso-muted">
    Sketchy is a free multiplayer drawing game for three to eight friends. Everyone draws one shared picture of
    a secret word, except the imposter, who doesn't know it. Play in the browser on a phone or computer, with
    nothing to download.
  </p>

  <div class="mt-8 divide-y-2 divide-riso-ink/10 border-y-2 border-riso-ink/10">
    {#each FAQ as [question, answer]}
      <details class="group py-3">
        <summary class="flex cursor-pointer list-none items-center justify-between gap-3 font-display text-base [&::-webkit-details-marker]:hidden">
          <h3 class="min-w-0">{question}</h3>
          <span aria-hidden="true" class="shrink-0 font-stamp text-lg transition group-open:rotate-45">+</span>
        </summary>
        <p class="mt-2 text-sm text-riso-muted">{answer}</p>
      </details>
    {/each}
  </div>
</section>
