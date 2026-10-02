<script>
  import { createEventDispatcher } from 'svelte'
  import Button from '../components/Button.svelte'
  import Card from '../components/Card.svelte'
  import Field from '../components/Field.svelte'
  import { registerUser, loginUser } from '../lib/api.js'

  const dispatch = createEventDispatcher()

  export let mode = 'login' // 'login' | 'register'

  let username = ''
  let email = ''
  let password = ''
  let error = ''
  let busy = false

  function switchMode(next) {
    mode = next
    error = ''
  }

  async function submit() {
    error = ''
    const name = username.trim()

    if (!name) return (error = 'Enter your username')
    if (mode === 'register' && !email.trim()) return (error = 'Enter your email')
    if (!password) return (error = 'Enter your password')

    busy = true
    try {
      const { user_id, username: confirmed, token } =
        mode === 'register'
          ? await registerUser(name, email.trim(), password)
          : await loginUser(name, password)

      dispatch('authed', { userId: user_id, userType: 'registered', username: confirmed, token })
    } catch (e) {
      error = e.message
      busy = false
    }
  }
</script>

<main class="flex min-h-dvh items-center justify-center px-4 py-8">
  <Card class="w-full max-w-lg">
    <form on:submit|preventDefault={submit} novalidate>
      {#if mode === 'register'}
        <h2 class="mb-2 font-display text-2xl">
          <span class="text-riso-pink mix-blend-multiply">Create</span> Account
        </h2>
        <p class="mb-6 text-sm text-riso-muted">Keep your name across games. No email verification needed.</p>

        <div class="sm:grid sm:grid-cols-2 sm:gap-x-4">
          <Field id="reg-username" label="Username" bind:value={username} placeholder="3–20 characters" maxlength="20" autocomplete="username" autofocus />
          <Field id="reg-email" label="Email" type="email" bind:value={email} placeholder="you@email.com" autocomplete="email" />
        </div>
        <Field id="reg-password" label="Password" type="password" bind:value={password} placeholder="6+ characters" autocomplete="new-password" />
      {:else}
        <h2 class="mb-2 font-display text-2xl">
          <span class="text-riso-blue mix-blend-multiply">Welcome</span> Back
        </h2>
        <p class="mb-6 text-sm text-riso-muted">Log in to play under your own name.</p>

        <Field id="login-username" label="Username" bind:value={username} placeholder="Your username" autocomplete="username" autofocus />
        <Field id="login-password" label="Password" type="password" bind:value={password} placeholder="Your password" autocomplete="current-password" />
      {/if}

      {#if error}
        <p class="mb-4 font-stamp text-sm text-riso-stamp" role="alert">{error}</p>
      {/if}

      <div class="mt-2 flex gap-3">
        <Button type="submit" variant="blue" class="min-w-0 flex-1" disabled={busy}>
          {#if busy}Working…{:else if mode === 'register'}Create Account{:else}Log In{/if}
        </Button>
        <Button class="min-w-0 flex-1" on:click={() => dispatch('back')}>Back</Button>
      </div>

      <button
        type="button"
        on:click={() => switchMode(mode === 'register' ? 'login' : 'register')}
        class="mt-6 block text-sm text-riso-blue underline hover:no-underline">
        {mode === 'register' ? 'Already have an account? Log in' : "New here? Create an account"}
      </button>
    </form>
  </Card>
</main>
