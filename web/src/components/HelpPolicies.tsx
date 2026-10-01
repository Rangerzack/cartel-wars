import { Card } from './ui'
import { policyUrl, type PolicyPage } from '../lib/pages'
import { openExternal } from '../lib/platform'

const pages: [PolicyPage, string][] = [['support', 'Support'], ['privacy', 'Privacy policy'], ['terms', 'Terms of service']]

/** Help & policies card on the Profile page. Apple wants the privacy policy reachable inside the app (5.1.1(i)), contact
 *  details published (1.2) and the subscription terms linkable (3.1.2). The pages are static files in web/public, served
 *  next to the app under the same base path; the iOS app opens the live site's copies in an in-app Safari sheet. */
export function HelpPolicies() {
  return (
    <Card title="Help & policies">
      {pages.map(([page, label]) => (
        <a key={page} className="row link" href={policyUrl(page)} target="_blank" rel="noopener" style={{ color: 'inherit' }}
           onClick={e => { e.preventDefault(); openExternal(policyUrl(page)) }}>
          <div className="grow t">{label}</div><span className="chev">›</span>
        </a>
      ))}
      <div className="bd small muted"><a href="mailto:support@rangelab.io" style={{ color: 'inherit' }}>support@rangelab.io</a></div>
    </Card>
  )
}
