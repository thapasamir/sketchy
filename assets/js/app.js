import { mount } from "svelte"
import App from "./App.svelte"

// the words in index.html that search engines read before any script runs; the home page shows
// the same things itself
document.getElementById("seo-shell")?.remove()

mount(App, { target: document.body })
