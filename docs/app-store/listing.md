# App Store listing (#24), age rating and privacy (#25), review notes (#26)

Everything App Store Connect asks for in text, ready to paste. The counts are characters, checked against Apple's limits. Screenshots are in `screenshots/` (6.9", required) and `screenshots-6.7/`, with a README.

## 1. Name (30 max)

**Cartel Wars** — 11/30

The catch (#4): *Narcos: Cartel Wars* is already on the store. App Store Connect only refuses a name that's taken exactly, so "Cartel Wars" may well go through when the app record is created. But it's the same two words as a big licensed game, and its publisher can file a name dispute with Apple later (guideline 5.2.1), which would mean renaming after launch. Try "Cartel Wars" first. If it's refused, or you'd rather not carry the risk, use a fallback:

1. **Cartel Wars: Hold the Block** — 27/30. Keeps the name and adds the tagline, so it can't be an exact match. Still shares the two words.
2. **Hold the Block** — 14/30. The tagline from the sign-in screen, and it says what the turf war is about. No "cartel" or "wars" to collide with.
3. **Street Cartel** — 13/30. Keeps "cartel", drops "wars". Short and plain.
4. **Cartel City** — 11/30. The 81-hood map is the heart of the game. Check it's free; short names often aren't.
5. **Turf Kings** — 10/30. Crews and blocks, no "cartel" at all. The safest one for review, the furthest from the game's own name.

The name under the icon on the home screen comes from the app (`CFBundleDisplayName`, "Cartel Wars"), not the store listing, and only shows about 12 characters. "Cartel Wars" fits.

## 2. Subtitle (30 max)

1. **Run product. Hold the block.** — 28/30
2. **Build a crew. Take the city.** — 28/30
3. **Grow it. Move it. Defend it.** — 28/30
4. **A live crime strategy MMO** — 25/30
5. **Crews, turf and a live market** — 29/30

Suggested: 1. It's the game in five words and echoes the sign-in screen.

## 3. Promotional text (170 max)

This sits above the description and can be changed at any time without a review.

1. **Grow it, move it, defend it. The rivals, crews and traders around you are real players, and the city keeps moving while you're away.** — 132/170
2. **Start a crew, take a block and hold it. A held block falls only after 50 hits, so your crew has time to fight back.** — 115/170
3. **The Daily Drop leaves a crate every day: cash, product, diamonds or a jackpot. Every prize and its odds are in the game.** — 120/170 (once purchases ship)

## 4. Description (4,000 max) — 3098/4000

```text
Cartel Wars is a crime strategy MMO set in a city that never shuts off. You start with a little cash and a few street jobs. Build an operation, find a crew, and take the city one block at a time.

PRODUCE AND MOVE PRODUCT
Build grow houses for herb, dust and pills. They produce while you're away. Collect into storage, then move it: send hustlers out to sell on the street, list it on the marketplace, or fill another player's buy order. Street prices move, and dumping a pile at once pushes them down. When you're ready, pick a path: Producers run the grow houses, Traders work the street.

RUN JOBS
Over thirty jobs, each with its own stamina cost, payout and heat. Some need the right gear or a crew behind you. The big ones can turn up rare gear you can't buy anywhere.

FIGHT
Fight other players one on one with the gear in your setups. You see your odds before you swing. Build combos that counter what the city runs. The winner takes a cut of the loser's cash on hand, so bank what you can't afford to lose. Take too many hits and you end up in the hospital.

HEAT AND JAIL
Every job and fight adds heat. Run hot and you risk getting busted. Inside, you run jail jobs and fight other inmates with your jail setup until you post bail.

CREWS AND CARTELS
Join a crew of up to 12, or start your own and run it as Capo. Crews share a bank, a chat and crew fights. Crews band together into cartels under a Don, and the Capos can vote in a new one.

TURF WARS
The city is 81 hoods of six blocks each. Hire thugs and mercenaries, claim empty blocks, and lay siege to held ones. A held block falls after your crew lands 50 hits, and every hit resets the owner's payout clock. Every block is a business that gives your whole crew a perk, and pays out every day.

A LIVE MARKET
Listings, buy orders and a prices board with the last trade and the day's volume. Prices move with what players sell.

THE CASINO
Live Texas Hold'em against other players, plus blackjack, craps, roulette and slots. You play with the game's cash only. Nothing you win in the casino can be cashed out.

A PERSISTENT WORLD
The city runs all the time. Your grow houses produce and other players make their moves while you're offline. Everyone you fight, trade with and talk to is a real player, apart from the thugs: 200 street-level NPCs to practice on. Live chat, crew and cartel chat, direct messages, a forum and weekly boards. You can report or block any player from their profile.

FREE TO PLAY
Free to play, with no ads. Optional in-app purchases: diamond packs, and the Daily Drop, a monthly subscription that leaves a crate every day. Diamonds buy refills, upgrades and extra setup slots. Every crate's prizes and odds are shown in the game. The Daily Drop renews each month until you cancel it in Settings at least 24 hours before the period ends.

For players 18 and over. Cartel Wars is fiction: the people, crews and places in it are made up. Needs an internet connection.

Terms of Service: https://rangerzack.github.io/cartel-wars/terms.html
Privacy Policy: https://rangerzack.github.io/cartel-wars/privacy.html
```

The Terms link is there on purpose: Apple wants a link to the terms of use in the description (or a custom EULA) for any app that sells a subscription (guideline 3.1.2).

## 5. Keywords (100 max) — 100/100

```text
mafia,mob,crime,gang,mmo,rpg,turf,crew,kingpin,hustle,underworld,empire,boss,street,multiplayer,thug
```

No word from the name. Apple already matches the name, subtitle and category, so repeating them wastes room. None of these are in subtitle 1. With subtitle 2, 4 or 5, drop the word it repeats (crew; crime and mmo; turf) and use the room for another, such as racket or syndicate. The line is at exactly 100 now.

## 6. Category, URLs, copyright

- **Primary category:** Games → Role Playing
- **Secondary category:** Games → Strategy
- **Support URL:** https://rangerzack.github.io/cartel-wars/support.html
- **Privacy Policy URL:** https://rangerzack.github.io/cartel-wars/privacy.html
- **Marketing URL:** https://rangerzack.github.io/cartel-wars/
- **Copyright:** © 2026 Range Lab

## 7. Age rating questionnaire (#25)

The 2025 questionnaire, item by item. "Frequent" is Apple's "Frequent or Intense".

| Section | Question | Answer | Why |
|---|---|---|---|
| In-app controls | Parental controls | No | There are none. |
| | Age assurance | No | No age check; the Terms say 18+. |
| Capabilities | Unrestricted web access | No | The only pages the app opens are our own Support, Privacy and Terms pages, in a Safari sheet. |
| | User-generated content | Yes | Street names, avatars, bios, crew names and descriptions, chat, forum posts. |
| | Messaging and chat | Yes | Live chat, crew and cartel chat, poker table chat and DMs with other players. |
| | Advertising | No | No ads. |
| Mature themes | Profanity or crude humor | Infrequent | Players can swear in chat. The word filter blocks slurs and hate everywhere and keeps names strict. |
| | Horror/fear themes | None | |
| | Alcohol, tobacco, or drug use or references | Frequent | Producing and dealing product is the core loop. The products have made-up names (herb, dust, pills). |
| | Mature or suggestive themes | Infrequent | Organized crime, extortion and bribery in job names. |
| Medical or wellness | Medical or treatment information | None | The hospital is just a health bar. |
| | Health or wellness topics | None | |
| Sexuality or nudity | Sexual content or nudity | None | |
| | Graphic sexual content and nudity | None | |
| Violence | Cartoon or fantasy violence | Frequent | One-on-one fights, crew fights and turf attacks, resolved as numbers. Losers end up in the hospital. |
| | Realistic violence | None | No images of violence, just text and numbers. |
| | Prolonged graphic or sadistic realistic violence | None | |
| | Guns or other weapons | Infrequent | Weapons are gear items with attack and defense numbers. |
| Chance-based activities | Simulated gambling | Frequent | Five casino games (Hold'em, blackjack, craps, roulette, slots) played with the game's cash. |
| | Contests | None | The weekly boards give a stripe, not a prize. |
| | Gambling (real money) | No | Nothing in the game can be cashed out. |
| | Loot boxes | Yes | The Daily Drop crates: a random prize from a fixed table, with the odds shown in the game. |

**Expected result: 18+.** Frequent simulated gambling should be enough on its own. If it comes out lower, choose a higher rating and set 18+: the Terms and the Privacy Policy both say players must be 18.

## 8. App Privacy (#25)

**Do you or your third-party partners collect data from this app?** Yes.

| Data type | What it is here | Purpose | Linked to the user | Used for tracking |
|---|---|---|---|---|
| Contact Info → Email Address | Sign-in, confirmation and reset emails, support replies | App Functionality | Yes | No |
| Identifiers → User ID | The account ID and the street name | App Functionality | Yes | No |
| Purchases → Purchase History | Diamond packs and the Daily Drop status, through RevenueCat (once purchases ship) | App Functionality | Yes | No |
| User Content → Emails or Text Messages | Chat lines and DMs | App Functionality | Yes | No |
| User Content → Gameplay Content | Cash, product, gear, fights, casino hands, crews, territory | App Functionality | Yes | No |
| User Content → Other User Content | Avatar, bio, crew names and descriptions, forum threads and replies, reports | App Functionality | Yes | No |

- Nothing else: no location, contacts, photos, health, financial info (Apple takes the payment), browsing or search history, usage data or diagnostics. There are no third-party advertising, analytics or crash-reporting SDKs.
- No purpose other than App Functionality: no analytics, no advertising, no personalization.
- **Tracking: No.** Nothing is shared with data brokers or used across other companies' apps, so there's no App Tracking Transparency prompt and no `NSUserTrackingUsageDescription`.
- RevenueCat processes the purchases. When the SDK goes in, check its App Store privacy guide: if it sends a device identifier, add Identifiers → Device ID (App Functionality, linked, not tracking).
- **Export compliance:** the app only uses the encryption built into iOS, for HTTPS, so it's exempt. `ITSAppUsesNonExemptEncryption` is already `false` in `web/ios/App/App/Info.plist`, so App Store Connect won't ask on each build.

## 9. Review notes (#26) (4,000 max) — 2895/4000

Fill in the two blanks before submitting.

```text
Cartel Wars is a multiplayer crime strategy game. The world is live and shared: every player you see is a real person on the same server, apart from the 200 NPC "thugs" on Fight > Thugs. The city keeps running between sessions. The app needs a network connection.

DEMO ACCOUNT
Email:
Password:
The account already has cash, diamonds, gear, a crew and product in storage, so every screen has something on it. You can also make a new account on the sign-in screen (New Player).

WHERE THINGS ARE
- Home: stats, recent activity, the Daily Drop card, and links to Territory, Casino, Forum, Crew and Top Users.
- Actions: jobs that cost stamina and pay cash or reputation.
- Economy: grow houses, hustlers and the marketplace.
- Fight: other players and the NPC thugs. Tap one to see your odds and attack.
- Services: bank, hospital, police, hoodlums, refills and upgrades.
- Chat: live chat, crew chat and direct messages.
- Profile: tap your name at the top left.

IN-APP PURCHASES
Diamond packs are in the Store tab. The Daily Drop subscription is on the Daily Drop card on Home. "What can drop? See the odds" on that card lists every prize and its odds before you buy. Purchases go through Apple in-app purchase (via RevenueCat). Diamonds are spent in the game only.

CASINO
Hold'em, blackjack, craps, roulette and slots, played with the game's own cash. No real money can be wagered or won, and nothing in the game can be cashed out.

USER CONTENT AND MODERATION (1.2)
- Players agree to the Terms of Service at sign-up. They forbid harassment, hate, threats and spam.
- Every other player's profile has Report and Block. Every chat line from someone else has a ⋯ menu with Report and Block. Forum threads and replies have Report.
- Block stops DMs both ways and hides that player's chat lines and posts, straight away.
- Reports go to an admin queue in the app. A new report also pings the admin on Discord, and the queue is checked at least once a day. Admins can delete messages and posts, reset names, avatars and bios, and mute a player for 1, 7 or 30 days.
- A word filter covers names, avatars, bios, crew names and forum titles, and blocks slurs and hate in chat and forum posts.

SIGN-IN EMAILS
Account confirmation and password reset links open in Safari, on our website. This is by design: our sign-in provider can only redirect to a web address, not into the app. After confirming, or setting a new password there, come back to the app and sign in.

ACCOUNT DELETION (5.1.1(v))
Profile (tap your name at the top left) > Account > Delete account. Type the street name to confirm. The account and its data are deleted at once and you're signed out.

CONTENT
Rated 18+. Everything in the game is fiction: the products (herb, dust, pills), people, crews and places are made up. There are no images of drugs or violence; the game is text, numbers and emoji.

Contact: support@rangelab.io
```

## 10. Demo account checklist (#26)

1. **Make the account in the app** (or on the web build) with **New Player**: a street name such as `AppReview` and an inbox you can read, such as `appreview@rangelab.io`. Click the confirmation link in the email. Signing up in the app gives it a real street name; an account made in the Supabase dashboard starts as `player_xxxxxxxx` and opens on a rename prompt.
2. **Check it** in the Supabase SQL editor:
   ```sql
   select p.id, p.name, u.email_confirmed_at
     from profiles p join auth.users u on u.id = p.id
    where u.email = 'appreview@rangelab.io';
   ```
3. **Stock it.** Cash, diamonds, gear in all three setups (with a combo in offense and defense), product, a herb grow house, some thugs, and a crew of its own. Change the crew name if it's taken.
   ```sql
   do $$
   declare me uuid := (select id from auth.users where email = 'appreview@rangelab.io'); c uuid;
   begin
     if me is null then raise exception 'No account with that email'; end if;
     update profiles set cash = 500000, bank = 2000000, diamonds = 300,
            stamina_max = 100, stamina = 100, health_max = 200, health = 200, heat = 0,
            storage_cap = 2000, inventory_slots = 8, jail_until = null, in_hospital = false
      where id = me;
     update storage set qty = case commodity when 'herb' then 800 when 'dust' then 300 else 60 end where player_id = me;
     insert into grow_houses (player_id, commodity, level, running, started_at) values (me, 'herb', 3, true, now())
       on conflict (player_id, commodity) do nothing;
     insert into inventory (player_id, item_id, qty)
       select me, id, 1 from item_defs
        where name in ('AK-47', 'Glock 18', 'Body Armor', 'Kevlar Vest', 'Armored SUV', 'Box Truck', 'Toothbrush Shiv')
       on conflict (player_id, item_id) do nothing;
     insert into setup_items (player_id, setup, item_id, qty)
       select me, s, id, 1 from item_defs, unnest(array['offense', 'defense']::setup_kind[]) s
        where name in ('AK-47', 'Glock 18', 'Body Armor', 'Kevlar Vest', 'Armored SUV')
       on conflict do nothing;
     insert into setup_items (player_id, setup, item_id, qty)
       select me, 'jail', id, 1 from item_defs where name in ('Toothbrush Shiv', 'Kevlar Vest')
       on conflict do nothing;
     insert into player_hoodlums (player_id, code, qty) values (me, 'thug', 60), (me, 'spy', 2)
       on conflict (player_id, code) do update set qty = excluded.qty;
     if (select crew_id from profiles where id = me) is null then
       insert into crews (name, emblem, description, capo_id) values ('Night Shift', '🌙', 'Open late.', me) returning id into c;
       update profiles set crew_id = c where id = me;
     end if;
   end $$;
   ```
4. **Sign in on a phone** and look at Home, Actions, Economy, Fight, Crew and Profile once, so nothing is stuck on a first-run prompt.
5. **Top lists.** Top Users ranks the top 20 by fights won, actions and market volume. The SQL above leaves those at zero, so the account sits at the bottom and only shows while the city has fewer than 20 players. Whatever the reviewer does in their week can still land them on that week's boards. There's no flag that hides an account from the lists: `is_bot` would, but it also makes the account a thug, which can't be reported, blocked or deleted. Don't use it.
6. **Paste the email and password** into the review notes (section 9) and into App Store Connect's sign-in fields, with "Sign-in required" ticked.
7. **After review**, the reviewer may have deleted the account (that's one of the things they check). Make a new one for the next submission the same way.
