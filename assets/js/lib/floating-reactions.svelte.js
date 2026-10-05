// Emoji reactions on screen. Like chat they are only relayed: each one floats for a moment and is
// dropped. (Which names are allowed, and how they are placed, is in reactions.js.)
import { show, SHOW_MS } from './reactions.js'

export class FloatingReactions {
  items = $state.raw([])

  #key = 0
  #timers = []
  #channel

  constructor(channel) {
    this.#channel = channel
  }

  receive = event => {
    const before = this.items
    this.items = show(this.items, event, ++this.#key)
    if (this.items === before) return
    const key = this.#key
    this.#timers.push(setTimeout(() => (this.items = this.items.filter(r => r.key !== key)), SHOW_MS))
  }

  // refused ones (too fast, closed) are simply not shown: nothing to tell the person
  send = id => this.#channel()?.push('react', { id })

  stop = () => this.#timers.forEach(clearTimeout)
}
