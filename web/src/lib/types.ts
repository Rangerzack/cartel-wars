export type Commodity = 'herb' | 'dust' | 'pills'
export type SetupKind = 'offense' | 'defense' | 'jail'
export type ItemCategory = 'weapon' | 'jail_weapon' | 'protection' | 'transport'
export type HeatLevel = 'green' | 'yellow' | 'red'
export type Path = 'producer' | 'trader'

export interface Power { att: number; def: number; combo: boolean }

export interface InventoryItem {
  item_id: number; qty: number; name: string; category: ItemCategory
  att: number; def: number; capacity: number; price: number; combo_tag: string | null
}
export interface SetupItem {
  item_id: number; qty: number; name: string; category: ItemCategory
  att: number; def: number; combo_tag: string | null
}
export interface GrowHouse {
  id: string; commodity: Commodity; level: number; running: boolean; started_at: string | null
  rate: number; cap: number; produced: number; upgrade_cost: number
}
export interface HustlerTrip {
  id: string; commodity: Commodity; count: number; units: number; cash_due: number; returns_at: string; back: boolean
}
export interface MyListing { id: string; commodity: Commodity; qty: number; unit_price: number; expires_at: string; held: boolean }

export interface Me {
  id: string; name: string; created_at: string; avatar: string; bio: string; reputation: number
  cash: number; bank: number; diamonds: number
  stamina: number; stamina_max: number
  health: number; health_max: number
  heat: number; heat_max: number; heat_level: HeatLevel
  jailed: boolean; jail_until: string | null
  hospital: boolean
  health_next: string; health_bought: number
  rep_earned: number; path: Path | null; path_required: boolean
  immune: boolean; immune_until: string
  inventory_slots: number; storage_cap: number; refills_used: number
  actions_done: number; fights_won: number; fights_lost: number; market_volume: number; imports: number
  next_tick: string
  power: Record<SetupKind, Power>
  crew: {
    id: string; name: string; emblem: string; capo_id: string; is_capo: boolean; co_capo_id: string | null; is_co_capo: boolean
    cartel_id: string | null; members: number; applications: number; invites: number
  } | null
  cartel: { id: string; name: string; don_id: string; is_don: boolean } | null
  storage: Record<Commodity, number>
  storage_used: number
  prices: Record<Commodity, number>
  grow_houses: GrowHouse[]
  hustlers: HustlerTrip[]
  inventory: InventoryItem[]
  setups: Partial<Record<SetupKind, SetupItem[]>>
  hoodlums: Partial<Record<string, number>>
  transport_capacity: number
  listings: MyListing[]
  ribbons: Ribbon[]
  server_time: string
}

export interface ActionDef {
  id: number; name: string; description: string; stamina_cost: number; pay_min: number; pay_max: number
  pay_rep: number; heat_gain: number; cash_cost: number; requires_item: number | null; min_crew: number; is_jail: boolean
  effect: string | null; sort: number
}
export interface ItemDef {
  id: number; name: string; category: ItemCategory; att: number; def: number; capacity: number
  price: number; rep_price: number; combo_tag: string | null; sort: number
}
export interface CommodityDef {
  code: Commodity; name: string; base_price: number; hustler_units: number; refill_stamina: number
  refill_health: number; grow_rate: number; grow_cap: number; grow_price: number; sort: number
}
export interface HoodlumDef { code: string; name: string; att: number; def: number; intel: number; base_price: number }

export interface Catalog {
  actions: ActionDef[]
  items: ItemDef[]
  commodities: CommodityDef[]
  hoodlums: HoodlumDef[]
  config: Record<string, number>
}

export interface PlayerSummary {
  id: string; name: string; avatar: string; crew: { name: string; emblem: string } | null
  fights: number; fights_won: number; hospital: boolean; jailed: boolean; immune: boolean; last_seen: string
}
export interface PublicPlayer {
  id: string; name: string; created_at: string; avatar: string; bio: string; reputation: number; fights: number; fights_won: number; actions: number
  health: number; health_max: number; heat_level: HeatLevel; jailed: boolean; hospital: boolean; immune: boolean
  last_seen: string; ribbons: Ribbon[]; crew: { id: string; name: string; emblem: string } | null; cartel: { id: string; name: string } | null
}
export interface FightResult {
  won: boolean; damage_dealt: number; damage_taken: number; cash: number; their_health: number; my_health: number
  hospitalized_them: boolean; hospitalized_me: boolean; busted: boolean; my_att: number; their_def: number; dry: boolean
}
export interface FightLog {
  id: number; attacker: string; attacker_id: string; defender: string; defender_id: string
  attacker_dmg: number; defender_dmg: number; cash: number; won: boolean; i_attacked: boolean; at: string
}
export interface MarketListing {
  id: string; commodity: Commodity; qty: number; unit_price: number; seller: string; seller_id: string; mine: boolean; expires_at: string
}
export interface Market { prices: Record<Commodity, number>; listings: MarketListing[] }

export interface CrewSummary {
  id: string; name: string; emblem: string; description: string; members: number; blocks: number; cartel: string | null
}
export interface CrewDetail {
  id: string; name: string; emblem: string; description: string; capo_id: string; is_capo: boolean
  co_capo_id: string | null; is_co_capo: boolean; is_boss: boolean; created_at: string
  bank: number | null; cartel: { id: string; name: string; don_id: string } | null
  members: { id: string; name: string; avatar: string; fights_won: number; actions: number; is_capo: boolean; is_co_capo: boolean; last_seen: string }[]
  blocks: { id: number; name: string; hood: string; hood_id: number; island: string; bonus_at: string | null }[]
  applications: { id: string; name: string; at: string }[] | null
  applied: boolean
  invites: { id: string; name: string }[] | null
  power: { att: number; def: number }
  fights: CrewFight[]
  next_fight_at: string | null
}
export interface CrewFight {
  id: number; attacker: string; attacker_id: string; defender: string; defender_id: string
  won: boolean; attack: number; defense: number; cash: number; at: string; we_attacked: boolean
}
export interface CrewFightResult { won: boolean; attack: number; defense: number; cash: number; busted: boolean }
export interface CartelSummary { id: string; name: string; don: string; crews: number; blocks: number }
export interface CartelDetail {
  id: string; name: string; don_id: string; is_don: boolean; don: string; created_at: string; bank: number | null; member: boolean
  crews: { id: string; name: string; emblem: string; capo_id: string; capo: string; members: number; blocks: number; votes: number; my_vote: boolean }[]
  can_vote: boolean
}

export interface CrewRef { id: string; name: string; emblem: string }
export interface Block {
  id: number; slot: number; name: string; owner: CrewRef | null; mine: boolean; garrisoned: boolean; garrison_size: number | null
  garrison: Record<string, number> | null; bonus_at: string | null; my_wins: number; top_wins: number
}
export interface Hood {
  id: number; name: string; district: string; gx: number; gy: number; price: number; claim_price: number
  daily_income: number; block_bonus: number; base_resistance: number; my_blocks: number; owner: CrewRef | null; blocks: Block[]
}
export interface TerritoryRules { siege_wins: number; min_thugs: number; bonus_hours: number; stamina: number }
export interface Territory { hoods: Hood[]; rules: TerritoryRules }
export interface TerritoryLog {
  id: number; block_id: number; block: string; hood: string; hood_id: number; attacker: string | null; attacker_id: string | null
  crew: string | null; crew_emblem: string | null; defender_crew: string | null; success: boolean; captured: boolean
  attack: number; resistance: number; thugs: number; mercs: number; lost_thugs: number; lost_mercs: number
  garrison_lost: number; siege_wins: number | null; at: string
}
export interface BlockDetail {
  id: number; name: string; slot: number; hood_id: number; hood: string; district: string; gx: number; gy: number
  claim_price: number; block_bonus: number; base_resistance: number; bonus_at: string | null; taken_at: string | null; mine: boolean
  owner: CrewRef | null; garrisoned: boolean; garrison: Record<string, number> | null
  siege: { crew_id: string; crew: string; emblem: string; wins: number; mine: boolean; at: string }[]
  log: TerritoryLog[]
}
export interface AttackBlockResult {
  success: boolean; captured: boolean; attack: number; resistance: number; lost_thugs: number; lost_mercs: number
  garrison_lost: number; claim_paid: number; wins: number | null; wins_needed: number; bonus_reset: boolean
}
export interface LedgerEntry {
  id: number; kind: 'deposit' | 'withdraw' | 'bonus' | 'fight_won' | 'fight_lost'; amount: number; balance: number
  note: string; at: string; player: string | null; player_id: string | null
}

export interface Message { id: number; sender_id: string; sender_name: string; body: string; created_at: string }
export interface Conversation { channel: string; other_id: string; other: string; last: string; at: string }

export interface TopUsers {
  fighters: { id: string; name: string; value: number }[]
  hustlers: { id: string; name: string; value: number }[]
  traders: { id: string; name: string; value: number }[]
  crews: { id: string; name: string; emblem: string; value: number }[]
}

export type AccoladeKind = 'fight_win' | 'defense' | 'action' | 'import' | 'market' | 'turf' | 'gambler'
export interface Ribbon { kind: AccoladeKind; rank: number }
export interface AccoladeBoard { [kind: string]: { id: string; name: string; value: number }[] }
export interface Accolades { week_start: string; week_end: string; this_week: AccoladeBoard; last_week: AccoladeBoard; mine: Ribbon[] }

// casino
export interface SlotsResult { reels: string[]; mult: number; payout: number; net: number }
export type RouletteBetType = 'straight' | 'red' | 'black' | 'odd' | 'even' | 'low' | 'high' | 'dozen' | 'column'
export interface RouletteBet { type: RouletteBetType; value?: number; amount: number }
export interface RouletteResult {
  number: number; color: 'red' | 'black' | 'green'; wager: number; payout: number; net: number
  bets: (RouletteBet & { win: number })[]
}
export type CrapsBetKind = 'pass' | 'dont' | 'field' | 'place6' | 'place8' | 'any7' | 'anycraps'
export interface CrapsState { point: number | null; bets: Partial<Record<CrapsBetKind, number>>; last: CrapsLast | null }
export interface CrapsLast { dice: [number, number]; sum: number; log: { bet: CrapsBetKind; amount: number; result: 'win' | 'lose' | 'push' | 'stays'; win?: number }[] }
export interface CrapsRoll extends CrapsLast { point: number | null; bets: CrapsState['bets']; wager: number; payout: number; net: number }
export interface BlackjackState {
  status: 'none' | 'playing' | 'done'; wager: number; player: string[]; player_total: number; player_soft: boolean
  dealer: string[]; dealer_total: number; dealer_hidden: boolean; can_double: boolean
  result: { outcome: 'blackjack' | 'win' | 'push' | 'lose' | 'bust' | 'dealer_bust'; payout: number; net: number } | null
}
export interface PokerTableInfo {
  id: number; name: string; small_blind: number; big_blind: number; min_buyin: number; max_buyin: number; seats: number
  seated: number; players: string[]; mine: boolean
}
export interface PokerSeat {
  seat: number; name: string; avatar: string; stack: number; sitting_out: boolean; is_me: boolean; player_id: string
  in_hand: boolean; folded: boolean | null; all_in: boolean | null; street_bet: number | null; hole: string[] | null
  hand_name: string | null; won: number | null
}
export interface PokerHand {
  id: number; no: number; stage: 'preflop' | 'flop' | 'turn' | 'river' | 'done'; finished: boolean; board: string[]; pot: number
  dealer: number; to_act: number | null; current_bet: number; min_raise: number; deadline: string | null
  result: { won: Record<string, number>; hands: Record<string, string> | null; fold_out: boolean; rake: number } | null
  my: { hole: string[]; folded: boolean; all_in: boolean; street_bet: number; total_bet: number; to_call: number; min_raise_to: number; my_turn: boolean } | null
}
export interface PokerState {
  table: Omit<PokerTableInfo, 'seated' | 'players' | 'mine'>
  me: { seat: number; stack: number; sitting_out: boolean } | null
  hand: PokerHand | null
  seats: PokerSeat[]
  server_time: string
}
export interface CasinoHistory { net: number; recent: { game: string; wager: number; payout: number; net: number; at: string }[] }

// forum
export type ForumCategory = 'updates' | 'new_player' | 'market' | 'general' | 'war' | 'off_topic' | 'suggestions'
export interface ForumAuthor { id: string; name: string; avatar: string; is_admin: boolean; crew: { id: string; name: string; emblem: string } | null }
export interface ForumCategoryRow { key: ForumCategory; threads: number; posts: number; last_post_at: string | null; last: { id: number; title: string; last_poster: string | null } | null }
export interface ForumCategories { is_admin: boolean; categories: ForumCategoryRow[] }
export interface ForumThreadSummary {
  id: number; category: ForumCategory; title: string; snippet: string; author: ForumAuthor; pinned: boolean; locked: boolean
  reply_count: number; last_post_at: string; last_poster: string | null; created_at: string
}
export interface ForumList { category: ForumCategory; page: number; pages: number; total: number; is_admin: boolean; can_post: boolean; threads: ForumThreadSummary[] }
export interface ForumPost { id: number; author: ForumAuthor; body: string | null; deleted: boolean; created_at: string; edited_at: string | null; mine: boolean }
export interface ForumThread {
  thread: ForumThreadSummary & { body: string; edited_at: string | null; mine: boolean }
  is_admin: boolean; can_reply: boolean; page: number; pages: number; posts: ForumPost[]
}
