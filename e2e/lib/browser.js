// What every browser test needs to start: where the game is, and a Chrome to drive it.
const { existsSync } = require('node:fs')
const puppeteer = require('puppeteer-core')

// where the game is running; the runner sets this, a hand-started server is on 4012 by default
const U = process.env.E2E_URL || 'http://localhost:4012'

const CANDIDATES = [
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome',
  '/usr/bin/google-chrome-stable',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
]

function chromePath() {
  if (process.env.CHROME_PATH) return process.env.CHROME_PATH
  const found = CANDIDATES.find(existsSync)
  if (!found) throw new Error('No Chrome found. Install it, or set CHROME_PATH to its location.')
  return found
}

const launch = (options = {}) => puppeteer.launch({ executablePath: chromePath(), headless: 'new', ...options })

module.exports = { U, launch, chromePath }
