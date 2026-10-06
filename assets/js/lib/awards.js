// What the end of a game says about how it went, worked out from the server's recap of each round
// (room.final.rounds): [{ round, outcome, imposter_id, word, category, accused, votes, points, names }].
// Pure, so every rule is unit-tested.

const OUTCOME_TEXT = {
  caught: 'Caught',
  escaped: 'Got away',
  guessed: 'Caught, but guessed the word',
  imposter_left: 'The imposter left',
}

export const outcomeText = outcome => OUTCOME_TEXT[outcome] ?? 'Finished'

// one line per round, for the recap
export function recap(rounds = []) {
  return rounds.map(r => ({
    round: r.round,
    imposterId: r.imposter_id,
    imposterName: r.names?.[r.imposter_id] ?? 'Someone',
    word: r.word,
    category: r.category,
    outcome: r.outcome,
    text: outcomeText(r.outcome),
    // did the crew win it? (the imposter escaping, or leaving, is not a crew win... leaving is)
    crewWon: r.outcome === 'caught' || r.outcome === 'imposter_left',
  }))
}

// how many times each id appears: { id: n }
function tally(ids) {
  const counts = {}
  for (const id of ids) counts[id] = (counts[id] ?? 0) + 1
  return counts
}

// everyone who has the highest count (a tie shares it), or null if nobody has any
function top(counts) {
  const best = Math.max(0, ...Object.values(counts))
  if (best < 1) return null
  return { ids: Object.keys(counts).filter(id => counts[id] === best), count: best }
}

// Up to three titles worth handing out. Each one goes to whoever did it most, and only if somebody
// did it at all. `names` (id -> name) is used when a title is shown; a player who has left still
// has the name they had in the round.
export function awards(rounds = []) {
  const found = []

  const escaped = top(tally(rounds.filter(r => r.outcome === 'escaped').map(r => r.imposter_id)))
  if (escaped) {
    found.push({
      key: 'disguise',
      title: 'Master of disguise',
      blurb: escaped.count === 1 ? 'Got away with it as the imposter.' : `Got away as the imposter ${escaped.count} times.`,
      ...escaped,
    })
  }

  const spotted = top(
    tally(rounds.flatMap(r => Object.entries(r.votes ?? {}).filter(([, target]) => target === r.imposter_id).map(([voter]) => voter)))
  )
  if (spotted) {
    found.push({
      key: 'eye',
      title: 'Sharpest eye',
      blurb: spotted.count === 1 ? 'Spotted the imposter.' : `Spotted the imposter ${spotted.count} times.`,
      ...spotted,
    })
  }

  const thief = top(tally(rounds.filter(r => r.outcome === 'guessed').map(r => r.imposter_id)))
  if (thief) {
    found.push({
      key: 'thief',
      title: 'Word thief',
      blurb: thief.count === 1 ? 'Caught, but still guessed the word.' : `Guessed the word after being caught ${thief.count} times.`,
      ...thief,
    })
  }

  return found
}

// a name for an id, from the first round that has one
export function nameIn(rounds, id, fallback = 'Someone') {
  for (const r of rounds) if (r.names?.[id]) return r.names[id]
  return fallback
}
