// Where the drawing has got to: which turn this is, who has drawn, who is next, and how long until
// it is my go. Worked out from what everyone can already see (the order, the laps, whose turn it is),
// so it needs nothing from the server.
//
// `order` is who draws in each lap, `laps` how many laps there are, `turn` is { player_id, lap }.
// Returns null when there is no drawing going on.
export function progress({ order, laps, turn, playerId }) {
  if (!turn || !order?.length) return null

  const at = order.indexOf(turn.player_id)
  if (at < 0) return null

  const slots = []
  for (let lap = 1; lap <= laps; lap++) for (const id of order) slots.push({ id, lap })

  const current = (turn.lap - 1) * order.length + at
  const marked = slots.map((slot, i) => ({ ...slot, state: i < current ? 'done' : i === current ? 'now' : 'next' }))

  // how many turns from now until I draw again (0 means it is my turn now); null if I have none left
  const mine = marked.findIndex((slot, i) => i >= current && slot.id === playerId)
  const turnsUntilMe = mine < 0 ? null : mine - current

  return {
    slots: marked,
    number: current + 1,
    total: slots.length,
    upNext: marked[current + 1]?.id ?? null,
    turnsUntilMe,
  }
}

// a sentence for the card: what is it to me?
export function whenMine(turnsUntilMe) {
  if (turnsUntilMe === null) return "You've drawn all your turns."
  if (turnsUntilMe === 0) return "It's your turn."
  if (turnsUntilMe === 1) return "You're up next."
  return `You're up in ${turnsUntilMe} turns.`
}
