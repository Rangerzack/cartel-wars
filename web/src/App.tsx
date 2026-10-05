import { lazy, useEffect } from 'react'
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { GameProvider, useGame } from './lib/game'
import Layout from './components/Layout'
import Auth from './pages/Auth'
import Home from './pages/Home'
import { features } from './lib/features'
import { Toasts } from './components/ui'
import { SetNewPassword } from './components/Account'

// Home is in the first download; every other screen is its own file, fetched when it's first opened and fetched ahead
// in the background once the city has loaded (prefetch below), so a tap on a tab, Items or the Casino doesn't wait on
// the network. The first download was 780 kB of script (Phase 5).
const pages = {
  Actions: () => import('./pages/Actions'),
  Economy: () => import('./pages/Economy'),
  Fight: () => import('./pages/Fight'),
  Services: () => import('./pages/Services'),
  Chat: () => import('./pages/Chat'),
  Player: () => import('./pages/Player'),
  Items: () => import('./pages/Items'),
  Crew: () => import('./pages/Crew'),
  Cartel: () => import('./pages/Cartel'),
  Territory: () => import('./pages/Territory'),
  Profile: () => import('./pages/Profile'),
  Accolades: () => import('./pages/Accolades'),
  Activity: () => import('./pages/Activity'),
  Casino: () => import('./pages/Casino'),
  PokerTable: () => import('./pages/PokerTable'),
  Forum: () => import('./pages/Forum'),
  Admin: () => import('./pages/Admin'),
  Store: () => import('./pages/Store'),
}
const Actions = lazy(pages.Actions)
const Economy = lazy(pages.Economy)
const Fight = lazy(pages.Fight)
const Services = lazy(pages.Services)
const Chat = lazy(pages.Chat)
const Player = lazy(pages.Player)
const Items = lazy(pages.Items)
const Crew = lazy(pages.Crew)
const Cartel = lazy(pages.Cartel)
const Territory = lazy(pages.Territory)
const Profile = lazy(pages.Profile)
const Accolades = lazy(pages.Accolades)
const Activity = lazy(pages.Activity)
const Casino = lazy(pages.Casino)
const PokerTable = lazy(pages.PokerTable)
const Forum = lazy(pages.Forum)
const Admin = lazy(pages.Admin)
const Store = lazy(pages.Store)
let prefetched = false
/** Fetch the other screens while nothing else is going on, so opening one later is instant. */
function prefetch() {
  if (prefetched) return
  prefetched = true
  // every screen fetched fine: a later deploy may reload the app once more (components/ScreenBoundary)
  const go = () => Promise.all(Object.values(pages).map(load => load()))
    .then(() => { try { sessionStorage.removeItem('cw.reloadedForUpdate') } catch { /* private mode */ } }).catch(() => {})
  const idle = (window as Window & { requestIdleCallback?: (cb: () => void) => void }).requestIdleCallback
  if (idle) idle(go); else setTimeout(go, 1500)
}

function Gate() {
  const { session, authReady, me, recovery } = useGame()
  const inCity = !!me
  useEffect(() => { if (inCity) prefetch() }, [inCity])
  // the same quiet spinner from launch to the city: no bare "Loading…" line first (Phase 5)
  if (!authReady) return <div className="app"><div className="empty"><span className="spin" role="status" aria-label="Loading" /></div></div>
  if (recovery && session) return <SetNewPassword />
  if (!session) return <Auth />
  if (!me) return <div className="app"><Toasts /><div className="empty"><span className="spin" aria-hidden /> Entering the city…</div></div>
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route path="/" element={<Home />} />
        <Route path="/actions" element={<Actions />} />
        <Route path="/economy" element={<Economy />} />
        <Route path="/fight" element={<Fight />} />
        <Route path="/player/:id" element={<Player />} />
        <Route path="/services" element={<Services />} />
        <Route path="/items" element={<Items />} />
        <Route path="/crew" element={<Crew />} />
        <Route path="/crew/:id" element={<Crew />} />
        <Route path="/cartel" element={<Cartel />} />
        <Route path="/cartel/:id" element={<Cartel />} />
        <Route path="/territory" element={<Territory />} />
        <Route path="/chat" element={<Chat />} />
        <Route path="/chat/:channel" element={<Chat />} />
        <Route path="/profile" element={<Profile />} />
        <Route path="/admin" element={<Admin />} />
        <Route path="/accolades" element={<Accolades />} />
        <Route path="/activity" element={<Activity />} />
        <Route path="/store" element={<Store />} />
        <Route path="/casino" element={<Casino />} />
        {features.casinoGames.length > 1 && <Route path="/casino/table/:id" element={<PokerTable />} />}
        <Route path="/casino/:game" element={<Casino />} />
        {features.forum && <Route path="/forum" element={<Forum />} />}
        {features.forum && <Route path="/forum/t/:id" element={<Forum />} />}
        {features.forum && <Route path="/forum/:cat" element={<Forum />} />}
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  )
}

export default function App() {
  return (
    <GameProvider>
      <BrowserRouter basename={import.meta.env.BASE_URL.replace(/\/$/, '')}>
        <Gate />
      </BrowserRouter>
    </GameProvider>
  )
}
