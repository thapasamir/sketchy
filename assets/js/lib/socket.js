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
export function joinRoom(code, playerId, { onJoined, onError }) {
  const channel = getSocket().channel(`room:${code}`, { player_id: playerId })

  channel
    .join()
    .receive('ok', ({ room }) => onJoined(room))
    .receive('error', ({ reason }) => onError(reason))
    .receive('timeout', () => onError('timeout'))

  return channel
}
