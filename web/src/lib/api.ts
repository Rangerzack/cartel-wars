import { supabase } from './supabase'
import type {
  CartelDetail, CartelSummary, Catalog, Conversation, CrewDetail, CrewFightResult, CrewSummary, FightLog, FightResult, Island,
  Accolades, Market, Me, Message, PlayerSummary, PublicPlayer, SetupKind, TerritoryLog, TopUsers,
  BlackjackState, CasinoHistory, CrapsBetKind, CrapsRoll, CrapsState, PokerState, PokerTableInfo, RouletteBet, RouletteResult, SlotsResult,
} from './types'

export class GameError extends Error {}

async function rpc<T>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw new GameError(error.message)
  return data as T
}

export const api = {
  // state
  me: () => rpc<Me>('get_me'),
  ensureProfile: (wanted?: string) => rpc<Me>('ensure_profile', { wanted: wanted ?? null }),
  catalog: () => rpc<Catalog>('get_catalog'),
  updateProfile: (avatar: string | null, bio: string | null) => rpc<{ ok: boolean }>('update_profile', { avatar, bio }),

  // actions
  doAction: (action_id: number) => rpc<{ pay: number; rep: number; busted: boolean; heat: number; stamina: number; cash: number }>('do_action', { action_id }),

  // fights
  attack: (target: string) => rpc<FightResult>('attack', { target }),
  fights: (limit_n = 30) => rpc<FightLog[]>('get_fights', { limit_n }),
  player: (pid: string) => rpc<PublicPlayer>('get_player', { pid }),
  findPlayers: (q = '', limit_n = 40) => rpc<PlayerSummary[]>('find_players', { q, limit_n }),
  topUsers: () => rpc<TopUsers>('top_users'),
  accolades: () => rpc<Accolades>('get_accolades'),

  // services
  hospitalCheckout: () => rpc<{ cost: number }>('hospital_checkout'),
  bribePolice: (points: number) => rpc<{ cost: number; heat: number }>('bribe_police', { points }),
  bailOut: () => rpc<{ cost: number }>('bail_out'),
  refill: (kind: 'stamina' | 'health', method: string) => rpc<{ gain: number }>('refill', { kind, method }),
  upgradeStat: (kind: 'stamina' | 'health' | 'slots') => rpc<{ cost: number }>('upgrade_stat', { kind }),
  bankDeposit: (amount: number) => rpc<{ bank: number }>('bank_deposit', { amount }),
  bankWithdraw: (amount: number) => rpc<{ bank: number }>('bank_withdraw', { amount }),
  sendCash: (target: string, amount: number) => rpc<{ sent: number }>('send_cash', { target, amount }),
  sendDiamonds: (target: string, n: number) => rpc<{ sent: number }>('send_diamonds', { target, n }),

  // items
  buyItem: (item: number, n = 1) => rpc<{ cost: number }>('buy_item', { item, n }),
  sellItem: (item: number, n = 1) => rpc<{ refund: number }>('sell_item', { item, n }),
  equip: (s: SetupKind, item: number, n: number) => rpc<{ qty: number }>('equip', { s, item, n }),

  // production
  growBuild: (commodity: string) => rpc<{ cost: number; diamonds: number }>('grow_build', { commodity }),
  growToggle: (house: string) => rpc<{ running: boolean }>('grow_toggle', { house }),
  growCollect: (house: string) => rpc<{ collected: number; left: number }>('grow_collect', { house }),
  growUpgrade: (house: string) => rpc<{ cost: number; level: number }>('grow_upgrade', { house }),
  growAbandon: (house: string) => rpc<{ ok: boolean }>('grow_abandon', { house }),
  storageUpgrade: () => rpc<{ cost: number; storage_cap: number }>('storage_upgrade'),
  hireHustlers: (commodity: string, n: number) => rpc<{ units: number; cash_due: number; cost: number }>('hire_hustlers', { commodity, n }),
  collectHustlers: () => rpc<{ cash: number; units: number }>('collect_hustlers'),

  // market
  market: (commodity?: string) => rpc<Market>('get_market', { commodity: commodity ?? null }),
  listProduct: (commodity: string, n: number, unit_price: number) => rpc<{ id: string }>('list_product', { commodity, n, unit_price }),
  cancelListing: (listing: string) => rpc<{ returned: number; held: number }>('cancel_listing', { listing }),
  buyListing: (listing: string, n: number) => rpc<{ cost: number; units: number }>('buy_listing', { listing, n }),

  // crews
  crewCreate: (nm: string, emblem: string, description: string) => rpc<{ id: string }>('crew_create', { nm, emblem, description }),
  crewUpdate: (emblem: string, description: string) => rpc<{ ok: boolean }>('crew_update', { emblem, description }),
  listCrews: (q = '') => rpc<CrewSummary[]>('list_crews', { q }),
  crew: (cid: string) => rpc<CrewDetail>('get_crew', { cid }),
  crewApply: (cid: string) => rpc<{ ok: boolean }>('crew_apply', { cid }),
  crewWithdraw: (cid: string) => rpc<{ ok: boolean }>('crew_withdraw', { cid }),
  crewDecide: (pid: string, accept: boolean) => rpc<{ ok: boolean }>('crew_decide', { pid, accept }),
  crewKick: (pid: string) => rpc<{ ok: boolean }>('crew_kick', { pid }),
  crewLeave: () => rpc<{ ok: boolean }>('crew_leave'),
  crewBank: (amount: number) => rpc<{ bank: number }>('crew_bank', { amount }),
  crewFight: (target: string) => rpc<CrewFightResult>('crew_fight', { target }),

  // cartels
  cartelCreate: (nm: string) => rpc<{ id: string }>('cartel_create', { nm }),
  listCartels: () => rpc<CartelSummary[]>('list_cartels'),
  cartel: (cid: string) => rpc<CartelDetail>('get_cartel', { cid }),
  cartelInvite: (crew: string) => rpc<{ ok: boolean }>('cartel_invite', { crew }),
  cartelAccept: (cartel: string, accept = true) => rpc<{ ok: boolean }>('cartel_accept', { cartel, accept }),
  cartelLeave: () => rpc<{ ok: boolean }>('cartel_leave'),
  cartelBank: (amount: number) => rpc<{ bank: number }>('cartel_bank', { amount }),
  cartelVoteDon: (candidate: string) => rpc<{ elected: boolean; votes?: number; needed?: number }>('cartel_vote_don', { candidate }),

  // territory
  territory: () => rpc<Island[]>('get_territory'),
  territoryLog: (limit_n = 30) => rpc<TerritoryLog[]>('get_territory_log', { limit_n }),
  buyHoodlums: (kind: string, n: number) => rpc<{ cost: number }>('buy_hoodlums', { kind, n }),
  stationHoodlums: (block: number, kind: string, n: number) => rpc<{ ok: boolean }>('station_hoodlums', { block, kind, n }),
  withdrawGarrison: (block: number, kind: string, n: number) => rpc<{ ok: boolean }>('withdraw_garrison', { block, kind, n }),
  spyBlock: (block: number) => rpc<{ garrison: Record<string, number>; resistance: number }>('spy_block', { block }),
  attackBlock: (block: number, thugs: number, mercs: number) =>
    rpc<{ success: boolean; attack: number; resistance: number; lost_thugs: number; lost_mercs: number; claim_paid: number }>('attack_block', { block, thugs, mercs }),

  // chat
  messages: (channel: string, limit_n = 50) => rpc<Message[]>('get_messages', { channel, limit_n }),
  sendMessage: (channel: string, body: string) => rpc<{ id: number }>('send_message', { channel, body }),
  conversations: () => rpc<Conversation[]>('get_conversations'),
  dmChannel: (other: string) => rpc<string>('dm_channel', { other }),

  // casino
  slotsSpin: (wager: number) => rpc<SlotsResult>('slots_spin', { wager }),
  rouletteSpin: (bets: RouletteBet[]) => rpc<RouletteResult>('roulette_spin', { bets }),
  crapsState: () => rpc<CrapsState>('craps_state'),
  crapsBet: (kind: CrapsBetKind, amount: number) => rpc<CrapsState>('craps_bet', { kind, amount }),
  crapsRoll: () => rpc<CrapsRoll>('craps_roll'),
  crapsClear: () => rpc<CrapsState>('craps_clear'),
  blackjackState: () => rpc<BlackjackState>('blackjack_state'),
  blackjackDeal: (wager: number) => rpc<BlackjackState>('blackjack_deal', { wager }),
  blackjackAction: (action: 'hit' | 'stand' | 'double') => rpc<BlackjackState>('blackjack_action', { action }),
  pokerLobby: () => rpc<PokerTableInfo[]>('poker_lobby'),
  pokerJoin: (tid: number, seat_no: number, buyin: number) => rpc<PokerState>('poker_join', { tid, seat_no, buyin }),
  pokerLeave: () => rpc<{ cashed_out: number }>('poker_leave'),
  pokerSitIn: () => rpc<PokerState>('poker_sit_in'),
  pokerAct: (action: 'fold' | 'check' | 'call' | 'bet' | 'raise', amount?: number) => rpc<PokerState>('poker_act', { action, amount: amount ?? null }),
  pokerState: (tid: number) => rpc<PokerState>('poker_state', { tid }),
  casinoHistory: (limit_n = 30) => rpc<CasinoHistory>('casino_history', { limit_n }),
}
