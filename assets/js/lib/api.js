// Plain HTTP calls to the Phoenix JSON API (one request, one response).

async function apiCall(endpoint, body) {
  const res = await fetch(endpoint, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  })

  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(data.message || data.error || 'Request failed')

  return data
}

export async function createGuestUser() {
  return apiCall('/api/users/guest', {})
}

export async function registerUser(username, email, password) {
  return apiCall('/api/users/register', { username, email, password })
}

export async function loginUser(username, password) {
  return apiCall('/api/users/login', { username, password })
}

export async function createRoom(name) {
  return apiCall('/api/rooms', { name })
}

export async function joinRoom(code, name) {
  return apiCall(`/api/rooms/${encodeURIComponent(code)}/join`, { name })
}
