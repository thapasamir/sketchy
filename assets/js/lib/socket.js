// One WebSocket per tab, shared by every channel. Phoenix reconnects it automatically.
import { Socket } from 'phoenix'

let socket

// who wants to hear that the connection dropped or came back: callback('lost' | 'restored')
const watchers = new Set()
const tell = state => watchers.forEach(watcher => watcher(state))

// is the socket open right now?
export const isConnected = () => !!socket?.isConnected()

export function watchConnection(watcher) {
  watchers.add(watcher)
  return () => watchers.delete(watcher)
}

function getSocket() {
  if (!socket) {
    socket = new Socket('/socket')
    // Phoenix reconnects on its own; these only say what is happening
    socket.onOpen(() => tell('restored'))
    socket.onClose(() => tell('lost'))
    socket.onError(() => tell('lost'))
    socket.connect()
  }
  return socket
}

// Join the live channel for a room. The server only accepts players who are in that room.
// Returns the channel so the caller can leave() it.
export function joinRoom(code, playerId, { onJoined, onUpdate, onDraw, onChat, onReaction, onKicked, onError }) {
  const channel = getSocket().channel(`room:${code}`, { player_id: playerId })

  // The server pushes the full room whenever it changes (someone joins, settings change, ...)
  // `vote` is who THIS player voted for; the server tells nobody else
  channel.on('room_updated', ({ room, secret, vote }) => onUpdate(room, secret, vote))
  channel.on('kicked', () => onKicked())

  // Strokes from whoever is drawing: start / points / end / undo. They arrive many times a second.
  channel.on('draw', event => onDraw(event))

  // Something said in the room. The server only relays it: nothing is stored, so each browser keeps
  // its own copy (see chatlog.js).
  channel.on('chat', message => onChat(message))

  // An emoji reaction from someone: { player_id, name, id }. Shown for a moment and forgotten.
  channel.on('reaction', event => onReaction(event))

  channel
    .join()
    // `strokes` is the picture so far, for someone who joins or refreshes mid-game
    .receive('ok', ({ room, secret, strokes, vote }) => onJoined(room, secret, strokes, vote))
    .receive('error', ({ reason }) => onError(reason))
    .receive('timeout', () => onError('timeout'))

  return channel
}
