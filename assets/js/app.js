import { mount } from "svelte"
import { Socket } from "phoenix"
import App from "./App.svelte"

mount(App, { target: document.body })

// Phoenix Channels connection (used once the room channel exists)
export const socket = new Socket("/socket", { params: {} })
