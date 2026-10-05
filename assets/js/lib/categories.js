// The categories as the host has set them: 'all', or a list. As a list, always.
export const chosenCategories = (setting, everything) => (setting === 'all' ? everything : setting)

// What tapping a category does. While everything is chosen, tapping one means "just this one"
// (starting from all sixteen and unticking fifteen would be tedious); after that, tapping adds or
// removes it. At least one always stays chosen, and choosing them all is the same as 'all'.
// Returns the new setting, or null for no change.
export function tapCategory(setting, everything, name) {
  if (setting === 'all') return [name]
  const next = setting.includes(name) ? setting.filter(c => c !== name) : [...setting, name]
  if (next.length === 0) return null
  return next.length === everything.length ? 'all' : next
}
