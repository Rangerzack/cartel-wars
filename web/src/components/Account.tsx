import { useState } from 'react'
import { supabase } from '../lib/supabase'
import { useGame } from '../lib/game'
import { Btn, Card, Toasts } from './ui'

/** Where password-reset emails send people back to: this build's own address (live or staging). */
export const resetRedirect = () => `${window.location.origin}${import.meta.env.BASE_URL}`

function NewPasswordFields({ onDone, submitLabel }: { onDone: () => void; submitLabel: string }) {
  const { toast } = useGame()
  const [pw, setPw] = useState('')
  const [pw2, setPw2] = useState('')
  const bad = pw.length > 0 && pw.length < 6 ? 'At least 6 characters' : pw2.length > 0 && pw !== pw2 ? "Passwords don't match" : null
  return (
    <form className="stack" onSubmit={async e => {
      e.preventDefault()
      if (bad || !pw) return
      const { error } = await supabase.auth.updateUser({ password: pw })
      if (error) { toast(error.message, 'bad'); return }
      toast('Password updated', 'ok'); setPw(''); setPw2(''); onDone()
    }}>
      <label className="f">New password<input className="input" type="password" autoComplete="new-password" minLength={6} value={pw} onChange={e => setPw(e.target.value)} /></label>
      <label className="f">Confirm new password<input className="input" type="password" autoComplete="new-password" value={pw2} onChange={e => setPw2(e.target.value)} /></label>
      {bad && <div className="small red">{bad}</div>}
      <button className="btn gold block" type="submit" disabled={!!bad || !pw || pw !== pw2}>{submitLabel}</button>
    </form>
  )
}

/** Account card on the Profile page: email, change password, sign out. */
export function AccountCard({ onSignedOut }: { onSignedOut: () => void }) {
  const { session, signOut } = useGame()
  const [changing, setChanging] = useState(false)
  return (
    <Card title="Account" right={<small>{session?.user.email}</small>}>
      <div className="bd stack">
        {changing
          ? <><NewPasswordFields submitLabel="Save new password" onDone={() => setChanging(false)} /><button className="btn sm ghost" onClick={() => setChanging(false)}>Cancel</button></>
          : <div className="grid2">
              <button className="btn" onClick={() => setChanging(true)}>Change password</button>
              <Btn className="ghost red" onClick={async () => { if (confirm('Sign out of Cartel Wars on this device?')) { await signOut(); onSignedOut() } }}>Sign out</Btn>
            </div>}
      </div>
    </Card>
  )
}

/** Full-screen step shown after opening a password-reset link. */
export function SetNewPassword() {
  const { endRecovery, signOut } = useGame()
  return (
    <div className="auth">
      <Toasts />
      <div className="logo"><h1>Cartel Wars</h1><p>Set a new password</p></div>
      <Card>
        <div className="bd stack">
          <div className="small muted">You opened a password reset link. Pick a new password to get back in.</div>
          <NewPasswordFields submitLabel="Save and enter the city" onDone={endRecovery} />
          <button className="btn sm ghost" onClick={async () => { await signOut(); endRecovery() }}>Cancel</button>
        </div>
      </Card>
    </div>
  )
}
