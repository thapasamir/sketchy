// Changing the game's settings in the lobby: the host opens a dialog (Change settings), taps, and
// closes it. The buttons in it are named `${setting}-${value}`: rounds-4, drawtime-60, laps-auto,
// difficulty-easy; categories are [data-category="Animals"].

const settled = ms => new Promise(r => setTimeout(r, ms))

async function openSettings(page) {
  if (await page.$('#settings-dialog')) return
  await page.click('#edit-settings')
  await page.waitForSelector('#settings-dialog')
}

async function closeSettings(page) {
  if (!(await page.$('#settings-dialog'))) return
  await page.click('#settings-done')
  await page.waitForFunction(() => !document.querySelector('#settings-dialog'))
}

// choose one value, then close the dialog; waits a moment for everyone to be told
async function setSetting(page, setting, value) {
  await openSettings(page)
  await page.click(`#${setting}-${value}`)
  await closeSettings(page)
  await settled(350)
}

// The lobby's player rows as text ("Samir (Host) (You)", "Priya Remove"), without the coloured
// marker in front of each name (its initial letter would otherwise be read as part of the text).
const playerRows = page =>
  page.$eval('#player-list', list =>
    [...list.querySelectorAll('li')].map(li => {
      const copy = li.cloneNode(true)
      copy.querySelectorAll('[data-marker]').forEach(marker => marker.remove())
      return copy.textContent.replace(/\s+/g, ' ').trim()
    })
  )

module.exports = { openSettings, closeSettings, setSetting, playerRows }
