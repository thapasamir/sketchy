// This browser's side of the room chat.
//
// The server only relays chat, so this browser keeps the conversation: it starts from what was
// saved (a refresh doesn't lose it) and is cleared when you leave the room for good.
import { append, load, save, clear } from './chatlog.js'
import { chatReasons } from './messages.js'
import { play } from './sound.js'

export class Chat {
  messages = $state.raw([])
  // what went wrong with the last message, for the box to show
  error = $state('')

  #roomCode
  #playerId
  #channel

  // `channel` is a function returning the room's channel (it doesn't exist until the page joins)
  constructor(roomCode, playerId, channel) {
    this.#roomCode = roomCode
    this.#playerId = playerId
    this.#channel = channel
    this.messages = load(roomCode, playerId)
  }

  receive = message => {
    this.messages = append(this.messages, message)
    save(this.#roomCode, this.#playerId, this.messages)
    if (message.player_id !== this.#playerId) play('message')
  }

  // resolves true if the room took the message, so the box is cleared only then
  send = text => {
    this.error = ''
    return new Promise(resolve => {
      this.#channel()
        .push('chat', { text })
        .receive('ok', () => resolve(true))
        .receive('error', ({ reason }) => {
          this.error = chatReasons[reason] ?? 'Could not send that.'
          resolve(false)
        })
        .receive('timeout', () => {
          this.error = 'Could not reach the server.'
          resolve(false)
        })
    })
  }

  // a note about an earlier problem shouldn't outlive the moment chat closes
  chatClosed = () => {
    this.error = ''
  }

  // leaving for good ends this conversation (a refresh doesn't come through here)
  leave = () => clear(this.#roomCode, this.#playerId)
}
