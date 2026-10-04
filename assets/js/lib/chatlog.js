// What THIS browser remembers of the room's chat.
//
// The server keeps no chat: it only relays each message to whoever is in the room at that moment.
// So the conversation lives here. It is kept in sessionStorage so a refresh or a dropped
// connection doesn't wipe it, and it is cleared when you leave (a new seat is a new conversation).
// Storage can be blocked (private windows); then the chat just forgets on refresh.

const CAP = 100

const key = (code, playerId) => `sketchy:chat:${code}:${playerId}`

const isMessage = m =>
  m !== null &&
  typeof m === 'object' &&
  Number.isFinite(m.id) &&
  typeof m.player_id === 'string' &&
  typeof m.name === 'string' &&
  typeof m.text === 'string' &&
  Number.isFinite(m.at)

// add a message, ignoring one we already have, and keeping only the most recent CAP
export function append(list, message, cap = CAP) {
  if (list.some(m => m.id === message.id && m.at === message.at)) return list
  return [...list, message].slice(-cap)
}

export function load(code, playerId) {
  try {
    const saved = JSON.parse(sessionStorage.getItem(key(code, playerId)))
    // whatever is in storage is not trusted: only well-formed messages come back
    return Array.isArray(saved) ? saved.filter(isMessage).slice(-CAP) : []
  } catch {
    return []
  }
}

export function save(code, playerId, list) {
  try {
    sessionStorage.setItem(key(code, playerId), JSON.stringify(list))
  } catch {}
}

export function clear(code, playerId) {
  try {
    sessionStorage.removeItem(key(code, playerId))
  } catch {}
}
