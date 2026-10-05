import { isNative } from './platform'

/**
 * A tap you feel, in the iPhone app only (the web has nothing to call on iOS Safari). Kept to outcomes, never to every
 * press (Apple: haptics should mean something): a job paid, a hand or a fight won or lost, a crate cracked, a bust, a
 * refusal. The plugin loads on first use, and a failure is silent: a missing buzz must never break the action.
 *
 *  - light: a job paid, a chip placed on a win line
 *  - medium: a crate opens, a turf hit lands
 *  - success / warning / error: the system's notification patterns for a win, a bust, a refusal
 */
export type Haptic = 'light' | 'medium' | 'success' | 'warning' | 'error'

type Plugin = typeof import('@capacitor/haptics')
let plugin: Promise<Plugin> | null = null

export function haptic(kind: Haptic) {
  if (!isNative) return
  plugin ??= import('@capacitor/haptics')
  plugin.then(({ Haptics, ImpactStyle, NotificationType }) => {
    if (kind === 'light') return Haptics.impact({ style: ImpactStyle.Light })
    if (kind === 'medium') return Haptics.impact({ style: ImpactStyle.Medium })
    return Haptics.notification({ type: kind === 'success' ? NotificationType.Success : kind === 'warning' ? NotificationType.Warning : NotificationType.Error })
  }).catch(() => {})
}
