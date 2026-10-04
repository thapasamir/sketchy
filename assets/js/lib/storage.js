// localStorage that never throws. In a private window or with storage blocked the game still works;
// the browser just forgets things between visits.

export function read(key) {
  try {
    return JSON.parse(localStorage.getItem(key))
  } catch {
    return null
  }
}

export function write(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value))
  } catch {}
}

export function remove(key) {
  try {
    localStorage.removeItem(key)
  } catch {}
}
