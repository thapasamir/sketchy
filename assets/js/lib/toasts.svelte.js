// The short notes at the top of the screen ("Bob left", "Cara is back"). Each shows for a few
// seconds; no more than four at once (the oldest make way).
const SHOW_MS = 4500
const MAX = 4

export class Toasts {
  items = $state.raw([])

  #id = 0
  #timers = []

  // `list` is [{ text, kind }], see notices.js
  add = list => {
    for (const notice of list) {
      const id = ++this.#id
      this.items = [...this.items, { ...notice, id }].slice(-MAX)
      this.#timers.push(setTimeout(() => (this.items = this.items.filter(n => n.id !== id)), SHOW_MS))
    }
  }

  stop = () => this.#timers.forEach(clearTimeout)
}
