<script>
  import { onMount } from 'svelte'
  import Home from './pages/Home.svelte'
  import Auth from './pages/Auth.svelte'
  import Dashboard from './pages/Dashboard.svelte'
  import Lobby from './pages/Lobby.svelte'
  import Controls from './components/Controls.svelte'
  import HowToPlay from './components/HowToPlay.svelte'
  import { unlock } from './lib/sound.js'
  import { hasSeenHowToPlay, markHowToPlaySeen } from './lib/prefs.js'
  import { loadUser, saveUser, clearUser, loadSeat, saveSeat, clearSeat } from './lib/session.js'
  import { getMe } from './lib/api.js'

  let user = loadUser()
  let seat = loadSeat()
  let inviteCode = ''
  let notice = ''
  let authMode = 'register'

  // the rules: opened from the "?" button, the home page, or automatically the first time someone
  // sits down in a room
  let showHelp = false
  function closeHelp() {
    showHelp = false
    markHowToPlaySeen()
  }

  // /room/ABCD is a shareable invite link
  const match = location.pathname.match(/^\/room\/([A-Za-z]{4})\/?$/)
  const pathCode = match ? match[1].toUpperCase() : ''

  // 'home' (new visitor) | 'auth' | 'dashboard' (signed in) | 'lobby'
  let view
  if (seat && (!pathCode || pathCode === seat.code)) {
    view = 'lobby'
  } else {
    seat = null
    inviteCode = pathCode
    view = user ? 'dashboard' : 'home'
  }

  $: document.title = view === 'lobby' ? `Room ${seat.code} · Sketchy` : 'Sketchy'

  onMount(() => {
    // Browsers keep sound off until the person has interacted with the page. Any first click or
    // key press switches it on, so it's ready by the time the game wants to play something.
    const ready = () => {
      unlock()
      window.removeEventListener('pointerdown', ready)
      window.removeEventListener('keydown', ready)
    }
    window.addEventListener('pointerdown', ready)
    window.addEventListener('keydown', ready)

    // A saved login is only a claim until the server confirms it. Show the saved screen right
    // away, then check in the background: if the token is expired, forged or the account is
    // gone, drop back to the start with an explanation.
    if (user) {
      getMe()
        .then(me => {
          if (me.username !== user.username) {
            user = { ...user, username: me.username }
            saveUser(user)
          }
        })
        .catch(e => e.status === 401 && signOut('Your session expired. Please start again.'))
    }

    // browser Back from /room/ABCD means "I'm leaving"
    const onPop = () => view === 'lobby' && leave()
    window.addEventListener('popstate', onPop)
    return () => window.removeEventListener('popstate', onPop)
  })

  function home() {
    view = user ? 'dashboard' : 'home'
  }

  function authed({ detail }) {
    user = detail
    saveUser(user)
    notice = ''
    view = 'dashboard'
  }

  function openAuth({ detail }) {
    authMode = detail
    view = 'auth'
  }

  function signOut(message = '') {
    clearUser()
    clearSeat()
    user = null
    seat = null
    inviteCode = ''
    notice = message
    history.replaceState({}, '', '/')
    view = 'home'
  }

  function enter({ detail: { code, playerId, name } }) {
    if (user?.userType === 'guest' && user.name !== name) {
      user = { ...user, name }
      saveUser(user)
    }
    seat = { code, playerId }
    saveSeat(seat)
    inviteCode = ''
    notice = ''
    history.pushState({}, '', `/room/${code}`)
    view = 'lobby'
    if (!hasSeenHowToPlay()) showHelp = true
  }

  function leave(message = '') {
    clearSeat()
    seat = null
    inviteCode = ''
    notice = typeof message === 'string' ? message : ''
    history.replaceState({}, '', '/')
    home()
  }
</script>

{#if view === 'lobby'}
  <Lobby roomCode={seat.code} playerId={seat.playerId} on:leave={() => leave()} on:gone={e => leave(e.detail)} />
{:else if view === 'auth'}
  <Auth mode={authMode} on:authed={authed} on:back={home} />
{:else if view === 'dashboard'}
  <Dashboard {user} {inviteCode} {notice} on:enter={enter} on:auth={openAuth} on:logout={() => signOut()} />
{:else}
  <Home {inviteCode} {notice} on:authed={authed} on:auth={openAuth} on:help={() => (showHelp = true)} />
{/if}

<Controls on:help={() => (showHelp = true)} />
{#if showHelp}
  <HowToPlay on:close={closeHelp} />
{/if}
