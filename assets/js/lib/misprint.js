// The logo's two inks slide in opposite directions as the pointer moves (see Wordmark.svelte,
// which reads --mx/--my). Returns the function that stops it and puts the inks back in place.
export function trackMisprint() {
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return () => {}
  const root = document.documentElement
  function onMove(e) {
    const nx = (e.clientX / window.innerWidth - 0.5) * 2
    const ny = (e.clientY / window.innerHeight - 0.5) * 2
    root.style.setProperty('--mx', (nx * 7).toFixed(1) + 'px')
    root.style.setProperty('--my', (ny * 5).toFixed(1) + 'px')
  }
  window.addEventListener('pointermove', onMove)
  return () => {
    window.removeEventListener('pointermove', onMove)
    root.style.removeProperty('--mx')
    root.style.removeProperty('--my')
  }
}
