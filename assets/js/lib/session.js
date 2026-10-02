// Remembers who you are in this browser, so a refresh doesn't create a new guest.
const KEY = 'sketchy:user'

export function loadUser() {
  try {
    const user = JSON.parse(localStorage.getItem(KEY))
    return user && user.userId && user.userType ? user : null
  } catch {
    return null
  }
}

export function saveUser(user) {
  try {
    localStorage.setItem(KEY, JSON.stringify(user))
  } catch {
    // storage blocked (private mode): the game still works, you just won't be remembered
  }
}

export function clearUser() {
  try {
    localStorage.removeItem(KEY)
  } catch {}
}
