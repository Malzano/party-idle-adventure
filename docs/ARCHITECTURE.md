# Grimhollow / "The Delve" — Architecture & Current State

> **Read this first if you are new to the repo (human or AI session).** It describes what is
> actually built and how the pieces fit. [CLAUDE.md](../CLAUDE.md) is the original design
> brief (intent); this file is the implementation truth. When they disagree, this file wins.
> **Keep it current: if you change architecture, update this doc in the same commit.**

A **party-based idle dungeon crawler** for PC/Steam in **Godot 4.6 (typed GDScript, tabs)**.
Dark gothic ARPG mood ("Grimhollow" design system: carved stone, beveled iron, ember glow).
A party of 4 heroes auto-fights 24/7 — including while the game is closed — and the player
builds power through gear, talents, pets, relics, food buffs, and gacha summons.

**Sister repo:** [party-idle-adventure-srv](https://github.com/Malzano/party-idle-adventure-srv)
(`grimhollow-api`) — TypeScript/Express 5/Firestore on Cloud Run. The server owns all mutable
shared state; this client ships with a schema-faithful **mock mode** (see §Backend).

---

## 1. The golden rules

1. **The UI is built 100 % in code.** Every `.tscn` is a bare root `Control` + script. The
   editor's 2D canvas is intentionally blank — press **F5** to see anything.
2. **Combat is a headless simulation** (`CombatSim`, 10 ticks/s), never an animation. The
   battlefield renders sim state; offline progress is "run the same math for N elapsed
   seconds" (capped 12 h).
3. **The server is authoritative** for everything monetized or shared (gacha, chests,
   parties, leaderboard…). All network goes through ONE seam: `autoload/BackendClient.gd`.
   Mock mode runs the same logic locally in the **exact server response schemas**.
4. **Balance is data**, in [data/balance.json](../data/balance.json) (live-overridable via
   `/v1/config`). Content/design data lives in `systems/data/GameContent.gd`.
5. **Layout gotcha:** to make a Control fill its parent use
   `set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)` — plain `set_anchors_preset`
   leaves containers stuck at min-size.
6. **Validation gotcha:** Godot prints `SCRIPT ERROR` / `Parse Error` to **stderr**. Never
   validate with stderr discarded (a swallowed parse error once silently killed every
   autoload). Commands in §8.
7. Screen scripts use `preload()` references, not `class_name` (shared UI/systems classes
   like `Palette`, `Style`, `StatBlock`, `GameContent` DO have `class_name`).

## 2. Boot & scene flow

```
autoloads (in order): EventBus → GameState → SaveManager → CombatSim → WindowManager → BackendClient
                                   │ SaveManager._ready loads user://savegame.json (v2 JSON)
main scene: scenes/login/Login.tscn
   ├─ GameState.has_profile()  → change_scene to scenes/main/Main.tscn
   └─ fresh profile            → PoE-style class select (warrior/mage/hunter/rogue around a
                                  campfire, lore panel per class) → choose_class() + save → Main
Main.tscn (the MAIN OS window — closing it autosaves + quits)
   └─ Fight scene (permanent) + NavRail + ResourceStrip
Popup OS windows (WindowManager, hidden-not-freed on close, all can be open at once):
   camp (hotkey 1) · hero (3) · leaderboard (L) · party (P)        [2 = focus main]
```

Popup windows render a fixed **1920×1080 "stage" Control, manually scale-to-fit**
(`WindowManager._create`) — `Window.content_scale_*` is deliberately bypassed (it laid out
but didn't scale at render).

## 3. Directory map (what lives where)

```
autoload/
  EventBus.gd        all cross-screen signals (sim_*, equipment_changed, party_changed, …)
  GameState.gd       the live profile: identity/class, currencies, progression, equipment
                     arrays, daily counters, party mirror; to_dict/from_dict (save schema v2,
                     39 keys); equip_from_bag / unequip_to_bag / add_bag_item
  SaveManager.gd     user://savegame.json, last_played_utc, offline elapsed (12 h cap),
                     v1→v2 migration (keeps timestamp, resets profile)
  WindowManager.gd   popup window registry (_DEFS) + stage scaling + per-window hotkeys
  BackendClient.gd   THE network seam (§5)
systems/
  combat/CombatSim.gd    10 t/s sim: wave/stage HP pools (geometric), gold/xp/loot/level,
                         speed 1×/2×/4×, energy regen, offline_rewards
  data/StatBlock.gd      flat + increased% stacking; effect-string parser ("+10 Strength",
                         "+8% Crit", "470–664") — ALL content strings are mechanically real
  data/PlayerStats.gd    cached aggregation: gear (forge-scaled) + class bonus + talents +
                         pet + relics + food + Team Aura + roster → derived stats + power
  data/GameContent.gd    every design table (party, gear, bag, pets, relics, gacha pool,
                         talent web via seeded PRNG, props, spawns, CLASSES, EQUIP_SLOTS,
                         chest item-gen MIRROR of srv lib/itemGen.ts — keep in sync!,
                         MOCK_DELVERS / MOCK_PARTY_NAMES for the mock party world)
  data/Balance.gd        balance.json loader + dot-path access + live-ops apply_overrides
scenes/
  login/Login.gd         first-launch class selection (campfire, EmberFire draw class)
  main/Main.gd           main-window shell (Fight + rail + strip; WM_CLOSE → save + quit)
  fight/Fight.gd         HUD: wave bar, party-finder dock (FIND/MANAGE PARTY button),
                         team aura, loot ticker, hero frames, controls, offline popup,
                         mythic announcement ribbon (EventBus.mythic_announced, queued)
  fight/Battlefield.gd   living world: scrolling iso floor, footsteps, props (incl. trees/
                         rocks) that wrap, edge-spawned enemies (approach→engage→die on
                         sim kills), clickable Battle Caches (chests → BackendClient
                         .chest_open), floaters. RULE: any node freed early must
                         unregister its _bobs/_pulses entries or _process casts freed.
  camp/                  Camp scene + Board/Gacha/Forge/Kitchen modals (all live systems)
  hero/                  Hero window tabs; EquipmentTab = 3-zone sheet/paperdoll/inventory
                         with full drag-and-drop (_DragCell: bag↔slot, swap-aware,
                         right-click quick equip, drop-target highlights)
  party/PartyFinder.gd   party window (§6)
  leaderboard/           season header, divisions, categories, ranked table
  ui/                    Palette · Style · Fonts · Tip (multi-window tooltips) · PixelSlot
                         (labeled art drop-slots sized for pixellab.ai sprites) · StatBar ·
                         NavRail · ResourceStrip
data/balance.json        ALL tuning (enemy curves, rewards, energy, gacha, forge, heroes,
                         power weights, gear_rarity_mult incl. mythic)
test/unit/               GUT suite — 66 tests (§8)
test/CaptureShots.tscn   windowed screenshot harness (§8)
docs/backend-spec.md     the original server spec the srv repo implements (+ extensions)
```

## 4. Core data flow

- **Items** are canonical dicts `{n, r, slot, ilvl, s: [[label, value], …]}`. Rarity ladder:
  common → uncommon → rare → epic → legendary → **mythic** (SSR, crimson, globally
  announced). Paperdoll = `GameState.equipped` (10 nullable slots, index-aligned with
  `GameContent.EQUIP_SLOTS`); bag = `GameState.bag_equipment` (cap 30). Mutations emit
  `EventBus.equipment_changed`; `PlayerStats` recomputes lazily.
- **Stat pipeline:** every source contributes to a `StatBlock` → derived stats + party DPS →
  `CombatSim` consumes DPS → kills/waves/stages → gold/xp (with gold-find/xp-gain bonuses) →
  currencies → economy loops (forge, kitchen, dungeon, quests, gacha) feed back into gear /
  buffs / roster.
- **Daily reset** (`GameState.check_daily_reset`): quests, dungeon attempts, meals, summons,
  forges, chests.

## 5. Backend integration (BackendClient.gd)

- Envelope, always: `{ok: bool, status: int, data: Dictionary}`. Always `await` calls (mock
  never suspends). Errors mirror the server: `{error: {code, message}}` in `data`.
- **mock = true** (default until deploy): same logic the modals used to run locally, wrapped
  in real server schemas. CSPRNG-equivalent gacha with identical pity math, chest rolls
  mirroring `srv/lib/itemGen.ts`, a simulated party world (bots drift stages/presence).
- **Flip to live:** set `mock = false`, `base_url` (Cloud Run URL), `web_api_key`
  (Identity Platform); anonymous Firebase auth code is already in place. No call-site
  changes — that is the whole point of the seam.
- **Heartbeat (45 s):** `POST /v1/sync` (fast-moving fields; server merges + re-validates
  caps) + `GET /v1/announcements` poll + `party_mine()` presence refresh when partied.
  Server-side, a player's sync also refreshes their party member entry.
- Wired endpoints (20): save (PUT/GET), sync, gacha/pull, forge/upgrade, kitchen/cook,
  dungeon/enter, talents/set, quests/claim, chest/open, announcements, leaderboard
  (submit/get), season, config, party (list/mine/create/join/leave).
  **Server-ready but NOT yet wired in the client:** `/v1/friends*`, `/v1/guild*`,
  `/v1/mail*` (those screens still show design-simulated content).
- **Save blob is `.strict()`-validated server-side (39 keys).** Never add keys to
  `GameState.to_dict()` without extending `srv/src/types/save.ts` in the same change
  (defaulted, so old blobs stay valid). Client-only state (e.g. the mock party) goes in
  `user://netstate.json` instead.

## 6. Party system (the "party game" core)

- Server: `parties/{id}` Firestore doc, members embedded (cap 4 → transactional), one party
  per player (`players/{uid}.party_id`), leader hand-off on leave, empty parties dissolve,
  presence TTL 120 s. List = open public parties, no composite index needed at v1.
- Client: `GameState.party` is a **read-only mirror** of the server's PartyView
  (`{}` = solo; `EventBus.party_changed` on replace). The Party Finder window renders it;
  all mutations go through `BackendClient.party_*`.
- Mock: ~6 bot parties seeded per session from `GameContent.MOCK_DELVERS`; your party
  persists across restarts via netstate.json; leaving hands the banner to the bots.

## 7. Implementation decisions vs the brief (CLAUDE.md §10 answers)

| Open question | What was built |
|---|---|
| Fight camera | Scroll-follow "endless travel": world drifts past, props wrap, party stays bottom-left heading top-right |
| Clash behavior | Enemies approach to an engage ring, fight, and die on sim kills (both surround *and* steamroll) |
| 5 main stats | STR / DEX / INT / VIT / LUK, as placeholdered |
| Hero acquisition | Fixed design party of 4 + gacha roster adds support DPS; **player class** chosen once at first launch (warrior/mage/hunter/rogue) |
| Offline cap | 12 h (`SaveManager.OFFLINE_CAP_SECONDS`, also in balance.json) |

## 8. How to run / validate / test (Windows dev machine)

```powershell
# Godot 4.6.3 executable (this machine):
#   C:\Users\Ping\Desktop\Godot_v4.6.3-stable_win64.exe

# Headless boot validation — DO NOT discard stderr; errors print there:
godot --path . --headless --quit-after 60          # clean = no SCRIPT/Parse Error lines
godot --path . --headless --check-only -s res://path/to/File.gd   # single script

# Unit tests (GUT, vendored; 66 tests / 10 scripts):
godot --path . --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit

# Visual verification (windowed; writes PNGs to _shots/, gitignored; never touches the
# real save): login picker → class selected → battlefield + chest + mythic ribbon →
# party finder joined state:
godot --path . res://test/CaptureShots.tscn
```

Test scripts: `test_statblock` (parser/math) · `test_balance` (curves) · `test_playerstats`
(aggregation/aura) · `test_sim` (determinism, offline cap) · `test_gacha` (pity bands) ·
`test_economy` (forge/kitchen/dungeon/quests/daily reset) · `test_save` (round-trip incl.
class/equipment) · `test_chests` (mock contract, item-gen canonical) · `test_battlefield`
(chest lifecycle regression) · `test_party` (create/join/leave/cap/presence contract).

A **godot-mcp** server is configured for runtime checks (`run_project` /
`get_debug_output` / `stop_project`) — useful for catching runtime-only errors (it caught a
freed-object crash unit tests missed).

## 9. Status & what's deliberately not done

Implemented and tested: everything described above. **Deferred:** final art (every sprite
location is a labeled `PixelSlot` placeholder — swap-in planned via pixellab.ai), audio,
Steam packaging/achievements/cloud saves, friends/guild/mail client UI (server endpoints
exist), realtime co-op combat (parties currently share presence/progress, not a battlefield),
project LICENSE file.

**Deploy day:** follow `README → Deploy` in the srv repo (Firestore + Identity Platform
anonymous auth + Cloud Run + Scheduler), then flip `BackendClient.mock = false` and fill
`base_url` + `web_api_key`.
