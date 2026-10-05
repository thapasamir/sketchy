<script>
  import Card from '../Card.svelte'
  import ChatPanel from '../ChatPanel.svelte'
  import InvitePanel from './InvitePanel.svelte'
  import PlayerList from './PlayerList.svelte'
  import RevealCard from './RevealCard.svelte'
  import SettingsCard from './SettingsCard.svelte'

  // Everything before the drawing starts. Same shape as the game screen: the room on the left (its
  // code and players, and the settings or the card you read), and the chat in a column on the right
  // that fills the height. On a phone the chat is a bar you open, so it isn't at the bottom of a
  // long page.
  let { session } = $props()

  let room = $derived(session.room)
  let chatOpen = $derived(room.chat_open)

  // is the screen wide enough for the side column?
  let wide = $state(false)
  $effect(() => {
    const query = window.matchMedia('(min-width: 1024px)')
    wide = query.matches
    const update = e => (wide = e.matches)
    query.addEventListener('change', update)
    return () => query.removeEventListener('change', update)
  })

  // the phone's chat bar: closed until opened, and says how much you have missed meanwhile
  let open = $state(false)
  let seen = $state(0)
  let unread = $derived(
    open ? 0 : session.chat.messages.slice(seen).filter(m => m.player_id !== session.playerId).length
  )
  const toggle = () => {
    open = !open
    seen = session.chat.messages.length
  }
  // while it is open, everything that arrives has been seen
  $effect(() => {
    if (open) seen = session.chat.messages.length
  })
</script>

<div class="grid grid-cols-[minmax(0,1fr)] items-start gap-6 {chatOpen ? 'lg:grid-cols-[minmax(0,1fr)_21rem]' : ''}">
  <div class="grid grid-cols-[minmax(0,1fr)] gap-6 md:grid-cols-2">
    <Card>
      <h3 class="mb-5 font-display text-2xl sm:text-3xl">Room Code</h3>
      <InvitePanel code={session.code} inviteUrl={session.inviteUrl} />
      <PlayerList
        players={session.players}
        hostId={room.host_id}
        playerId={session.playerId}
        canKick={session.isHost && !session.playing}
        onkick={session.kick} />
    </Card>

    {#if session.playing}
      <RevealCard {room} secret={session.secret} secondsLeft={session.secondsLeft} />
    {:else}
      <SettingsCard {session} />
    {/if}
  </div>

  <!-- (Closed while cards are read: see Chat.open?/1 on the server.) -->
  {#if chatOpen}
    <aside id="lobby-chat" class="flex flex-col gap-3 lg:sticky lg:top-4 lg:h-[calc(100dvh-7rem)] lg:min-h-[26rem]">
      {#if !wide}
        <button
          type="button"
          id="chat-toggle"
          aria-expanded={open}
          aria-controls="chat-panel"
          onclick={toggle}
          class="flex min-h-12 w-full cursor-pointer items-center justify-between gap-3 rounded-[3px] border-2 border-riso-ink bg-white/60 px-4 py-2 font-display text-lg transition hover:bg-white">
          <span>Chat</span>
          <span class="flex items-center gap-2">
            {#if unread > 0}
              <span id="chat-unread" class="rounded-full bg-riso-pink px-2.5 py-0.5 font-stamp text-xs text-white">{unread} new</span>
            {/if}
            <span aria-hidden="true" class="font-stamp text-sm transition {open ? 'rotate-180' : ''}">▾</span>
          </span>
        </button>
      {/if}

      {#if wide || open}
        <ChatPanel
          fill
          messages={session.chat.messages}
          players={session.players}
          playerId={session.playerId}
          send={session.chat.send}
          error={session.chat.error}
          hint="Say hi while you wait for everyone." />
      {/if}
    </aside>
  {/if}
</div>
