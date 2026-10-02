// Plain HTTP calls to the Phoenix JSON API (one request, one response).

export async function createRoom(name) {
  const res = await fetch('/api/rooms', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ name }),
  })

  const body = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(body.message || 'Could not create a room, please try again')

  return body // { code, player_id }
}
