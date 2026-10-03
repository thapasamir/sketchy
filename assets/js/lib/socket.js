// One WebSocket per tab, shared by every channel. Phoenix reconnects it automatically.
import { Socket } from 'phoenix'

let socket

function getSocket() {
  if (!socket) {
    socket = new Socket('/socket')
    socket.connect()
  }
  return socket
}

// Join the live channel for a room. The server only accepts players who are in that room.
// Returns the channel so the caller can leave() it.
export function joinRoom(code, playerId, { onJoined, onUpdate, onDraw, onKicked, onError }) {
  const channel = getSocket().channel(`room:${code}`, { player_id: playerId })

  // The server pushes the full room whenever it changes (someone joins, settings change, ...)
  channel.on('room_updated', ({ room, secret }) => onUpdate(room, secret))
  channel.on('kicked', () => onKicked())

  // Strokes from whoever is drawing: start / points / end / undo. They arrive many times a second.
  channel.on('draw', event => onDraw(event))

  channel
    .join()
    // `strokes` is the picture so far, for someone who joins or refreshes mid-game
    .receive('ok', ({ room, secret, strokes }) => onJoined(room, secret, strokes))
    .receive('error', ({ reason }) => onError(reason))
    .receive('timeout', () => onError('timeout'))

  return channel
}
