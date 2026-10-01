/** Smooth scrolling, unless the player asked the system for reduced motion (then it jumps). */
export const scrollBehavior = (): ScrollBehavior =>
  typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth'

/** Deep links (/services?focus=bank, /store#drop): scroll the card with that id under the top bar and ring it once. */
export function focusCard(id: string): boolean {
  const el = document.getElementById(id)
  if (!el) return false
  el.scrollIntoView({ behavior: scrollBehavior(), block: 'start' })
  el.classList.remove('focused'); void el.offsetWidth; el.classList.add('focused')
  return true
}
