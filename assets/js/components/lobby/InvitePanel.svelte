<script>
  import Button from '../Button.svelte'
  import QrCode from '../QrCode.svelte'
  import { copyText, shareInvite } from '../../lib/invite.js'

  // The room's code, big, and the ways to get it to a friend, in one bar.
  let { code, inviteUrl } = $props()

  // which button says "Copied!" for a moment: 'link' | ''
  let copied = $state('')
  let showQr = $state(false)

  async function copyLink() {
    await copyText(inviteUrl)
    copied = 'link'
    setTimeout(() => (copied = ''), 1500)
  }

  async function share() {
    // where there is no share sheet, sharing copies the link (and the button says so)
    if ((await shareInvite({ code, url: inviteUrl })) === 'copied') {
      copied = 'link'
      setTimeout(() => (copied = ''), 1500)
    }
  }
</script>

<div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between sm:gap-6">
  <div class="min-w-0">
    <div class="font-stamp text-sm text-riso-muted">Room code · share it with friends</div>
    <div
      id="room-code"
      class="mt-1 pl-[0.1em] font-display text-5xl leading-none tracking-[0.2em] text-riso-pink mix-blend-multiply sm:text-6xl">
      {code}
    </div>
  </div>

  <!-- three buttons of one fixed size: no label can make one a different height -->
  <div class="grid grid-cols-3 gap-2 sm:w-[21rem] sm:shrink-0">
    <Button variant="blue" class="h-11 min-w-0 whitespace-nowrap !px-2 !py-0 font-stamp text-sm" onclick={copyLink}>
      {copied === 'link' ? 'Copied!' : 'Copy link'}
    </Button>
    <Button id="share-button" variant="yellow" class="h-11 min-w-0 whitespace-nowrap !px-2 !py-0 font-stamp text-sm" onclick={share}>
      Share
    </Button>
    <Button
      id="qr-toggle"
      aria-expanded={showQr}
      aria-controls="qr-panel"
      class="h-11 min-w-0 whitespace-nowrap !px-2 !py-0 font-stamp text-sm"
      onclick={() => (showQr = !showQr)}>
      {showQr ? 'Hide QR code' : 'QR code'}
    </Button>
  </div>
</div>

{#if showQr}
  <div id="qr-panel" class="mt-4 animate-rise border-2 border-riso-ink bg-white p-4 text-center">
    <div class="mx-auto w-52 sm:w-60">
      <QrCode text={inviteUrl} label="QR code to join room {code}" />
    </div>
    <p class="mt-2 font-stamp text-xs text-riso-muted">Point a phone camera here to join room {code}.</p>
  </div>
{/if}
