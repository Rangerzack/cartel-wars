import { isNative, WEB_URL } from './platform'

export type PolicyPage = 'support' | 'privacy' | 'terms'

/** Where a policy page lives: next to the app on the web; on the live site from the iOS app (capacitor://localhost can't be opened by Safari). */
export const policyUrl = (page: PolicyPage) => `${isNative ? WEB_URL : import.meta.env.BASE_URL}${page}.html`
