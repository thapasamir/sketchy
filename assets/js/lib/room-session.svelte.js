// One player's live connection to one room: the channel, everything the server tells us, and
// everything we can ask it to do. The page (Lobby.svelte) only shows what is in here.
//
// The server's room state is the source of truth; every update replaces it wholesale.
import { joinRoom } from './socket.js'
import { createStrokeStore } from './strokes.js'
import { cuesFor } from './cues.js'
import { noticesFor } from './notices.js'
import { play } from './sound.js'
import { saveAvatar } from './avatar.js'
import { joinReasons, drawReasons, describeAction } from './messages.js'
import { Chat } from './chat.svelte.js'
import { FloatingReactions } from './floating-reactions.svelte.js'
import { Toasts } from './toasts.svelte.js'

export class RoomSession {
  // 'connecting' | 'live' | 'error'
  status = $state('connecting')
  errorMessage = $state('')
  room = $state.raw(null)
  // What THIS player may know about the round (the word, or the imposter's hint). The server
  // sends it only to this player; it is never part of the shared room.
  secret = $state.raw(null)
  // who I voted for (only the server and I know)
  vote = $state(null)
  drawError = $state('')
  actionError = $state('')
  // countdown while everyone reads their card
  secondsLeft = $state(0)

  // the shared picture; lives here (not in the board) so strokes aren't lost between screens
  strokes = createStrokeStore()

  chat
  reactions
  toasts

  #roomCode
  #playerId
  #onGone
  #channel = null
  #cueTimers = []
  #countdown
  #lastPhase
  #hadPen = false
  #turnKey = ''
  #originalTitle = ''

  // `onGone(reason)` is called when this seat can no longer be used (kicked, room closed)
  constructor({ roomCode, playerId, onGone }) {
    this.#roomCode = roomCode
    this.#playerId = playerId
    this.#onGone = onGone
    const channel = () => this.#channel
    this.chat = new Chat(roomCode, playerId, channel)
    this.reactions = new FloatingReactions(channel)
    this.toasts = new Toasts()
  }

  // --- what the page asks about ---

  get playerId() {
    return this.#playerId
  }
  get players() {
    return this.room ? this.room.players : []
  }
  get isHost() {
    return this.room?.host_id === this.#playerId
  }
  get code() {
    return this.room ? this.room.code : this.#roomCode
  }
  get inviteUrl() {
    return `${location.origin}/room/${this.code}`
  }
  get me() {
    return this.players.find(p => p.id === this.#playerId)
  }
  get myReady() {
    return !!this.me?.ready
  }
  get connectedCount() {
    return this.players.filter(p => p.connected).length
  }
  get minPlayers() {
    return this.room?.min_players ?? 3
  }
  get playing() {
    return !!this.room && this.room.phase !== 'lobby'
  }
  get inGame() {
    return ['drawing', 'voting', 'guess', 'result'].includes(this.room?.phase)
  }
  get finished() {
    return this.room?.phase === 'final'
  }
  // everyone who is here, isn't the host, and hasn't said ready (away players don't hold things up)
  get waitingFor() {
    return this.players.filter(p => p.id !== this.room?.host_id && p.connected && !p.ready).length
  }
  get canStart() {
    return this.isHost && this.connectedCount >= this.minPlayers && this.waitingFor === 0
  }

  // --- joining and leaving ---

  connect() {
    document.addEventListener('visibilitychange', this.#onVisibility)
    this.#channel = joinRoom(this.#roomCode, this.#playerId, {
      onJoined: (room, secret, picture, vote) => {
        this.secret = secret
        this.vote = vote
        this.strokes.load(picture)
        this.#adopt(room)
        this.status = 'live'
      },
      onUpdate: this.#applyUpdate,
      onDraw: event => this.strokes.apply(event),
      onChat: this.chat.receive,
      onReaction: this.reactions.receive,
      onKicked: () => this.#onGone('The host removed you from the room.'),
      onError: reason => {
        const message = joinReasons[reason] || 'Could not connect to the room.'
        // A closed room or a seat that isn't yours can't be fixed by retrying: go home and say why.
        if (reason === 'timeout') {
          this.errorMessage = message
          this.status = 'error'
        } else {
          this.#onGone(message)
        }
      },
    })
  }

  // Leaving the screen on purpose (Leave button, browser Back, room closed) frees the seat right
  // away. Closing the tab or refreshing skips this, so the server keeps the seat for a grace
  // period and you can come straight back.
  destroy() {
    clearInterval(this.#countdown)
    this.#cueTimers.forEach(clearTimeout)
    this.toasts.stop()
    this.reactions.stop()
    this.#restoreTitle()
    document.removeEventListener('visibilitychange', this.#onVisibility)
    this.chat.leave()
    this.#channel?.push('leave', {})
    this.#channel?.leave()
  }

  // --- the room changing ---

  // Every change to the room comes through here: work out what it should sound like (see
  // lib/cues.js), play it, and update the screen.
  #applyUpdate = (next, nextSecret, nextVote) => {
    const cues = cuesFor(this.room, next, this.#playerId, nextSecret)
    this.toasts.add(noticesFor(this.room, next, this.#playerId))
    this.secret = nextSecret
    this.vote = nextVote
    this.#adopt(next)

    const myTurn = next.phase === 'drawing' && next.turn?.player_id === this.#playerId
    if (!myTurn) this.#restoreTitle()

    for (const cue of cues) {
      if (cue.delay) this.#cueTimers.push(setTimeout(() => play(cue.name), cue.delay))
      else play(cue.name)
      if (cue.attention) this.#attention()
    }
  }

  // take the new room, and do what a change to it calls for
  #adopt(next) {
    this.room = next

    // everyone reads their card for a while: count down
    if (next.phase !== this.#lastPhase) {
      this.#lastPhase = next.phase
      clearInterval(this.#countdown)
      if (next.phase === 'reveal') {
        this.secondsLeft = next.reveal_seconds
        this.#countdown = setInterval(() => this.secondsLeft > 0 && (this.secondsLeft -= 1), 1000)
      }
    }

    if (!next.chat_open) this.chat.chatClosed()

    // when the pen leaves my hands, make sure my screen matches the real picture
    const hasPen = next.phase === 'drawing' && next.turn?.player_id === this.#playerId
    if (this.#hadPen && !hasPen && this.#channel) this.resync()
    this.#hadPen = hasPen

    // a complaint about one turn shouldn't follow you into the next
    const turnKey = next.turn ? `${next.turn.player_id}:${next.turn.lap}` : ''
    if (turnKey !== this.#turnKey) {
      this.#turnKey = turnKey
      this.drawError = ''
    }

    // A new round (and a new game) starts with an empty canvas. The server has already cleared its
    // copy; this clears the one in this browser.
    if (next.phase === 'reveal' || next.phase === 'lobby') this.strokes.load([])
  }

  // --- the tab's title: say so when it is your turn and you're looking at something else ---

  #attention() {
    navigator.vibrate?.(70)
    if (document.hidden) {
      this.#originalTitle ||= document.title
      document.title = 'Your turn! · Sketchy'
    }
  }

  #restoreTitle() {
    if (this.#originalTitle) {
      document.title = this.#originalTitle
      this.#originalTitle = ''
    }
  }

  #onVisibility = () => !document.hidden && this.#restoreTitle()

  // --- asking the server to do things ---

  send = (event, payload = {}) => {
    this.actionError = ''
    this.#channel
      .push(event, payload)
      .receive('error', ({ reason }) => (this.actionError = describeAction(reason, this.minPlayers)))
      .receive('timeout', () => (this.actionError = joinReasons.timeout))
  }

  // change my face: remember it for next time, and tell the room
  setAvatar = face => {
    saveAvatar(face)
    this.send('set_avatar', face)
  }

  startGame = () => this.send('start')
  nextRound = () => this.send('next_round')
  playAgain = () => this.send('play_again')
  submitGuess = text => this.send('guess', { text })
  kick = playerId => this.send('kick', { player_id: playerId })
  updateSettings = changes => this.send('update_settings', changes)

  toggleReady = () => {
    play('select')
    this.send('set_ready', { ready: !this.myReady })
  }

  castVote = targetId => {
    play('select')
    this.vote = targetId // show it at once; the server's answer arrives right behind
    this.send('vote', { target_id: targetId })
  }

  // --- drawing ---

  // The drawer's own screen is drawn before the server has agreed to anything. If the server
  // refused part of it (the turn ran out mid-stroke, too many strokes), that part is on this
  // screen only. Asking for the server's picture puts everyone back on the same one.
  resync = () => {
    this.#channel.push('sync', {}).receive('ok', ({ strokes }) => this.strokes.load(strokes))
  }

  // Strokes are sent without waiting for an answer; the server only answers to refuse.
  sendStroke = event => {
    this.#channel.push('draw', event).receive('error', ({ reason }) => {
      this.drawError = drawReasons[reason] ?? ''
      this.resync()
    })
  }

  undo = () => {
    this.drawError = ''
    this.#channel.push('undo', {}).receive('ok', event => this.strokes.apply(event))
  }

  finishTurn = () => this.#channel.push('finish_turn', {})
}
