import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import '@fontsource/oswald/latin-500.css'
import '@fontsource/oswald/latin-600.css'
import '@fontsource/oswald/latin-700.css'
import './index.css'
import App from './App'
import { startNative } from './lib/native'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
// After React's first paint, so the launch splash lifts onto the app rather than a blank web view. No-op on the web.
requestAnimationFrame(() => setTimeout(() => { void startNative() }))
