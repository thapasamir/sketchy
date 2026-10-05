// Plain HTTP calls to the Phoenix JSON API (one request, one response).
import { loadUser } from './session.js'

export class ApiError extends Error {
  constructor(message, status) {
    super(message)
    this.status = status // undefined means the request never reached the server
  }
}

async function request(method, endpoint, body) {
  const headers = { 'content-type': 'application/json' }

  // Prove who we are: the server signed this token at login and is the only one who can.
  const token = loadUser()?.token
  if (token) headers.authorization = `Bearer ${token}`

  let res
  try {
    res = await fetch(endpoint, { method, headers, body: body && JSON.stringify(body) })
  } catch {
    throw new ApiError('Could not reach the server. Check your connection.')
  }

  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new ApiError(data.message || data.error || 'Request failed', res.status)

  return data
}

const post = (endpoint, body = {}) => request('POST', endpoint, body)

export const createGuestUser = () => post('/api/users/guest')
export const registerUser = (username, email, password) => post('/api/users/register', { username, email, password })
export const loginUser = (username, password) => post('/api/users/login', { username, password })
export const getMe = () => request('GET', '/api/users/me')

export const createRoom = (name, avatar) => post('/api/rooms', { name, avatar })
export const joinRoom = (code, name, avatar) => post(`/api/rooms/${encodeURIComponent(code)}/join`, { name, avatar })
