import { useState } from 'react'
import { supabase } from '../lib/supabase'
import { api } from '../lib/api'
import { useGame } from '../lib/game'
import { isNative, WEB_URL } from '../lib/platform'
import { Btn, Card, Modal, Toasts } from './ui'

/** Where password-reset emails send people back to: this build's own address (live or staging).
 *  The iOS app's origin is capacitor://localhost, which Supabase won't redirect to, so its links open the live web app. */
export const resetRedirect = () => isNative ? WEB_URL : `${window.location.origin}${import.meta.env.BASE_URL}`

function NewPasswordFields({ onDone, submitLabel }: { onDone: () => void; submitLabel: string }) {
  const { toast } = useGame()
  const [pw, setPw] = useState('')
  const [pw2, setPw2] = useState('')
  const [saving, setSaving] = useState(false)
  const bad = pw.length > 0 && pw.length < 6 ? 'At least 6 characters' : pw2.length > 0 && pw !== pw2 ? "Passwords don't match" : null
  return (
    <form className="stack" onSubmit={async e => {
      e.preventDefault()
      if (bad || !pw || saving) return
      setSaving(true)
      try {
        const { error } = await supabase.auth.updateUser({ password: pw })
        if (error) { toast(error.message, 'bad'); return }
        toast('Password updated', 'ok'); setPw(''); setPw2(''); onDone()
      } finally { setSaving(false) }
    }}>
      <label className="f">New password<input className="input" type="password" autoComplete="new-password" minLength={6} value={pw} onChange={e => setPw(e.target.value)} /></label>
      <label className="f">Confirm new password<input className="input" type="password" autoComplete="new-password" value={pw2} onChange={e => setPw2(e.target.value)} /></label>
      {bad && <div className="small red">{bad}</div>}
      <button className="btn gold block" type="submit" disabled={!!bad || !pw || pw !== pw2 || saving}>{saving ? <span className="spin" role="img" aria-label="Working" /> : submitLabel}</button>
    </form>
  )
}

/** Account card on the Profile page: email, change password, sign out, delete the account. */
export function AccountCard({ onSignedOut }: { onSignedOut: () => void }) {
  const { session, signOut } = useGame()
  const [changing, setChanging] = useState(false)
  const [deleting, setDeleting] = useState(false)
  return (
    <Card title="Account" right={<small>{session?.user.email}</small>}>
      <div className="bd stack">
        {changing
          ? <><NewPasswordFields submitLabel="Save New Password" onDone={() => setChanging(false)} /><button className="btn sm ghost" onClick={() => setChanging(false)}>Cancel</button></>
          : <div className="grid2">
              <button className="btn" onClick={() => setChanging(true)}>Change Password</button>
              {/* no "are you sure": signing out loses nothing, and it's two screens deep (Phase 3) */}
              <Btn className="ghost" onClick={async () => { await signOut(); onSignedOut() }}>Sign Out</Btn>
            </div>}
        <button className="btn sm ghost red" onClick={() => setDeleting(true)}>Delete Account</button>
      </div>
      {deleting && <DeleteAccount onClose={() => setDeleting(false)} onDeleted={onSignedOut} />}
    </Card>
  )
}

/** Apple guideline 5.1.1(v): an app that makes accounts lets people delete them in the app. Typing the street name
 *  (any case) is the confirmation; the server checks it again. */
function DeleteAccount({ onClose, onDeleted }: { onClose: () => void; onDeleted: () => void }) {
  const { me, signOut, toast } = useGame()
  const [typed, setTyped] = useState('')
  const matches = !!me && typed.trim().toLowerCase() === me.name.trim().toLowerCase()
  return (
    <Modal title="Delete your account" onClose={onClose}>
      <div className="stack">
        <ul className="small points">
          <li>Everything you built is gone for good: cash, bank, diamonds, gear, product, grow houses and hoodlums. Purchases can't be refunded.</li>
          <li>Your chat messages, DMs and forum posts are deleted, and so are threads you started.</li>
          <li>If you run a crew, your Co-Capo takes over, or else the longest-standing member. A crew of one disbands. Crew and cartel banks stay where they are.</li>
          <li>Game history other players see, like fights, trades and their activity feed, stays without your name.</li>
          <li>Deleting your account doesn't cancel the Daily Drop or any other Apple subscription. Cancel those in your device settings.</li>
        </ul>
        <label className="f">Type your street name to confirm
          <input className="input" value={typed} onChange={e => setTyped(e.target.value)} placeholder={me?.name} autoComplete="off" autoCapitalize="off" autoCorrect="off" spellCheck={false} />
        </label>
        <Btn className="red block" disabled={!matches} onClick={async () => {
          try { await api.deleteAccount(typed) } catch (e) { toast((e as Error).message, 'bad'); return }
          await signOut()
          toast('Your account is deleted', 'ok')
          onDeleted()
        }}>Delete forever</Btn>
      </div>
    </Modal>
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
          <NewPasswordFields submitLabel="Save and Enter the City" onDone={endRecovery} />
          <button className="btn sm ghost" onClick={async () => { await signOut(); endRecovery() }}>Cancel</button>
        </div>
      </Card>
    </div>
  )
}
