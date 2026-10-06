<script>
  import AvatarEditor from '../AvatarEditor.svelte'
  import Button from '../Button.svelte'
  import Card from '../Card.svelte'
  import ChatPanel from '../ChatPanel.svelte'
  import Modal from '../Modal.svelte'
  import InvitePanel from './InvitePanel.svelte'
  import LobbyAction from './LobbyAction.svelte'
  import PlayerList from './PlayerList.svelte'
  import SettingsCard from './SettingsCard.svelte'

  // Everything before the drawing starts. The room on the left, top to bottom: the code and how to
  // share it, who is here beside what the game will be like, and the one thing to do next. The chat
  // is a column on the right exactly as tall as that stack (so the bottoms line up, and it is never
  // a tall empty slab). On a phone the chat is a bar you open, so it isn't at the bottom of a long page.
  let { session } = $props()

  let room = $derived(session.room)
  let chatOpen = $derived(room.chat_open)

  // changing your own look (tap your marker in the player list)
  let editingAvatar = $state(false)
  let me = $derived(session.me)

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

<!-- On a tall window the whole thing grows to fill it (up to a point), so there is no blank band
     under the content: the cards stretch, the action stays at the bottom, the chat follows. -->
<div class="grid grid-cols-[minmax(0,1fr)] items-start gap-5 lg:min-h-[min(calc(100dvh-7rem),46rem)] {chatOpen ? 'lg:grid-cols-[minmax(0,1fr)_21rem] lg:items-stretch' : ''}">
  <div class="flex min-w-0 flex-col gap-5">
    <Card class="!p-5">
      <InvitePanel code={session.code} inviteUrl={session.inviteUrl} />
    </Card>

    <!-- side by side and the same height, so neither card leaves a gap under it -->
    <div class="grid grid-cols-[minmax(0,1fr)] gap-5 md:grid-cols-2 md:items-stretch lg:flex-1">
      <Card class="flex flex-col !p-5">
        <PlayerList
          players={session.players}
          hostId={room.host_id}
          playerId={session.playerId}
          canKick={session.isHost && !session.playing}
          onkick={session.kick}
          onedit={() => (editingAvatar = true)}
          minPlayers={session.minPlayers} />
        <p class="mt-auto pt-5 font-stamp text-xs text-riso-muted">
          Friends join with the room code, or the invite link, above.
        </p>
      </Card>

      <SettingsCard {session} />
    </div>

    {#if !session.playing}
      <LobbyAction {session} />
    {/if}
  </div>

  <!-- (Closed while cards are read: see Chat.open?/1 on the server.) -->
  {#if chatOpen}
    <aside id="lobby-chat" class="relative flex flex-col gap-3 lg:min-h-[22rem]">
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
              <span id="chat-unread" class="rounded-full bg-riso-stamp px-2.5 py-0.5 font-stamp text-xs text-white">{unread} new</span>
            {/if}
            <span aria-hidden="true" class="font-stamp text-sm transition {open ? 'rotate-180' : ''}">▾</span>
          </span>
        </button>
      {/if}

      {#if wide || open}
        <!-- on a wide screen this fills the column without adding to its height, so the column is as tall as the room -->
        <div class="flex flex-col lg:absolute lg:inset-0">
          <ChatPanel
            fill
            messages={session.chat.messages}
            players={session.players}
            playerId={session.playerId}
            send={session.chat.send}
            error={session.chat.error}
            hint="Say hi while you wait for everyone." />
        </div>
      {/if}
    </aside>
  {/if}
</div>

{#if editingAvatar && me}
  <Modal id="avatar-dialog" title="Your look" onclose={() => (editingAvatar = false)}>
    <AvatarEditor face={me.avatar} color={me.color ?? '#ffe800'} name={me.name} id={me.id} onchange={session.setAvatar} />
    {#snippet footer()}
      <Button id="avatar-done" variant="yellow" class="w-full py-3 text-lg" onclick={() => (editingAvatar = false)}>Done</Button>
    {/snippet}
  </Modal>
{/if}
