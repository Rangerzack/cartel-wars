import { isNative, RESUME_EVENT } from './platform'

/** iOS app setup, called once from main.tsx after the first paint. The plugins are dynamic imports so the web build never loads them. */
export async function startNative() {
  if (!isNative) return
  const [{ SplashScreen }, { StatusBar, Style }, { App }, { Keyboard }] = await Promise.all([
    import('@capacitor/splash-screen'), import('@capacitor/status-bar'), import('@capacitor/app'), import('@capacitor/keyboard'),
  ])
  await SplashScreen.hide()
  // Light text: the web view runs under the status bar and the top bar behind it is dark (index.css pads it with safe-area-inset-top).
  await StatusBar.setStyle({ style: Style.Dark })
  // Back from the background: refetch now instead of waiting for the minute poll.
  await App.addListener('appStateChange', ({ isActive }) => { if (isActive) window.dispatchEvent(new Event(RESUME_EVENT)) })
  // The keyboard shrinks the web view (resize: native), which would lift the tab bar on top of it; .kb hides it while typing.
  await Keyboard.addListener('keyboardWillShow', () => document.documentElement.classList.add('kb'))
  await Keyboard.addListener('keyboardWillHide', () => document.documentElement.classList.remove('kb'))
}
