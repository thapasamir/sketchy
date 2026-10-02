// What this browser remembers: who you are, and which room you are sitting in.
const USER = 'sketchy:user'
const SEAT = 'sketchy:seat'

function read(key) {
  try {
    return JSON.parse(localStorage.getItem(key))
  } catch {
    return null
  }
}

function write(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value))
  } catch {
    // storage blocked (private mode): the game still works, you just won't be remembered
  }
}

function remove(key) {
  try {
    localStorage.removeItem(key)
  } catch {}
}

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
