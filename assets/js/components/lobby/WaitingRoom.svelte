<script>
  import Card from '../Card.svelte'
  import ChatPanel from '../ChatPanel.svelte'
  import InvitePanel from './InvitePanel.svelte'
  import PlayerList from './PlayerList.svelte'
  import RevealCard from './RevealCard.svelte'
  import SettingsCard from './SettingsCard.svelte'

  // Everything before the drawing starts: the room's code and players on the left; on the right the
  // settings (waiting) or the card you read (the game is starting); chat underneath.
  let { session } = $props()

  let room = $derived(session.room)
</script>

<div class="grid gap-6 md:grid-cols-2">
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

  <!-- while waiting for friends. (Closed while cards are read: see Chat.open?/1 on the server.) -->
  {#if room.chat_open}
    <div class="md:col-span-2">
      <ChatPanel
        messages={session.chat.messages}
        players={session.players}
        playerId={session.playerId}
        send={session.chat.send}
        error={session.chat.error}
        hint="Say hi while you wait for everyone." />
    </div>
  {/if}
</div>
