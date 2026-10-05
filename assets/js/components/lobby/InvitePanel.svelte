<script>
  import Button from '../Button.svelte'
  import QrCode from '../QrCode.svelte'
  import { copyText, shareInvite } from '../../lib/invite.js'

  // the room's code and the link a friend opens to join it
  let { code, inviteUrl } = $props()

  // which button says "Copied!" for a moment: 'code' | 'link' | ''
  let copied = $state('')
  let showQr = $state(false)

  async function copy(text, key) {
    await copyText(text)
    copied = key
    setTimeout(() => copied === key && (copied = ''), 1500)
  }

  async function share() {
    // where there is no share sheet, sharing copies the link (and the button says so)
    if ((await shareInvite({ code, url: inviteUrl })) === 'copied') copied = 'link'
  }
</script>

<div class="border-2 border-riso-ink bg-white/60 p-5 text-center">
  <div class="mb-2 font-stamp text-xs uppercase tracking-widest text-riso-muted">Share this</div>
  <div
    id="room-code"
    class="pl-[0.2em] font-display text-4xl tracking-[0.2em] text-riso-pink mix-blend-multiply sm:text-5xl">
    {code}
  </div>
</div>

<div class="mt-3 flex gap-3">
  <Button class="min-w-0 flex-1 px-3 py-2.5 font-stamp text-sm" onclick={() => copy(code, 'code')}>
    {copied === 'code' ? 'Copied!' : 'Copy code'}
  </Button>
  <Button variant="blue" class="min-w-0 flex-1 px-3 py-2.5 font-stamp text-sm" onclick={() => copy(inviteUrl, 'link')}>
    {copied === 'link' ? 'Copied!' : 'Copy invite link'}
  </Button>
</div>

<div class="mt-3 flex gap-3">
  <Button id="share-button" variant="yellow" class="min-w-0 flex-1 px-3 py-2.5 font-stamp text-sm" onclick={share}>
    Share
  </Button>
  <Button
    id="qr-toggle"
    aria-expanded={showQr}
    aria-controls="qr-panel"
    class="min-w-0 flex-1 px-3 py-2.5 font-stamp text-sm"
    onclick={() => (showQr = !showQr)}>
    {showQr ? 'Hide QR code' : 'QR code'}
  </Button>
</div>

{#if showQr}
  <div id="qr-panel" class="mt-3 animate-rise border-2 border-riso-ink bg-white p-4 text-center">
    <div class="mx-auto w-52 sm:w-60">
      <QrCode text={inviteUrl} label="QR code to join room {code}" />
    </div>
    <p class="mt-2 font-stamp text-xs text-riso-muted">Point a phone camera here to join room {code}.</p>
  </div>
{/if}
