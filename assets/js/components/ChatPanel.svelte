<script>
  import { afterUpdate } from 'svelte'
  import Button from './Button.svelte'
  import Card from './Card.svelte'

  export let messages = []
  export let players = []
  export let playerId
  // what to say when nobody has spoken yet
  export let hint = 'Say something.'
  // sends one message; resolves true if the room accepted it (so the box is only cleared then)
  export let send = async () => true
  export let error = ''

  const MAX = 200

  let text = ''
  let log

  $: colors = Object.fromEntries(players.map(p => [p.id, p.color]))
  $: left = MAX - text.length

  // stay at the newest message, unless the reader has scrolled up to read older ones
  let stick = true
  const onScroll = () => (stick = log.scrollHeight - log.scrollTop - log.clientHeight < 40)
  // (afterUpdate already runs once the new messages are on the page; calling tick() here would
  // schedule another update, and so another afterUpdate, forever)
  afterUpdate(() => {
    if (stick && log) log.scrollTop = log.scrollHeight
  })

  // The box is cleared at once, so you can keep typing while the message is on its way. Only if the
  // room refuses it (too fast, chat just closed) does the text come back, in front of anything
  // you have typed since. (No "already sending" guard: the server does the rate limiting, and a
  // second message pressed on a slow connection should still be sent, not silently ignored.)
  async function submit() {
    const message = text.trim()
    if (!message) return
    text = ''
    stick = true
    if (!(await send(message))) text = text ? `${message} ${text}` : message
  }
</script>

<Card id="chat-panel" class="flex flex-col !p-4">
  <h3 class="mb-2 font-display text-lg">Chat</h3>

  <div
    id="chat-log"
    bind:this={log}
    on:scroll={onScroll}
    role="log"
    aria-live="polite"
    aria-label="Chat messages"
    class="mb-3 flex h-44 flex-col gap-1.5 overflow-y-auto rounded-[2px] border border-riso-line bg-white/50 p-2.5 sm:h-52">
    {#each messages as message (message.id + ':' + message.at)}
      <div data-chat-from={message.name} class="min-w-0 text-sm {message.player_id === playerId ? 'text-right' : ''}">
        <span
          class="mr-1 inline-block h-2.5 w-2.5 rounded-full border border-riso-ink/50 align-baseline"
          style="background:{colors[message.player_id] ?? '#b9bbb0'}"
          aria-hidden="true"></span>
        <b class="font-bold">{message.player_id === playerId ? 'You' : message.name}</b>
        <span class="break-words">{message.text}</span>
      </div>
    {:else}
      <p class="m-auto text-center font-stamp text-xs text-riso-muted">{hint}</p>
    {/each}
  </div>

  <form class="flex gap-2" on:submit|preventDefault={submit}>
    <input
      id="chat-input"
      bind:value={text}
      maxlength={MAX}
      autocomplete="off"
      autocapitalize="sentences"
      enterkeyhint="send"
      placeholder="Message"
      aria-label="Message"
      class="min-w-0 flex-1 rounded-[3px] border-2 border-riso-ink bg-white/80 px-3 py-2.5 text-base outline-none focus:border-riso-blue focus:ring-2 focus:ring-riso-blue/30" />
    <Button id="chat-send" variant="blue" type="submit" class="px-3.5 py-2.5 text-base" disabled={!text.trim()}>
      Send
    </Button>
  </form>

  <div class="mt-1.5 flex min-h-4 items-center justify-between gap-2 font-stamp text-xs">
    <span id="chat-error" class="text-riso-stamp" role="alert">{error}</span>
    {#if left <= 40}<span class="text-riso-muted">{left}</span>{/if}
  </div>
</Card>
