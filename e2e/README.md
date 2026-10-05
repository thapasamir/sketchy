# Browser tests

These drive a real Chrome against a real running server: several browsers join one room and
play, and the tests check what each of them sees. They catch what unit tests can't (layout,
timing between players, what is on screen at each moment).

```
npm run test:e2e                    # every suite
npm run test:e2e -- vote chat       # suites whose name contains "vote" or "chat"
npm run test:e2e -- --list          # the suites, and the server settings each uses
npm run test:e2e -- --build         # rebuild the JS and CSS first
npm run test:e2e -- --retries=0     # don't give a failing suite a second go
```

You need Chrome installed (it is found automatically; set `CHROME_PATH` if it isn't) and
`npm install` done. The runner starts and stops the server itself, on port 4012
(`E2E_PORT` to change it), so stop any server already on that port first.

**Build first.** The tests run against the built files in `priv/static`, not your source. If they
look older than the code the runner says so; use `--build`.

## Server settings ("profiles")

The game's clocks (a turn, the vote, the result) are server settings, and suites need different
ones, so they are grouped (see `PROFILES` and `PROFILE_OF` in `run.js`). For each group the
runner starts a fresh server, runs the group's suites, and stops it.

| profile  | for                                                            |
| -------- | -------------------------------------------------------------- |
| `fast`   | most suites: votes and results run out within the test         |
| `steady` | suites that take their time and must not have a clock run out  |
| `turn`   | the one suite that watches a 6 second turn run out             |

A new suite uses `fast` unless you list it in `PROFILE_OF`.

## How a suite passes

A suite is a script in `suites/` that prints `PASS ...` or `FAIL ...` per check. It passes when it
exits cleanly, printed at least one `PASS`, and printed no `FAIL` or `CRASH`. A failing suite is
tried once more; if it passes the second time it is reported as **FLAKY**, and listed at the end.
Treat flaky as something to fix, not to ignore.

Output goes to `e2e/out/` (not committed): `<suite>.log` for each suite, `server-<profile>.log`
for each server, and screenshots in `e2e/out/shots`.

## Writing a suite

Copy a small one (`words.js`, `reactions.js`). Start with:

```js
const { U, launch } = require('../lib/browser')   // U is the server's address
const b = await launch()                            // a Chrome
```

Things that have caught people out:

* **Synthetic events don't bubble.** `new Event('change')` never reaches the page's root, where
  Svelte listens for it. Use `{ bubbles: true }`, or better, real input (`page.keyboard`, `page.click`).
* **A click can land mid-animation.** Panels rise in; scroll the button into view and wait a moment
  before clicking on a phone-sized screen.
* **Don't measure "no sideways scroll" with `scrollWidth <= innerWidth` on an emulated phone.** The
  emulated viewport widens to fit the content, so it is always true. Compare the elements' own
  rectangles with the screen width instead.
* **A suite whose steps take longer than a turn** needs the `steady` profile, or the drawer changes
  under it.
