// A picture of how the game ended, to post in the group chat. Drawn on a canvas in the game's own
// colours and fonts (1200 x 630, the shape link previews use), then shared as an image where the
// phone can ("Share" sheet), or saved as a file where it can't.

const W = 1200
const H = 630
const INK = '#263A6E'
const PAPER = '#F4F2EC'
const PINK = '#FF48B0'
const BLUE = '#0078BF'
const YELLOW = '#FFE800'
const MUTED = '#55574F'

const DISPLAY = '"Bowlby One", "Arial Black", Impact, sans-serif'
const TYPE = '"Special Elite", "Courier New", monospace'

// shorten text to fit a width, with an ellipsis
function fit(ctx, text, width) {
  if (ctx.measureText(text).width <= width) return text
  let cut = text
  while (cut.length > 1 && ctx.measureText(cut + '…').width > width) cut = cut.slice(0, -1)
  return cut + '…'
}

// `ranking` is [{ name, score, winner }] best first; at most five are shown
export function drawShareCard(ctx, { headline, ranking, rounds, url }) {
  ctx.fillStyle = PAPER
  ctx.fillRect(0, 0, W, H)

  // the wordmark: two inks, a little out of line
  ctx.textBaseline = 'alphabetic'
  ctx.font = `92px ${DISPLAY}`
  ctx.fillStyle = PINK
  ctx.fillText('SKETCHY', 60, 140)
  ctx.globalAlpha = 0.9
  ctx.fillStyle = BLUE
  ctx.fillText('SKETCHY', 66, 146)
  ctx.globalAlpha = 1

  ctx.font = `26px ${TYPE}`
  ctx.fillStyle = MUTED
  ctx.fillText(`GAME OVER AFTER ${rounds} ${rounds === 1 ? 'ROUND' : 'ROUNDS'}`, 62, 200)

  ctx.font = `54px ${DISPLAY}`
  ctx.fillStyle = INK
  ctx.fillText(fit(ctx, headline, W - 120), 60, 280)

  // the scores
  const top = ranking.slice(0, 5)
  const rowH = 58
  top.forEach((p, i) => {
    const y = 320 + i * rowH
    ctx.fillStyle = p.winner ? YELLOW : 'rgba(38,58,110,0.06)'
    ctx.fillRect(60, y, W - 120, rowH - 8)
    if (p.winner) {
      ctx.strokeStyle = INK
      ctx.lineWidth = 3
      ctx.strokeRect(60, y, W - 120, rowH - 8)
    }
    ctx.fillStyle = MUTED
    ctx.font = `24px ${TYPE}`
    ctx.fillText(String(i + 1), 80, y + 36)
    ctx.fillStyle = INK
    ctx.font = `28px ${DISPLAY}`
    ctx.fillText(fit(ctx, p.name, 700), 130, y + 37)
    ctx.textAlign = 'right'
    ctx.fillText(String(p.score), W - 80, y + 37)
    ctx.textAlign = 'left'
  })

  ctx.font = `24px ${TYPE}`
  ctx.fillStyle = MUTED
  ctx.textAlign = 'right'
  ctx.fillText(url.replace(/^https?:\/\//, ''), W - 60, 60)
  ctx.textAlign = 'left'

  // a line for whoever sees it without having played
  ctx.fillStyle = INK
  ctx.font = `28px ${TYPE}`
  ctx.fillText('Draw things. Catch the imposter. Play free with friends.', 62, H - 40)
}

// make the picture, then share it as an image, or save it
export async function shareCard(data) {
  // the fonts are loaded by the page's stylesheet; make sure they are ready before drawing
  try {
    await Promise.all([document.fonts.load(`92px "Bowlby One"`), document.fonts.load(`24px "Special Elite"`)])
  } catch {
    // drawn in the fallback fonts, which is fine
  }

  const canvas = document.createElement('canvas')
  canvas.width = W
  canvas.height = H
  drawShareCard(canvas.getContext('2d'), data)
  const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/png'))
  if (!blob) return 'failed'

  const file = new File([blob], 'sketchy-results.png', { type: 'image/png' })
  const text = `${data.headline} Play Sketchy: ${data.url}`
  if (navigator.canShare?.({ files: [file] })) {
    try {
      await navigator.share({ files: [file], text })
      return 'shared'
    } catch (error) {
      // closing the share sheet is not a failure
      if (error?.name === 'AbortError') return 'cancelled'
    }
  }

  // no share sheet for files (most computers): save the picture
  const link = document.createElement('a')
  link.href = URL.createObjectURL(blob)
  link.download = file.name
  document.body.appendChild(link)
  link.click()
  link.remove()
  setTimeout(() => URL.revokeObjectURL(link.href), 4000)
  return 'saved'
}
