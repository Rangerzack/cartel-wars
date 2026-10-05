import { useState } from 'react'
import { supabase, configured } from '../lib/supabase'
import { Card, Toasts } from '../components/ui'
import { useGame } from '../lib/game'
import { errorText } from '../lib/errors'
import { resetRedirect } from '../components/Account'
import { api } from '../lib/api'
import { policyUrl, type PolicyPage } from '../lib/pages'
import { openExternal } from '../lib/platform'

/** A policy link: a real href for the web, an in-app Safari sheet in the iOS app. */
const Policy = ({ page, children }: { page: PolicyPage; children: string }) => (
  <a href={policyUrl(page)} target="_blank" rel="noopener" onClick={e => { e.preventDefault(); openExternal(policyUrl(page)) }}>{children}</a>
)

export default function Auth() {
  const { toast } = useGame()
  const [mode, setMode] = useState<'in' | 'up' | 'reset'>('in')
  const [sent, setSent] = useState(false)
  const [confirming, setConfirming] = useState(false)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [name, setName] = useState('')
  const [busy, setBusy] = useState(false)
  const [showPw, setShowPw] = useState(false)
  // the last error stays on the form above the button (the toast still pops, then goes) — P2-8
  const [why, setWhy] = useState<string | null>(null)
  const switchTo = (m: typeof mode) => { setMode(m); setWhy(null); if (m === 'reset') setSent(false) }

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setBusy(true)
    setWhy(null)
    try {
      if (mode === 'reset') {
        const { error } = await supabase.auth.resetPasswordForEmail(email, { redirectTo: resetRedirect() })
        if (error) throw error
        setSent(true)
      } else if (mode === 'up') {
        if (name.trim().length < 3) throw new Error('Pick a name of at least 3 characters')
        // ask before creating the account, so a taken or blocked name doesn't turn into a placeholder
        const chk = await api.checkName(name.trim()).catch(() => null)
        if (chk && !chk.ok) throw new Error(chk.why ?? 'Pick another name')
        const { data, error } = await supabase.auth.signUp({ email, password, options: { data: { name: name.trim() } } })
        if (error) throw error
        // email confirmation is on: no session until they open the link, which lands in the browser, not this app
        if (!data.session) { setMode('in'); setConfirming(true) }
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email, password })
        if (error) throw error
      }
    } catch (err) {
      const msg = errorText(err)
      setWhy(msg)
      toast(msg, 'bad')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="auth">
      <Toasts />
      <div className="logo">
        <h1>Cartel Wars</h1>
        <p>Produce. Move product. Hold the block.</p>
      </div>
      {!configured && (
        <div className="notice red">Supabase isn't configured. Copy <code>.env.example</code> to <code>.env</code> and set your project URL and anon key.</div>
      )}
      <Card>
        <div className="bd">
          {mode === 'reset' ? (
            <div className="stack" style={{ marginBottom: 12 }}>
              <b>Reset your password</b>
              <div className="small muted">{sent ? `Check your email. If ${email} has an account, a reset link is on its way. The link opens in your browser — set a new password there, then come back here and sign in.` : "Enter your account's email and we'll send you a link to set a new password."}</div>
            </div>
          ) : (
            <div className="seg" style={{ marginBottom: 12 }}>
              <button type="button" className={mode === 'in' ? 'on' : ''} aria-pressed={mode === 'in'} onClick={() => switchTo('in')}>Existing Account</button>
              <button type="button" className={mode === 'up' ? 'on' : ''} aria-pressed={mode === 'up'} onClick={() => switchTo('up')}>New Player</button>
            </div>
          )}
          {mode === 'in' && confirming && <div className="notice gold" style={{ marginBottom: 12 }}>Check your email to confirm your account. The link opens in your browser — then come back here and sign in.</div>}
          <form onSubmit={submit} className="stack">
            {mode === 'up' && (
              <div className="stack" style={{ gap: 4 }}>
                <label className="f">Street name
                  <input className="input" value={name} onChange={e => setName(e.target.value)} maxLength={20} autoComplete="nickname" aria-describedby="name-rule" />
                </label>
                {/* the rule in _name_problem() (20261004000006_moderation.sql): 3 to 20 characters, then not reserved, filtered or taken */}
                <span id="name-rule" className="small muted">3–20 characters. Spaces and symbols are fine.</span>
              </div>
            )}
            <label className="f">Email
              <input className="input" type="email" value={email} onChange={e => setEmail(e.target.value)} autoComplete="email" required />
            </label>
            {mode !== 'reset' && (
              // the Show toggle sits over the field's right end but outside the label, so the field is still just "Password"
              <div className="pw-field">
                <label className="f">Password
                  <input id="pw" className="input" type={showPw ? 'text' : 'password'} value={password} onChange={e => setPassword(e.target.value)} autoComplete={mode === 'up' ? 'new-password' : 'current-password'} minLength={6} required />
                </label>
                <button type="button" className="pw-toggle" aria-pressed={showPw} aria-controls="pw" onClick={() => setShowPw(v => !v)}>Show</button>
              </div>
            )}
            {why && <div className="why">{why}</div>}
            <button className="btn doit block" disabled={busy || (mode === 'reset' && sent)} type="submit">{busy ? <span className="spin" role="img" aria-label="Working" /> : mode === 'up' ? 'Enter the City' : mode === 'reset' ? (sent ? 'Link Sent' : 'Send Reset Link') : 'Sign In'}</button>
          </form>
          <div className="center" style={{ marginTop: 10 }}>
            {mode === 'in' && <button type="button" className="linkbtn small" onClick={() => switchTo('reset')}>Forgot your password?</button>}
            {mode === 'reset' && <button type="button" className="linkbtn small" onClick={() => switchTo('in')}>‹ Back to sign in</button>}
            {mode === 'up' && <div className="small muted">By entering the city you agree to the <Policy page="terms">Terms of Service</Policy> and <Policy page="privacy">Privacy Policy</Policy>.</div>}
          </div>
        </div>
      </Card>
    </div>
  )
}
