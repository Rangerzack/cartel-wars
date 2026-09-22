export type Commodity = 'herb' | 'dust' | 'pills'
export type SetupKind = 'offense' | 'defense' | 'jail'
export type ItemCategory = 'weapon' | 'jail_weapon' | 'protection' | 'transport'
export type HeatLevel = 'green' | 'yellow' | 'red'

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
  immune: boolean; immune_until: string
  inventory_slots: number; storage_cap: number; refills_used: number
  actions_done: number; fights_won: number; fights_lost: number; market_volume: number; imports: number
  next_tick: string
  power: Record<SetupKind, Power>
  crew: { id: string; name: string; emblem: string; capo_id: string; is_capo: boolean; cartel_id: string | null; members: number; applications: number; invites: number } | null
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
  id: string; name: string; emblem: string; description: string; capo_id: string; is_capo: boolean; created_at: string
  bank: number | null; cartel: { id: string; name: string; don_id: string } | null
  members: { id: string; name: string; avatar: string; fights_won: number; actions: number; is_capo: boolean; last_seen: string }[]
  blocks: { id: number; name: string; hood: string; island: string }[]
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
  crews: { id: string; name: string; emblem: string; capo_id: string; capo: string; members: number; blocks: number }[]
}

export interface CrewRef { id: string; name: string; emblem: string }
export interface Block {
  id: number; name: string; owner: CrewRef | null; mine: boolean; garrisoned: boolean; garrison_size: number | null
  garrison: Record<string, number> | null; claim_price: number
}
export interface Hood {
  id: number; name: string; price: number; daily_income: number; base_resistance: number; owner: CrewRef | null; blocks: Block[]
}
export interface Island { island: string; hoods: Hood[] }
export interface TerritoryLog {
  id: number; block: string; hood: string; attacker: string | null; crew: string | null; success: boolean
  attack: number; resistance: number; at: string
}

export interface Message { id: number; sender_id: string; sender_name: string; body: string; created_at: string }
export interface Conversation { channel: string; other_id: string; other: string; last: string; at: string }

export interface TopUsers {
  fighters: { id: string; name: string; value: number }[]
  hustlers: { id: string; name: string; value: number }[]
  traders: { id: string; name: string; value: number }[]
  crews: { id: string; name: string; emblem: string; value: number }[]
}

export type AccoladeKind = 'fight_win' | 'defense' | 'action' | 'import' | 'market' | 'turf'
export interface Ribbon { kind: AccoladeKind; rank: number }
export interface AccoladeBoard { [kind: string]: { id: string; name: string; value: number }[] }
export interface Accolades { week_start: string; week_end: string; this_week: AccoladeBoard; last_week: AccoladeBoard; mine: Ribbon[] }
