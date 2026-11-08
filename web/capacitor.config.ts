import type { CapacitorConfig } from '@capacitor/cli'

// Native iOS shell (Apple guideline 4.2): the app ships its own build of web/dist, it never loads the Pages site.
// Build with BASE_PATH=/ (`npm run build:ios`) — inside the shell the app is served from capacitor://localhost/.
const config: CapacitorConfig = {
  appId: 'io.rangelab.cartelwars',
  appName: 'Thug Empire',
  webDir: 'dist',
  backgroundColor: '#0a1214',
  ios: {
    scheme: 'App',
    // Full-bleed web view: index.html sets viewport-fit=cover and index.css pads the top bar, tab bar, toasts and
    // modals with env(safe-area-inset-*). 'automatic' would inset the scroll view as well and double the gap.
    contentInset: 'never',
  },
  plugins: {
    SplashScreen: { launchAutoHide: true, backgroundColor: '#0a1214', showSpinner: false },
    StatusBar: { style: 'DARK', overlaysWebView: true },
    Keyboard: { resize: 'native', resizeOnFullScreen: true },
  },
}

export default config
