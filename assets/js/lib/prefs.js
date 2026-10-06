// Small preferences this browser remembers: sound on/off, and whether it has seen "How to play".
import { read, write } from './storage.js'

const MUTED = 'sketchy:muted'
const SEEN_HELP = 'sketchy:seen-how-to-play'

export const loadMuted = () => read(MUTED) === true
export const saveMuted = muted => write(MUTED, muted === true)

const SEEN_VOTE_HELP = 'sketchy:seen-vote-help'

export const hasSeenVoteHelp = () => read(SEEN_VOTE_HELP) === true
export const markVoteHelpSeen = () => write(SEEN_VOTE_HELP, true)

export const hasSeenHowToPlay = () => read(SEEN_HELP) === true
export const markHowToPlaySeen = () => write(SEEN_HELP, true)
