// How a conversation is laid out: messages from the same person close together form one group,
// shown as a run of bubbles with the name above the first and the time under the last.

// Messages by one person this close together (ms) belong to one group.
export const GROUP_GAP_MS = 2 * 60 * 1000

// Mark each message with `first` (it starts a group) and `last` (it ends one). Pure: returns new
// objects and leaves the messages alone.
export function groupMessages(messages, gap = GROUP_GAP_MS) {
  const together = (a, b) => !!a && !!b && a.player_id === b.player_id && Math.abs(b.at - a.at) <= gap
  return messages.map((message, i) => ({
    ...message,
    first: !together(messages[i - 1], message),
    last: !together(message, messages[i + 1]),
  }))
}

// "14:32": the time of day, as this person's own clock and language would show it
export function timeLabel(at, locale) {
  return new Date(at).toLocaleTimeString(locale, { hour: '2-digit', minute: '2-digit' })
}
