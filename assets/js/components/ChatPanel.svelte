<script>
  import { afterUpdate } from 'svelte'
  import Card from './Card.svelte'
  import Marker from './Marker.svelte'
  import { groupMessages, timeLabel } from '../lib/chatformat.js'

  // on a wide screen, `fill` lets the chat take all the height its column has left
  export let fill = false
  let className = ''
  export { className as class }
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

  $: byId = Object.fromEntries(players.map(p => [p.id, p]))
  $: rows = groupMessages(messages)
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

<Card id="chat-panel" class="flex flex-col !p-4 {fill ? 'lg:min-h-[13rem] lg:flex-1 lg:!p-3' : ''} {className}">
  <h3 class="mb-2 font-display text-lg lg:mb-2">Chat</h3>

  <!-- the conversation: yours on the right in blue, everyone else's on the left. Messages from one
       person in a row share a name (above the first), a marker (by the last) and a time (under it) -->
  <div
    id="chat-log"
    bind:this={log}
    on:scroll={onScroll}
    role="log"
    aria-live="polite"
    aria-label="Chat messages"
    class="mb-3 flex h-44 flex-col overflow-y-auto rounded-[3px] bg-riso-blue/5 px-3 py-3 sm:h-52 {fill ? 'lg:h-auto lg:min-h-0 lg:flex-1' : ''}">
    {#each rows as message (message.id + ':' + message.at)}
      {@const mine = message.player_id === playerId}
      <div
        data-chat-from={message.name}
        data-chat-mine={mine}
        class="flex min-w-0 flex-col {mine ? 'items-end' : 'items-start'} {message.first ? 'mt-3 first:mt-0' : 'mt-0.5'}">
        {#if message.first && !mine}
          <span class="mb-0.5 pl-9 font-stamp text-xs text-riso-muted">{message.name}</span>
        {/if}
        <div class="flex max-w-[88%] items-end gap-2 {mine ? 'flex-row-reverse' : ''}">
          {#if !mine}
            <span class="w-7 shrink-0">
              {#if message.last}<Marker player={byId[message.player_id]} size={28} />{/if}
            </span>
          {/if}
          <span
            class="min-w-0 whitespace-pre-wrap break-words rounded-[1.1rem] px-3.5 py-2 text-sm leading-snug {mine
              ? 'bg-riso-blue text-white'
              : 'border border-riso-line bg-white'} {message.last ? (mine ? 'rounded-br-[0.3rem]' : 'rounded-bl-[0.3rem]') : ''}">
            {message.text}
          </span>
        </div>
        {#if message.last}
          <span class="mt-0.5 font-stamp text-[0.65rem] text-riso-muted {mine ? 'pr-1' : 'pl-9'}">{timeLabel(message.at)}</span>
        {/if}
      </div>
    {:else}
      <p class="m-auto max-w-[16rem] text-center font-stamp text-xs text-riso-muted">{hint}</p>
    {/each}
  </div>

  <form
    class="flex items-center gap-2 rounded-full border-2 border-riso-ink bg-white py-1 pl-4 pr-1 transition focus-within:border-riso-blue focus-within:ring-2 focus-within:ring-riso-blue/30"
    on:submit|preventDefault={submit}>
    <input
      id="chat-input"
      bind:value={text}
      maxlength={MAX}
      autocomplete="off"
      autocapitalize="sentences"
      enterkeyhint="send"
      placeholder="Write a message"
      aria-label="Message"
      class="min-w-0 flex-1 bg-transparent py-2 text-base outline-none placeholder:text-riso-muted/70" />
    <button
      id="chat-send"
      type="submit"
      aria-label="Send"
      disabled={!text.trim()}
      class="grid h-11 w-11 shrink-0 cursor-pointer place-items-center rounded-full bg-riso-blue text-white transition enabled:hover:brightness-110 enabled:active:scale-95 disabled:cursor-default disabled:opacity-35">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <path d="M12 19V5M5 12l7-7 7 7" />
      </svg>
    </button>
  </form>

  <div class="mt-1.5 flex min-h-4 items-center justify-between gap-2 font-stamp text-xs">
    <span id="chat-error" class="text-riso-stamp" role="alert">{error}</span>
    {#if left <= 40}<span class="text-riso-muted">{left}</span>{/if}
  </div>
</Card>
