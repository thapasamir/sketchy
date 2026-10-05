#!/usr/bin/env node
// Runs the browser tests (e2e/suites) against a real server.
//
//   npm run test:e2e                  every suite
//   npm run test:e2e -- vote chat     only suites whose name contains "vote" or "chat"
//   npm run test:e2e -- --list        what there is, and which server settings each one uses
//   npm run test:e2e -- --build       rebuild the JS and CSS first
//   npm run test:e2e -- --retries=0   don't give a failing suite a second go
//
// The game's timers (how long a turn, a vote, a result last) are settings of the server, and the
// suites need different ones: some wait for a clock to run out, some take their time. So the
// suites are grouped by the settings they need ("profiles"); for each group a fresh server is
// started with those settings, its suites run one after another, and the server is stopped.
const { spawn } = require('node:child_process')
const fs = require('node:fs')
const http = require('node:http')
const path = require('node:path')

const root = path.join(__dirname, '..')
const suitesDir = path.join(__dirname, 'suites')
const outDir = path.join(__dirname, 'out')
const port = Number(process.env.E2E_PORT || 4012)
const url = `http://localhost:${port}`

// Server settings: the game's clocks in milliseconds (see config/dev.exs for what each one is),
// and the abuse limits (see Backend.RateLimit).
//
// The abuse limits are ON in every profile, so every ordinary suite also proves that normal play
// isn't slowed down by them. They are loosened to 10 times their count (RATE_LIMIT_SCALE) only
// because a whole run makes far more guests and rooms from this one machine than any real person.
// Per-connection message limits are not affected by that, and are the real thing.
const LIMITS_EASED = { RATE_LIMIT_SCALE: 10 }

const PROFILES = {
  // short, so a vote or a result runs out by itself within a test
  fast: { REVEAL_MS: 1500, RECONNECT_GRACE_MS: 2500, TURN_MS: 5000, VOTE_MS: 8000, GUESS_MS: 8000, RESULT_MS: 6000, ...LIMITS_EASED },
  // long, for tests that take their time and must not have a clock run out under them
  steady: { REVEAL_MS: 1500, TURN_MS: 30000, VOTE_MS: 40000, GUESS_MS: 30000, RESULT_MS: 40000, ...LIMITS_EASED },
  // one turn of exactly 6 seconds, for the test that watches a turn run out
  turn: { REVEAL_MS: 1500, RECONNECT_GRACE_MS: 2500, TURN_MS: 6000, VOTE_MS: 30000, GUESS_MS: 20000, RESULT_MS: 12000, ...LIMITS_EASED },
  // tight limits (a tenth of the real counts, at most 6 rooms), and the caller's address taken from
  // a header so the test can be many different callers: only for the suite that tries to abuse the server
  limited: { REVEAL_MS: 1500, RECONNECT_GRACE_MS: 2500, RATE_LIMIT_SCALE: 0.1, MAX_ROOMS: 6, CLIENT_IP_HEADER: 'x-test-ip' },
}

// which settings each suite needs (a suite not listed here uses 'fast')
const PROFILE_OF = {
  'first-screens': 'steady',
  'reveal-stage': 'steady',
  draw: 'turn',
  'rate-limits': 'limited',
}

const args = process.argv.slice(2)
const flag = name => args.some(a => a === `--${name}`)
const option = (name, fallback) => (args.find(a => a.startsWith(`--${name}=`)) ?? `=${fallback}`).split('=')[1]
const filters = args.filter(a => !a.startsWith('--'))
const retries = Number(option('retries', 1))

const allSuites = fs.readdirSync(suitesDir).filter(f => f.endsWith('.js')).map(f => f.slice(0, -3)).sort()
const chosen = filters.length ? allSuites.filter(s => filters.some(f => s.includes(f))) : allSuites
const profileOf = suite => PROFILE_OF[suite] ?? 'fast'

if (flag('list')) {
  for (const s of allSuites) console.log(`${s.padEnd(16)} ${profileOf(s)}`)
  process.exit(0)
}
if (!chosen.length) {
  console.error(`No suite matches ${filters.join(', ')}. Try --list.`)
  process.exit(2)
}

const sleep = ms => new Promise(r => setTimeout(r, ms))

// What does the port say to a request? null if nothing is listening, else the HTTP status.
const probe = () =>
  new Promise(resolve => {
    const req = http.get(url + '/', res => (res.resume(), resolve(res.statusCode)))
    req.on('error', () => resolve(null))
    req.setTimeout(1500, () => (req.destroy(), resolve(null)))
  })

// is something listening at all (even something broken)?
const listening = async () => (await probe()) !== null
// is the game up and well?
const healthy = async () => {
  const status = await probe()
  return status !== null && status < 500
}

// are the built files older than the code they were built from?
function assetsAreStale() {
  const built = ['priv/static/assets/app.js', 'priv/static/assets/app.css'].map(f => path.join(root, f))
  if (!built.every(fs.existsSync)) return true
  const builtAt = Math.min(...built.map(f => fs.statSync(f).mtimeMs))
  const newest = dir =>
    fs.readdirSync(dir, { withFileTypes: true }).reduce((latest, e) => {
      const p = path.join(dir, e.name)
      return Math.max(latest, e.isDirectory() ? newest(p) : fs.statSync(p).mtimeMs)
    }, 0)
  return newest(path.join(root, 'assets/js')) > builtAt || newest(path.join(root, 'assets/css')) > builtAt
}

function run(cmd, cmdArgs, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, cmdArgs, { cwd: root, stdio: 'inherit', ...options })
    child.on('exit', code => (code === 0 ? resolve() : reject(new Error(`${cmd} ${cmdArgs.join(' ')} failed`))))
  })
}

async function startServer(profile) {
  const log = fs.openSync(path.join(outDir, `server-${profile}.log`), 'w')
  const child = spawn('mix', ['phx.server'], {
    cwd: root,
    detached: true, // its own process group, so stopping it stops the Erlang VM under it too
    stdio: ['ignore', log, log],
    env: { ...process.env, PORT: String(port), ...Object.fromEntries(Object.entries(PROFILES[profile]).map(([k, v]) => [k, String(v)])) },
  })
  let exited = false
  child.on('exit', () => (exited = true))
  for (let i = 0; i < 300; i++) {
    if (exited) throw new Error(`The server stopped while starting. See e2e/out/server-${profile}.log`)
    if (await healthy()) return child
    await sleep(300)
  }
  stopServer(child)
  throw new Error(`The server did not answer on ${url} in time. See e2e/out/server-${profile}.log`)
}

async function stopServer(child) {
  try {
    process.kill(-child.pid, 'SIGTERM')
  } catch {}
  for (let i = 0; i < 20 && (await listening()); i++) await sleep(250)
  try {
    process.kill(-child.pid, 'SIGKILL')
  } catch {}
}

// One go at one suite: its output, and whether it passed. A suite passes when it exits cleanly,
// says PASS at least once, and never says FAIL or CRASH (some suites exit 0 even after a FAIL).
function runSuite(suite, shots) {
  return new Promise(resolve => {
    const started = Date.now()
    const child = spawn('node', [path.join(suitesDir, `${suite}.js`), shots], {
      cwd: root,
      env: { ...process.env, E2E_URL: url },
    })
    let output = ''
    child.stdout.on('data', d => (output += d))
    child.stderr.on('data', d => (output += d))
    const timer = setTimeout(() => (output += '\nCRASH timed out after 5 minutes\n', child.kill('SIGKILL')), 300000)
    child.on('exit', code => {
      clearTimeout(timer)
      const passes = (output.match(/^PASS\b/gm) || []).length
      const failures = output.split('\n').filter(l => /^(FAIL|CRASH)\b/.test(l))
      resolve({ output, passes, failures, passed: code === 0 && passes > 0 && failures.length === 0, ms: Date.now() - started })
    })
  })
}

async function main() {
  fs.mkdirSync(path.join(outDir, 'shots'), { recursive: true })

  if (await listening()) {
    console.error(`Something is already listening on ${url}. Stop it, or set E2E_PORT to another port.`)
    process.exit(2)
  }
  if (flag('build')) await run('npm', ['run', 'build'])
  else if (assetsAreStale()) console.warn('Note: the built JS/CSS look older than the code. Run with --build to be sure you are testing what you wrote.\n')

  const byProfile = {}
  for (const s of chosen) (byProfile[profileOf(s)] ??= []).push(s)

  const results = []
  for (const [profile, suites] of Object.entries(byProfile)) {
    console.log(`\n== server settings: ${profile} (${suites.length} suite${suites.length === 1 ? '' : 's'})`)
    const server = await startServer(profile)
    try {
      for (const suite of suites) {
        let result = await runSuite(suite, path.join(outDir, 'shots'))
        let tries = 1
        while (!result.passed && tries <= retries) {
          console.log(`   ${suite}: failed, trying once more`)
          // keep what the failed go said: a flaky pass would otherwise hide why it failed
          fs.writeFileSync(path.join(outDir, `${suite}.failed-attempt-${tries}.log`), result.output)
          result = { ...(await runSuite(suite, path.join(outDir, 'shots'))), retried: true }
          tries++
        }
        fs.writeFileSync(path.join(outDir, `${suite}.log`), result.output)
        results.push({ suite, ...result })
        const mark = result.passed ? (result.retried ? 'FLAKY' : 'ok   ') : 'FAIL '
        console.log(`   ${mark} ${suite.padEnd(16)} ${String(result.passes).padStart(3)} checks  ${(result.ms / 1000).toFixed(1)}s`)
        if (!result.passed) for (const line of result.failures.slice(0, 6)) console.log(`          ${line.slice(0, 150)}`)
      }
    } finally {
      await stopServer(server)
    }
  }

  const failed = results.filter(r => !r.passed)
  const flaky = results.filter(r => r.passed && r.retried)
  const checks = results.reduce((n, r) => n + r.passes, 0)
  console.log(`\n${results.length - failed.length} of ${results.length} suites passed, ${checks} checks.`)
  if (flaky.length) console.log(`Passed only on a second go (look into these): ${flaky.map(r => r.suite).join(', ')}`)
  if (failed.length) console.log(`Failed: ${failed.map(r => r.suite).join(', ')}. Output is in e2e/out/<suite>.log, pictures in e2e/out/shots.`)
  process.exit(failed.length ? 1 : 0)
}

main().catch(e => {
  console.error(e.message)
  process.exit(2)
})
