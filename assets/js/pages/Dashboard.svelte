<script>
  import { createEventDispatcher } from 'svelte'
  import Button from '../components/Button.svelte'
  import Card from '../components/Card.svelte'
  import Field from '../components/Field.svelte'
  import AvatarPicker from '../components/AvatarPicker.svelte'
  import { createRoom, joinRoom } from '../lib/api.js'
  import { loadAvatar, saveAvatar } from '../lib/avatar.js'

  const dispatch = createEventDispatcher()

  export let user
  export let inviteCode = '' // from an invite link, so Join comes first
  export let notice = '' // e.g. "That room has closed"

  const registered = user.userType === 'registered'

  // Registered players play under their username. Guests type a name once and we remember it.
  let name = registered ? user.username : user.name || ''
  let code = inviteCode
  let error = notice
  let busy = ''

  // the face this browser last chose, sent along when joining or making a room
  let avatar = loadAvatar()
  const changeAvatar = face => {
    avatar = face
    saveAvatar(face)
  }

  $: code = code.toUpperCase().replace(/[^A-Z]/g, '')

  function checkName() {
    if (name.trim()) return true
    error = 'Pick a name for this game'
    return false
  }

  async function enter(kind) {
    error = ''
    if (!checkName()) return
    if (kind === 'join' && code.length !== 4) return (error = 'Room codes are 4 letters')

    busy = kind
    try {
      const result =
        kind === 'join' ? await joinRoom(code, name.trim(), avatar) : await createRoom(name.trim(), avatar)

      dispatch('enter', { code: result.code, playerId: result.player_id, name: name.trim() })
    } catch (e) {
      error = e.message
      busy = ''
    }
  }

  // Enter key: a typed code means join, otherwise create
  const submit = () => enter(code.length === 4 || inviteCode ? 'join' : 'create')
</script>

<main class="flex min-h-dvh items-center justify-center px-4 py-8">
  <Card class="w-full max-w-lg">
    <form on:submit|preventDefault={submit} novalidate>
      <div class="mb-2 flex items-start justify-between gap-4">
        <h2 class="font-display text-2xl">
          {#if registered}
            <span class="text-riso-pink mix-blend-multiply">Hi,</span> {user.username}
          {:else}
            <span class="text-riso-pink mix-blend-multiply">Let's</span> Play
          {/if}
        </h2>
        {#if registered}
          <button type="button" on:click={() => dispatch('logout')} class="shrink-0 text-sm text-riso-muted underline hover:text-riso-ink">
            Log out
          </button>
        {:else}
          <button type="button" on:click={() => dispatch('auth', 'login')} class="shrink-0 text-sm text-riso-muted underline hover:text-riso-ink">
            Log in
          </button>
        {/if}
      </div>

      <p class="mb-6 text-sm text-riso-muted">
        {#if inviteCode}
          You're invited to room <strong class="tracking-widest text-riso-ink">{inviteCode}</strong>.
        {:else}
          Everyone draws, someone is the imposter.
        {/if}
      </p>

      <div class="mb-5"><AvatarPicker face={avatar} onchange={changeAvatar} /></div>

      {#if !registered}
        <Field id="name" label="Your name" bind:value={name} placeholder="What should we call you?" maxlength="20" autocomplete="nickname" autofocus />
      {/if}

      <div class="flex flex-col">
        <div class={inviteCode ? 'order-3' : 'order-1'}>
          <Button
            variant={inviteCode ? 'outline' : 'blue'}
            class="w-full"
            disabled={!!busy}
            on:click={() => enter('create')}>
            {busy === 'create' ? 'Creating…' : 'Create Room'}
          </Button>
        </div>

        <div class="order-2 my-6 flex items-center gap-3 font-stamp text-xs uppercase tracking-widest text-riso-muted">
          <span class="h-px flex-1 bg-riso-line"></span>
          {inviteCode ? 'or start your own' : 'or join a friend'}
          <span class="h-px flex-1 bg-riso-line"></span>
        </div>

        <div class={inviteCode ? 'order-1' : 'order-3'}>
          <label for="code" class="mb-2 block font-stamp text-sm uppercase tracking-widest">Room code</label>
          <div class="flex gap-3">
            <input
              id="code"
              type="text"
              bind:value={code}
              placeholder="ABCD"
              maxlength="4"
              autocomplete="off"
              autocapitalize="characters"
              class="w-full min-w-0 flex-1 rounded-[3px] border-2 border-riso-ink bg-white py-3 pl-[0.4em] text-center font-stamp text-xl tracking-[0.4em] placeholder:text-riso-line focus:outline-2 focus:outline-offset-2 focus:outline-riso-blue" />
            <Button variant={inviteCode ? 'blue' : 'outline'} class="shrink-0" disabled={!!busy} on:click={() => enter('join')}>
              {busy === 'join' ? 'Joining…' : 'Join'}
            </Button>
          </div>
        </div>
      </div>

      {#if error}
        <p class="mt-5 font-stamp text-sm text-riso-stamp" role="alert">{error}</p>
      {/if}

      <button type="submit" class="hidden" tabindex="-1" aria-hidden="true">Go</button>
    </form>

    {#if !registered}
      <p class="mt-6 border-t border-riso-line pt-5 text-sm text-riso-muted">
        Want to keep your name across games?
        <button type="button" on:click={() => dispatch('auth', 'register')} class="text-riso-blue underline hover:no-underline">
          Create an account
        </button>
      </p>
    {/if}
  </Card>
</main>
