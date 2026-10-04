// What this browser remembers: who you are, and which room you are sitting in.
import { read, write, remove } from './storage.js'

const USER = 'sketchy:user'
const SEAT = 'sketchy:seat'

export function loadUser() {
  const user = read(USER)
  return user && user.userId && user.userType && user.token ? user : null
}
export const saveUser = user => write(USER, user)
export const clearUser = () => remove(USER)

// A "seat" is your place in a room: enough to walk back in after a refresh.
export function loadSeat() {
  const seat = read(SEAT)
  return seat && seat.code && seat.playerId ? seat : null
}
export const saveSeat = seat => write(SEAT, seat)
export const clearSeat = () => remove(SEAT)
