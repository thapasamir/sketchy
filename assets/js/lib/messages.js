// What to say when the server refuses something. The server sends a short reason; this turns it
// into a sentence a player can read. Anything it doesn't know gets a generic line, never the raw
// reason.

// why a room could not be joined
export const joinReasons = {
  room_not_found: 'That room has closed. Start a new one or join another.',
  not_a_member: "You're not a player in that room.",
  timeout: 'Could not reach the server. Check your connection and try again.',
}

export const chatReasons = {
  chat_closed: "Chat is closed right now. It's back during the vote.",
  too_fast: 'Slow down a little.',
  empty: 'Type something first.',
  too_long: 'That message is too long.',
  not_a_member: "You're not in this room any more.",
}

// an empty message means "say nothing": not being the drawer isn't worth a complaint
export const drawReasons = {
  not_your_turn: '',
  too_many_strokes: 'That is enough strokes for one turn.',
  canvas_full: 'The canvas is full.',
  stroke_too_long: 'That stroke got too long. Lift the pen and start a new one.',
}

export const actionReasons = minPlayers => ({
  not_host: 'Only the host can do that.',
  not_all_ready: 'Everyone needs to be ready first.',
  not_a_member: 'That player has already left.',
  host_cannot: "The host can't do that.",
  invalid_settings: "Those settings aren't allowed.",
  not_enough_players: `Need at least ${minPlayers} connected players to start.`,
  game_in_progress: 'The game has already started.',
  not_voting: 'The voting is over.',
  cannot_vote_self: "You can't vote for yourself.",
  not_imposter: 'Only the imposter can guess.',
  invalid_guess: 'Type a word or two.',
  not_guessing: 'The guessing is over.',
  not_result: 'That can only be done after a round.',
  not_finished: 'The game is not over yet.',
})

export const describeAction = (reason, minPlayers = 3) =>
  actionReasons(minPlayers)[reason] || 'Something went wrong.'
