// Getting the room's link or code to a friend.

// Put text on the clipboard. Older browsers and some embedded views refuse the modern way, so fall
// back to selecting a hidden box and copying from that.
export async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text)
  } catch {
    const box = document.createElement('textarea')
    box.value = text
    document.body.append(box)
    box.select()
    document.execCommand('copy')
    box.remove()
  }
}

// The phone's own share sheet (WhatsApp, Messages, AirDrop, ...). Where there isn't one (most
// desktop browsers), sharing just copies the link. Closing the sheet is not an error.
// Returns 'shared', 'copied' (it fell back to the clipboard) or 'cancelled'.
export async function shareInvite({ code, url }) {
  const data = { title: 'Join my Sketchy game', text: `Join my Sketchy game! Room code ${code}`, url }
  if (!navigator.share) {
    await copyText(url)
    return 'copied'
  }
  try {
    await navigator.share(data)
    return 'shared'
  } catch (e) {
    if (e?.name === 'AbortError') return 'cancelled'
    await copyText(url)
    return 'copied'
  }
}
