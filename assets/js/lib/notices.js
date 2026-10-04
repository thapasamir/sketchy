// Short messages about who came and went ("Bob left", "Bob is back"). Pure functions: given the
// room before and after a change, say which notices to show. The page shows them for a few
// seconds and forgets them.
//
// kind: 'good' (someone joined or came back), 'warn' (someone left or dropped), 'info'.

const byId = players => Object.fromEntries((players ?? []).map(p => [p.id, p]))

// `prev` and `next` are the public room before and after; `me` is my player id.
export function noticesFor(prev, next, me) {
  // the first snapshot (joining, refreshing) is not news
  if (!prev || !next) return []

  const before = byId(prev.players)
  const after = byId(next.players)
  const notices = []

  // someone is new
  for (const player of next.players) {
    if (before[player.id] || player.id === me) continue
    notices.push(
      player.spectator
        ? { text: `${player.name} is watching`, kind: 'info' }
        : { text: `${player.name} joined`, kind: 'good' },
    )
  }

  // someone is gone
  for (const player of prev.players) {
    if (after[player.id] || player.id === me) continue
    const wasImposter = next.phase === 'result' && prev.phase !== 'result' && next.result?.imposter_id === player.id && next.result?.outcome === 'imposter_left'
    notices.push(
      wasImposter
        ? { text: `${player.name} left, and they were the imposter!`, kind: 'warn' }
        : { text: `${player.name} left`, kind: 'warn' },
    )
  }

  // someone dropped, or came back (people who are staying, whose connection changed)
  for (const player of next.players) {
    const was = before[player.id]
    if (!was || player.id === me || was.connected === player.connected) continue
    notices.push(
      player.connected
        ? { text: `${player.name} is back`, kind: 'good' }
        : { text: `${player.name} lost their connection`, kind: 'warn' },
    )
  }

  // a spectator joins in at the start of a round
  for (const player of next.players) {
    if (before[player.id]?.spectator && !player.spectator && player.id !== me) {
      notices.push({ text: `${player.name} joins in this round`, kind: 'good' })
    }
  }

  // a new host
  if (prev.host_id && next.host_id && prev.host_id !== next.host_id && after[next.host_id]) {
    notices.push({ text: next.host_id === me ? 'You are the host now' : `${after[next.host_id].name} is the host now`, kind: 'info' })
  }

  return notices
}
