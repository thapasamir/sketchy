<script>
  import { createEventDispatcher, onMount } from 'svelte'
  import InkTrail from '../components/InkTrail.svelte'
  import Wordmark from '../components/Wordmark.svelte'
  import Button from '../components/Button.svelte'
  import { createGuestUser } from '../lib/api.js'

  const dispatch = createEventDispatcher()

  // set when someone opened an invite link like /room/ABCD
  export let inviteCode = ''
  export let notice = '' // e.g. "Your session expired"

  let busy = false
  let error = ''

  // Logo misprint: the two inks slide in opposite directions as the pointer moves
  onMount(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return
    const root = document.documentElement
    function onMove(e) {
      const nx = (e.clientX / window.innerWidth - 0.5) * 2
      const ny = (e.clientY / window.innerHeight - 0.5) * 2
      root.style.setProperty('--mx', (nx * 7).toFixed(1) + 'px')
      root.style.setProperty('--my', (ny * 5).toFixed(1) + 'px')
    }
    window.addEventListener('pointermove', onMove)
    return () => window.removeEventListener('pointermove', onMove)
  })

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

  <div class="flex w-full max-w-sm flex-col gap-3 sm:w-auto sm:max-w-none sm:flex-row sm:gap-5">
    <Button variant="pink" class="sm:min-w-52" disabled={busy} on:click={playAsGuest}>
      {busy ? 'One sec…' : 'Play as Guest'}
    </Button>
    <Button class="sm:min-w-52" on:click={() => dispatch('auth', 'login')}>Log in / Sign up</Button>
  </div>

  {#if error}
    <p class="mt-5 font-stamp text-sm text-riso-stamp" role="alert">{error}</p>
  {/if}
</main>
