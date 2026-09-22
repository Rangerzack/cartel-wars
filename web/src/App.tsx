import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { GameProvider, useGame } from './lib/game'
import Layout from './components/Layout'
import Auth from './pages/Auth'
import Home from './pages/Home'
import Actions from './pages/Actions'
import Economy from './pages/Economy'
import Fight from './pages/Fight'
import Player from './pages/Player'
import Services from './pages/Services'
import Items from './pages/Items'
import Crew from './pages/Crew'
import Cartel from './pages/Cartel'
import Territory from './pages/Territory'
import Chat from './pages/Chat'
import Profile from './pages/Profile'
import Accolades from './pages/Accolades'
import Casino from './pages/Casino'
import PokerTable from './pages/PokerTable'
import Forum from './pages/Forum'
import { features } from './lib/features'
import { Toasts } from './components/ui'

function Gate() {
  const { session, authReady, me } = useGame()
  if (!authReady) return <div className="empty">Loading…</div>
  if (!session) return <Auth />
  if (!me) return <div className="app"><Toasts /><div className="empty"><span className="spin" /> Entering the city…</div></div>
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
        <Route path="/accolades" element={<Accolades />} />
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
