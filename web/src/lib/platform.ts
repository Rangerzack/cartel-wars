import { Capacitor } from '@capacitor/core'

/** True inside the iOS app (served from capacitor://localhost), false in every browser. */
export const isNative = Capacitor.isNativePlatform()

/** The live web build. Links that leave the iOS app (auth emails) point here: Supabase only redirects to http(s) URLs on its allow list. */
export const WEB_URL = 'https://rangerzack.github.io/cartel-wars/'

/** Fired on window when the iOS app comes back to the foreground; GameProvider refreshes on it. */
export const RESUME_EVENT = 'cartelwars:resume'

/** Open a page outside the game: an in-app Safari sheet in the iOS app, a new tab on the web. */
export async function openExternal(url: string) {
  if (!isNative) { window.open(url, '_blank', 'noopener'); return }
  const { Browser } = await import('@capacitor/browser')
  await Browser.open({ url })
}
