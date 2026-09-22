import { useState } from 'react'
import { supabase, configured } from '../lib/supabase'
import { Card, Toasts } from '../components/ui'
import { useGame } from '../lib/game'

export default function Auth() {
  const { toast } = useGame()
  const [mode, setMode] = useState<'in' | 'up'>('in')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [name, setName] = useState('')
  const [busy, setBusy] = useState(false)

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setBusy(true)
    try {
      if (mode === 'up') {
        if (name.trim().length < 3) throw new Error('Pick a name of at least 3 characters')
        const { error } = await supabase.auth.signUp({ email, password, options: { data: { name: name.trim() } } })
        if (error) throw error
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email, password })
        if (error) throw error
      }
    } catch (err) {
      toast((err as Error).message, 'bad')
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
          <div className="seg" style={{ marginBottom: 12 }}>
            <button className={mode === 'in' ? 'on' : ''} onClick={() => setMode('in')}>Existing Account</button>
            <button className={mode === 'up' ? 'on' : ''} onClick={() => setMode('up')}>New Player</button>
          </div>
          <form onSubmit={submit} className="stack">
            {mode === 'up' && (
              <label className="f">Street name
                <input className="input" value={name} onChange={e => setName(e.target.value)} maxLength={20} autoComplete="nickname" />
              </label>
            )}
            <label className="f">Email
              <input className="input" type="email" value={email} onChange={e => setEmail(e.target.value)} autoComplete="email" required />
            </label>
            <label className="f">Password
              <input className="input" type="password" value={password} onChange={e => setPassword(e.target.value)} autoComplete={mode === 'up' ? 'new-password' : 'current-password'} minLength={6} required />
            </label>
            <button className="btn doit block" disabled={busy} type="submit">{busy ? <span className="spin" /> : mode === 'up' ? 'Enter the City' : 'Sign In'}</button>
          </form>
        </div>
      </Card>
      <p className="muted small center">An unofficial fan reconstruction of SMLSD's 2009–2010 iPhone MMO.</p>
    </div>
  )
}
