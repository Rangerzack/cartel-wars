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
/** One of my open buy orders: qty is what's still wanted (its cash is held), filled what's come in. */
export interface MyOrder { id: string; commodity: Commodity; qty: number; filled: number; unit_price: number; expires_at: string }
/** Street price and what's behind it: pressure is the share hustler dumping has knocked off (fades by half every few hours). */
export interface StreetInfo { price: number; base: number; wiggle: number; pressure: number; depth: number }

export interface Me {
  id: string; name: string; created_at: string; avatar: string; bio: string; reputation: number
  cash: number; bank: number; diamonds: number
  stamina: number; stamina_max: number
  health: number; health_max: number
  heat: number; heat_max: number; heat_level: HeatLevel
  jailed: boolean; jail_until: string | null
  hospital: boolean
  health_next: string; health_bought: number
  /** Health at which you walk out of the hospital (a % of max). */
  hospital_out_at?: number
  /** Next heat cool-down tick (next_tick is the stamina clock). */
  heat_next?: string
  rep_earned: number; path: Path | null; path_required: boolean
  /** Why the path is required: 100 reputation, or a grow house past the level unpathed players can reach. */
  path_due?: 'rep' | 'grow' | null
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
  /** Tab badges. Optional so a frontend ahead of the database still works. */
  unread_activity?: number
  unread_dms?: number
  server_time: string
  /** Business perks from the blocks your crew holds, as fractions (0.2 = 20%). */
  perks?: Partial<Record<BusinessCode, number>>
  /** Storage before the Warehouse perk (storage_cap has it applied). */
  storage_base?: number
  /** Most units one market listing can hold (Trucking Co raises it). */
  listing_max?: number
  /** Daily Drop subscription and crates. Optional so a frontend ahead of the database still works. */
  drop?: DropState
  /** Daily Drop credits: full stamina refills, and hustlers hired without the fee. */
  free_refills?: number
  free_hustlers?: number
  /** Per setup: the combos it completes, the one it runs, and the one the player picked (null = best). */
  combos?: Record<SetupKind, SetupCombos>
  /** Street details per product, my open buy orders, and the share of missing stamina/health the next product refill restores. */
  street?: Record<Commodity, StreetInfo>
  /** This player's yellow and red heat lines (heat upgrades move them up with max heat). */
  heat_yellow?: number; heat_red?: number
  /** Moderation: admins see the open report count; a reset or placeholder name asks for a new one. */
  is_admin?: boolean; rename_pending?: boolean; name_required?: boolean; reports_open?: number
  /** Ids of the players I've blocked: chat drops their lines as they arrive. */
  blocked?: string[]
  /** An admin muted me: no chat, forum posts or bio changes until then (null when not muted). */
  muted_until?: string | null
  orders?: MyOrder[]
  /** Today's drug refills: full ones per drug (3, or 5 on the Daily Drop), how many of each are used, and the share of
   *  max stamina one restores past those. */
  refills?: { full: number; used: Partial<Record<Commodity, number>>; late_share: number; sub_full: number }
  /** Milestone counts the profile didn't already carry: turf attacks made, cash wagered at the casino. */
  turf_attacks?: number; casino_wagered?: number
  /** What the next setup slot costs (it climbs with every slot past the free six). */
  slot_cost?: { diamonds: number; cash: number }
  /** 24-hour boost: +amount attack in Offense or defense in Defense. The side is locked on the first buy. */
  boost?: { side: 'attack' | 'defense' | null; until: string | null; active: boolean; amount: number }
}

export type StyleCode = 'armored' | 'antitank' | 'infantry' | 'blitz' | 'blackout'
/** A fighting style on the counter wheel: it beats two styles and loses to the other two. */
export interface ComboStyle { code: StyleCode; name: string; icon: string; blurb: string; beats: StyleCode[] }
/** A combo: complete when, for each part, one of that part's items is in the setup. Tier 1 street · 2 pro · 3 elite. */
export interface ComboDef { code: string; name: string; style: StyleCode; tier: 1 | 2 | 3; parts: number[][] }
export interface SetupCombos { active: string | null; complete: string[]; chosen: string | null }
/** What active players run (counts by combo code), and how combos did in the last week's fights. */
export interface ComboMeta {
  players: number; offense: Record<string, number>; defense: Record<string, number>
  fights: number; attacks: Record<string, { n: number; won: number }>
}

export type DropKind = 'herb' | 'dust' | 'pills' | 'diamonds' | 'cash' | 'refills' | 'thugs' | 'hustlers'
/** One line of the Daily Drop prize table; weight is out of the table's total (1,000). */
export interface DropPrize { code: string; label: string; kind: DropKind; amount: number; weight: number; jackpot: boolean; sort: number }
export interface DropState {
  subscribed: boolean; since: string | null; until: string | null; crates: number; max: number; opened: number
  /** The plan came from the App Store: it renews through Apple and is cancelled in the device settings. */
  drop_paid?: boolean
  last: { label: string; kind: DropKind; amount: number; jackpot: boolean; at: string } | null
}
export interface DropResult { code: string; label: string; kind: DropKind; amount: number; jackpot: boolean; crates: number }
export interface RecentDrop { player_id: string; player: string; label: string; kind: DropKind; amount: number; at: string }

export interface ActionDef {
  id: number; name: string; description: string; stamina_cost: number; pay_min: number; pay_max: number
  pay_rep: number; heat_gain: number; cash_cost: number; requires_item: number | null; min_crew: number; is_jail: boolean
  effect: string | null; sort: number
  /** The rare find this job can turn up (chance = stamina_cost / config.drop_stamina). */
  drop_item?: number | null
}
export interface ItemDef {
  id: number; name: string; category: ItemCategory; att: number; def: number; capacity: number
  price: number; rep_price: number; combo_tag: string | null; sort: number
  /** Found only on actions; can't be bought or sold. */
  drop_only?: boolean
}
export interface RareFind { id: number; name: string; category: ItemCategory; att: number; def: number; owned: number }
export interface RecentFind { player_id: string; player: string; item: string; item_id: number; action: string | null; at: string }
export interface ActionResult { pay: number; rep: number; busted: boolean; heat: number; stamina: number; cash: number; found?: RareFind | null }
export interface CommodityDef {
  code: Commodity; name: string; base_price: number; hustler_units: number; refill_stamina: number
  refill_health: number; grow_rate: number; grow_cap: number; grow_price: number; sort: number
  /** Units sold at once that would take the whole dumping discount off street. */
  market_depth?: number
}
export interface HoodlumDef { code: string; name: string; att: number; def: number; intel: number; base_price: number }

export type BusinessCode = 'grow_house' | 'dust_lab' | 'pill_factory' | 'utility' | 'chop_shop' | 'trucking' | 'repo'
  | 'strip_club' | 'night_club' | 'dispensary' | 'gym' | 'shooting_range' | 'security_firm'
  | 'pawn_shop' | 'pharmacy' | 'warehouse' | 'clinic' | 'law_office' | 'bent_cop'
export type BusinessCategory = 'production' | 'transport' | 'nightlife' | 'muscle' | 'retail' | 'services'
export interface BusinessDef {
  code: BusinessCode; name: string; category: BusinessCategory; slot: number; rot: number; icon: string
  perk: string; base: number; ceiling: number; sort: number
}

export interface Catalog {
  actions: ActionDef[]
  items: ItemDef[]
  commodities: CommodityDef[]
  hoodlums: HoodlumDef[]
  /** Optional so the page still works against an older database. */
  businesses?: BusinessDef[]
  drop_prizes?: DropPrize[]
  combo_styles?: ComboStyle[]
  combos?: ComboDef[]
  /** Diamond milestones: lifetime ladder steps (once each) and repeating steps (`repeat`: every n, forever). */
  milestones?: MilestoneDef[]
  /** In-app purchases: the diamond packs on sale and the Daily Drop's product id. Prices come from StoreKit. */
  store?: { packs: StorePack[]; drop_product: string }
  config: Record<string, number>
}
/** A diamond pack: its App Store product id and how many diamonds it credits. */
export interface StorePack { id: string; diamonds: number }
export type MilestoneKind = 'actions' | 'wins' | 'fights' | 'turf' | 'wagered'
export interface MilestoneDef { key: string; kind: MilestoneKind; n: number; reward: number; repeat?: boolean }

export interface PlayerSummary {
  id: string; name: string; avatar: string; crew: { name: string; emblem: string } | null
  fights: number; fights_won: number; hospital: boolean; jailed: boolean; immune: boolean; last_seen: string
}
/** Fight › Players filters (find_fighters): who you can fight right now, who's online (seen in 5 minutes), who's laid
 *  up or locked up; and the sorts. */
export type FighterStatus = 'all' | 'fight' | 'online' | 'hospital' | 'jail'
export type FighterSort = 'seen' | 'wins' | 'rep' | 'name'
export interface Fighter extends PlayerSummary { reputation: number; online: boolean; can_fight: boolean }
/** One page of the list, and how many the whole search has under each filter (for the chips). */
export interface FighterList { players: Fighter[]; counts: Record<FighterStatus, number> }
export interface PublicPlayer {
  id: string; name: string; created_at: string; avatar: string; bio: string; reputation: number; fights: number; fights_won: number; actions: number
  health: number; health_max: number; heat_level: HeatLevel; jailed: boolean; hospital: boolean; immune: boolean
  last_seen: string; ribbons: Ribbon[]; crew: { id: string; name: string; emblem: string } | null; cartel: { id: string; name: string } | null
  is_bot?: boolean
  /** I've blocked them / they've blocked me (either way, no DMs). */
  blocked?: boolean; blocked_me?: boolean
  /** Admins only: when their mute ends (null when not muted). */
  muted_until?: string | null
}
export interface BlockedPlayer { id: string; name: string; avatar: string; at: string }
export type ReportReason = 'name' | 'avatar' | 'bio' | 'other'
/** What's wrong with a chat message, forum thread or reply. */
export type ContentReason = 'harassment' | 'hate' | 'spam' | 'threat' | 'other'
export type ReportKind = 'profile' | 'message' | 'forum_thread' | 'forum_post'
export type ModAction = 'reset_name' | 'reset_avatar' | 'clear_bio' | 'dismiss' | 'delete_message' | 'delete_post' | 'delete_thread'
  | 'mute_1d' | 'mute_7d' | 'mute_30d' | 'unmute'
export interface ModReport {
  id: number; kind: ReportKind; reason: ReportReason | ContentReason; note: string
  /** The message, thread or reply id (null for a profile report). */
  ref_id: number | null
  /** A profile report keeps name, avatar and bio; a content report the text, where it was and who wrote it. */
  snapshot: { name?: string; avatar?: string; bio?: string; text?: string; title?: string; channel?: string; category?: string; author?: string; thread_id?: number }
  /** The reported text, and whether it's still up (null for a profile report). */
  text: string | null; live: boolean | null
  reporter: string | null; reporter_id: string | null; at: string
}
export interface ModQueueItem { id: string; name: string; avatar: string; bio: string; rename_pending: boolean; muted_until: string | null; reports: ModReport[] }
export interface ModLogEntry {
  id: number; action: ModAction | 'add_word' | 'remove_word' | 'set_word'; old: string | null; new: string | null; reports: number; at: string
  admin: string | null; target: string | null; target_id: string | null
}
export type WordMatch = 'squash' | 'part' | 'word'
/** chat: the word also blocks chat messages and forum posts (each tier matched its own way). */
export interface BannedWord { word: string; match: WordMatch; chat: boolean }
/** A +1 edge in a fight and who holds it, from the attacker's side. */
export interface FightEdge { k: 'defender' | 'cash' | 'heat'; side: 'you' | 'them' }
export interface FightResult {
  won: boolean; damage_dealt: number; damage_taken: number; cash: number; their_health: number; my_health: number
  hospitalized_them: boolean; hospitalized_me: boolean; busted: boolean; my_att: number; their_def: number; dry: boolean
  // head-to-head scoring (optional so the page still works against an older database)
  my_def?: number; their_att?: number; my_score?: number; their_score?: number; my_roll?: number; their_roll?: number
  edges?: FightEdge[]
  // combos: which each side ran, the most each could roll (10 countering, 5 even, 0 countered) and what it rolled
  my_combo?: string | null; their_combo?: string | null; my_combo_bonus?: number; their_combo_bonus?: number
  my_combo_max?: number; their_combo_max?: number
}
export interface ThugRow {
  id: string; name: string; avatar: string; level: number; stash: number; health: number; health_max: number
  hospital: boolean; win_pct: number; hits: number; dry: boolean; combo?: string | null
}
export interface FightLog {
  /** A side whose player deleted their account has a null id and the name "Deleted player". */
  id: number; attacker: string; attacker_id: string | null; defender: string; defender_id: string | null
  attacker_dmg: number; defender_dmg: number; cash: number; won: boolean; i_attacked: boolean; at: string
  attacker_combo?: string | null; defender_combo?: string | null; attacker_combo_bonus?: number; defender_combo_bonus?: number
}
export interface MarketListing {
  id: string; commodity: Commodity; qty: number; unit_price: number; seller: string; seller_id: string; mine: boolean; expires_at: string
}
export interface MarketOrder {
  id: string; commodity: Commodity; qty: number; filled: number; unit_price: number; buyer: string; buyer_id: string; mine: boolean; expires_at: string
}
export interface MarketStats { last: number | null; last_at: string | null; units_24h: number; avg_24h: number | null }
export interface Market {
  prices: Record<Commodity, number>; listings: MarketListing[]
  orders?: MarketOrder[]; street?: Record<Commodity, StreetInfo>; stats?: Record<Commodity, MarketStats>
}

export interface CrewSummary {
  id: string; name: string; emblem: string; description: string; members: number; blocks: number; cartel: string | null
}
export interface CrewDetail {
  id: string; name: string; emblem: string; description: string; capo_id: string; is_capo: boolean
  co_capo_id: string | null; is_co_capo: boolean; is_boss: boolean; created_at: string
  bank: number | null; cartel: { id: string; name: string; don_id: string } | null
  members: { id: string; name: string; avatar: string; fights_won: number; actions: number; is_capo: boolean; is_co_capo: boolean; last_seen: string }[]
  blocks: { id: number; name: string; hood: string; hood_id: number; island: string; bonus_at: string | null; business?: BusinessCode }[]
  applications: { id: string; name: string; at: string }[] | null
  applied: boolean
  invites: { id: string; name: string }[] | null
  power: { att: number; def: number }
  fights: CrewFight[]
  next_fight_at: string | null
  perks?: CrewPerk[]
}
/** One of a crew's business perks: stacked value, how many blocks feed it, and the best one. */
export interface CrewPerk {
  code: BusinessCode; value: number; blocks: number; best: number; best_full: boolean
  best_block: number; best_name: string; best_hood_id: number
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
  business?: BusinessCode
}
export interface Hood {
  id: number; name: string; district: string; gx: number; gy: number; price: number; claim_price: number
  daily_income: number; block_bonus: number; base_resistance: number; my_blocks: number; owner: CrewRef | null; blocks: Block[]
  ring?: number; full_hood?: boolean
}
export interface TerritoryRules { siege_wins: number; min_thugs: number; bonus_hours: number; stamina: number }
export interface Territory { hoods: Hood[]; rules: TerritoryRules; my_perks?: Partial<Record<BusinessCode, number>> }
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
  ring?: number
  business?: BlockBusiness | null
}
export interface BlockBusiness {
  code: BusinessCode; name: string; icon: string; category: BusinessCategory; perk: string; ceiling: number
  /** This block on its own, with the whole hood, and with the whole hood in a cartel. */
  value: number; value_full: number; value_full_cartel: number
  /** What it gives the crew holding it now, and that crew's total for this business. */
  owner_value: number | null; owner_full: boolean; owner_total: number | null
  my_total: number
}
export interface AttackBlockResult {
  success: boolean; captured: boolean; attack: number; resistance: number; lost_thugs: number; lost_mercs: number
  garrison_lost: number; claim_paid: number; wins: number | null; wins_needed: number; bonus_reset: boolean
}
export interface LedgerEntry {
  id: number; kind: 'deposit' | 'withdraw' | 'bonus' | 'fight_won' | 'fight_lost'; amount: number; balance: number
  note: string; at: string; player: string | null; player_id: string | null
}

/** deleted: an admin removed it (the body comes back empty); clients don't show it. */
export interface Message { id: number; sender_id: string; sender_name: string; body: string; created_at: string; deleted?: boolean }
export interface Conversation { channel: string; other_id: string; other: string; last: string; at: string; unread?: number }

export type ActivityKind = 'attacked' | 'crew_fight' | 'siege' | 'block_lost' | 'block_taken' | 'sold' | 'filled' | 'applied' | 'joined' | 'kicked' | 'daily_cash' | 'moderated'
  | 'purchase' | 'purchase_refunded' | 'milestone'
export interface ActivityItem {
  id: number; kind: ActivityKind; at: string; seen: boolean
  data: { n?: number; held?: number | boolean; cash_won?: number; cash_lost?: number; hospital?: boolean; cash?: number; commodity?: Commodity; units?: number; days?: number; combo?: string | null; action?: string; until?: string
          /** purchase: diamonds credited; purchase_refunded: diamonds taken back, of the `bought` the refunded pack gave */
          diamonds?: number; bought?: number
          /** milestone: which count reached n (the highest step paid), and the diamonds it paid */
          what?: MilestoneKind }
  actor_id: string | null; actor: string | null
  crew_id: string | null; crew: string | null; crew_emblem: string | null
  block_id: number | null; block: string | null; hood_id: number | null
  siege_wins: number | null; siege_need: number | null
}

export interface FightPreview {
  win_pct: number; dmg_min: number; dmg_max: number; my_health: number; hospital_risk: boolean
  dry: boolean; hits_this_hour: number; stamina_cost: number; heat_gain: number; bust_pct: number
  setup: SetupKind; their_setup: SetupKind
  // head-to-head scoring (optional so the page still works against an older database)
  win_exact?: number; edges?: FightEdge[]; edge_you?: number; edge_them?: number
  base_you?: number; base_them?: number; combo_you?: boolean; combo_them?: boolean
  my_att?: number; my_def?: number; their_att?: number; their_def?: number
  // combos: theirs is only known if they're a thug, run none, or you've hit them before (then it's what they ran then)
  my_combo?: string | null; their_combo?: string | null; their_combo_known?: boolean; their_combo_seen_at?: string | null
  their_has_combo?: boolean; my_combo_max?: number; their_combo_max?: number
}

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
export type CrapsNumber = 4 | 5 | 6 | 8 | 9 | 10
export type CrapsBetKind = 'pass' | 'dont' | 'pass_odds' | 'dont_odds' | 'field' | 'come' | 'dcome'
  | `place${CrapsNumber}` | `come${CrapsNumber}` | `come${CrapsNumber}_odds` | `dcome${CrapsNumber}` | `dcome${CrapsNumber}_odds`
  | 'hard4' | 'hard6' | 'hard8' | 'hard10' | 'any7' | 'anycraps'
export type CrapsEvent = 'natural' | 'craps' | 'point' | 'hit' | 'seven_out' | 'roll'
export interface CrapsLogLine { bet: CrapsBetKind; amount: number; result: 'win' | 'lose' | 'push' | 'stays' | 'off' | 'moves'; win?: number; stays?: boolean; to?: number }
export interface CrapsHistoryRoll { dice: [number, number]; sum: number; event: CrapsEvent }
export interface CrapsLast { dice: [number, number]; sum: number; log: CrapsLogLine[]; event?: CrapsEvent }
export interface CrapsState {
  point: number | null; bets: Partial<Record<CrapsBetKind, number>>; last: CrapsLast | null
  history?: CrapsHistoryRoll[]
  /** Most odds you can have behind each line bet right now. */
  odds_max?: { pass_odds: number; dont_odds: number; come?: Record<string, number>; dcome?: Record<string, number> }
}
export interface CrapsRoll extends CrapsState {
  dice: [number, number]; sum: number; event?: CrapsEvent; log: CrapsLogLine[]; wager: number; payout: number; net: number
}
export type BlackjackOutcome = 'blackjack' | 'win' | 'push' | 'lose' | 'bust' | 'dealer_bust'
export interface BlackjackHand {
  cards: string[]; total: number; soft: boolean; bet: number; doubled: boolean; split: boolean; done: boolean; active: boolean
  result: { outcome: BlackjackOutcome; payout: number; net: number } | null
}
export interface BlackjackState {
  status: 'none' | 'playing' | 'done'; wager: number; player: string[]; player_total: number; player_soft: boolean
  dealer: string[]; dealer_total: number; dealer_hidden: boolean; can_double: boolean; can_split?: boolean
  hands?: BlackjackHand[]; active?: number
  result: { outcome: BlackjackOutcome | 'split'; payout: number; net: number; hands?: { outcome: BlackjackOutcome; payout: number; net: number }[] } | null
}
export interface PokerTableInfo {
  id: number; name: string; small_blind: number; big_blind: number; min_buyin: number; max_buyin: number; seats: number
  seated: number; players: string[]; mine: boolean
  /** Rookie tables: only accounts younger than this many days can sit. */
  rookie_days?: number | null; eligible?: boolean
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
  /** By a player I've blocked: the snippet (and body) come back empty. */
  hidden?: boolean
}
export interface ForumList { category: ForumCategory; page: number; pages: number; total: number; is_admin: boolean; can_post: boolean; threads: ForumThreadSummary[] }
export interface ForumPost { id: number; author: ForumAuthor; body: string | null; deleted: boolean; created_at: string; edited_at: string | null; mine: boolean; hidden?: boolean }
export interface ForumThread {
  thread: ForumThreadSummary & { body: string; edited_at: string | null; mine: boolean }
  is_admin: boolean; can_reply: boolean; page: number; pages: number; posts: ForumPost[]
}
