// Checks about how the page is laid out on a screen.

// Does everything on the page stay within the screen's width? Returns { ok, offenders }, where
// offenders names (up to 5) the elements that stick out past the right edge.
//
// Why not `document.documentElement.scrollWidth <= innerWidth`? On an emulated phone, Chrome
// widens the page to fit whatever is too wide, so `innerWidth` grows with it and that check is
// always true. This compares each element's own edge with the width the screen was set to.
//
// An element inside something that deliberately scrolls or clips sideways (a row of chips you
// swipe) is allowed to be wider than the screen, because the container is what you see.
async function fitsScreen(page) {
  const width = page.viewport().width
  const offenders = await page.evaluate(width => {
    const clipped = el => {
      for (let a = el.parentElement; a && a !== document.documentElement; a = a.parentElement) {
        const x = getComputedStyle(a).overflowX
        if (x === 'auto' || x === 'scroll' || x === 'hidden' || x === 'clip') return true
      }
      return false
    }
    const out = []
    for (const el of document.body.querySelectorAll('*')) {
      const r = el.getBoundingClientRect()
      const style = getComputedStyle(el)
      if (r.width === 0 || style.visibility === 'hidden' || style.display === 'none' || style.position === 'fixed') continue
      if (r.right > width + 1 && !clipped(el)) out.push(`${el.tagName.toLowerCase()}${el.id ? '#' + el.id : ''} right=${Math.round(r.right)}`)
      if (out.length >= 5) break
    }
    return out
  }, width)
  return { ok: offenders.length === 0, offenders, width }
}

module.exports = { fitsScreen }
