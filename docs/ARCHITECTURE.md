# Party Idle Adventure (working title) — Architecture & Current State

> **Read this first if you are new to the repo (human or AI session).** It describes what is
> actually built and how the pieces fit. [CLAUDE.md](../CLAUDE.md) is the original design
> brief (intent); this file is the implementation truth. When they disagree, this file wins.
> **Keep it current: if you change architecture, update this doc in the same commit.**

A **party-based idle dungeon crawler** for PC/Steam in **Godot 4.6 (typed GDScript, tabs)**.
Dark gothic ARPG mood ("Grimhollow" design system: carved stone, beveled iron, ember glow).
Your **single character** auto-fights 24/7 — including while the game is closed — and you build
power through gear, talents, pets, relics, food buffs, and gacha summons (real-player parties
add a shared-combat bonus).

**Sister repo:** [party-idle-adventure-srv](https://github.com/Malzano/party-idle-adventure-srv)
(`party-idle-api`) — TypeScript/Express 5/Firestore on Cloud Run, **LIVE on party-idle-dev**
(asia-southeast1). The server owns all mutable shared state; the client ships **`mock=false`**
(set `BackendClient.mock=true` to run fully offline; same schemas).

---

## Single-character pivot (2026-06-14) — the current model

> Earlier versions had a player-owned **party of 4 gacha heroes** with a Roster tab. That is
> **GONE**. The four stages below shipped + deployed; the design memory has the full record.

- **1 account = 1 character.** `GameContent.active_party()` returns ONE class-derived delver
  (cascades to the battlefield, Fight HUD, party dock and `CombatSim` vitals — all read it
  size-agnostically). `PlayerStats` base DPS = `character.base_dps[class_id]` (balance.json)
  × gear/talent mult × `GameState.party_aura_mult`. The 12-hero `HEROES` pool, `aura_check`,
  `gacha_pick`, `set_party_slot`/`add_roster_hero`, and `party_ids` are **dormant** (pruned in
  a later cleanup). The Roster tab is removed.
- **Floors & bosses.** The flat `stage` (1..50) is the sub-stage counter; `floor =
  (stage_index-1)/10+1`. Mini-boss on the final wave of sub-stage 5, floor boss on sub-stage
  10 (`Balance.wave_kind`). `data/bosses.json` holds 5 deterministic scalar skill primitives
  (enrage/shield/regen/adds). `CombatSim` clocks the boss with an INTEGER tick counter so the
  live tick and `_boss_clear_secs` (offline) are byte-identical; bosses force-clear at
  `boss_time_cap` → offline never stalls. `stages_per_act=50` is FROZEN (server stage-index
  unit); `enemy.substages_per_floor` is the new cadence knob.
- **Gacha rolls GEAR** into the bag (mock + live, bag-full salvage to gold). The pet-unlock
  gate reads `GameState.total_summons` (migrated from a legacy roster's length on load).
- **Team Aura → real-party composition bonus.** Server `lib/compositionAura.ts` returns
  `party_aura_mult` on the PartyView (online members' class/role spread, capped +28%, solo
  1.0). `GameState.set_party` adopts it; `party_changed` reprices the sim + rebuilds the
  Fight "PARTY AURA · +N%" badge.
- **Save schema (both repos, coordinated rollout).** `to_dict` dropped `party_lineup` +
  `roster_extra`, added `total_summons`. `SAVE_VERSION` 2→3 with the load gate fixed to `< 2`
  (the old `< SAVE_VERSION` gate would have WIPED every v2 save). Server went **permissive
  first** (`roster_extra` optional, anti-cheat re-keyed to `total_summons` growth) before the
  client dropped the keys, so nothing 422s.
- **Firestore gotcha (critical):** Firestore can't store arrays-of-arrays, and item stat pairs
  are `s: [["Armour","+248"],...]`. So the save blob is persisted as a **JSON string** on the
  server (`lib/blob.ts`; client/HTTP contract unchanged). Live-test saves WITH items, not just
  empty ones. Verified live: save+items, gacha→gear (idempotent), chest, sync, forge all 200.
- **Stage 5 — synchronized shared delve (BUILT).** One `combat_sessions/{party_id}` doc per
  party; the **leader's** deterministic client sim is authoritative and POSTs a checkpoint
  every ~4 s (`BackendClient._delve_beat`, `DELVE_INTERVAL`), online members GET + render via
  `CombatSim.apply_session` in `follow_mode` (no self-advance, no persist — solo position is
  preserved for clean resume on leave). The server stores + **loosely** validates (`lib/delve.ts`
  `validateCheckpoint`: leader-only, strictly-increasing seq, monotonic + `MAX_STAGE_JUMP=60`
  capped), never re-simulates. `SESSION_STALE_SECONDS=15` drops a stalled delve so members fall
  back to solo. Host migration (`leaveDelve`) promotes a remaining **live party member**
  (`adopt_as_leader` continues from the session position so the first checkpoint isn't a
  "backward" reject); the session is deleted on party dissolution so it can't orphan.
  - **Followers earn (Stage 5.3).** `apply_session` credits gold/xp (with the player's own
    gold_find/xp_gain) for the shared waves cleared since the last poll, at the **party floor**,
    and advances `max_stage` toward it; a wave-index cursor baselines on the first apply so
    joining a deep delve never back-pays. `sync.ts` stays the **only** gold/xp/max_stage writer.
  - **Party-floor caps grace.** A carried member earns/reaches `max_stage` above their own solo
    floor, which the solo anti-cheat would 422. So `save`/`sync` read the caller's live session
    (`activeDelveFloor`, same transaction) and pass its floor to `checkCaps` as `delveStageIndex`:
    reward RATE is priced at `max(ownFloor, partyFloor)` and the stage-rate cap permits *reaching*
    (not exceeding) the party floor. Solo play untouched (`delveStageIndex 0 == absent`); the
    floor is bounded by the leader-authoritative (capped) checkpoints, so it can't be forged.
    Verified live: an identical floor 2→180 jump 422s with no session, succeeds with a live delve.
- The composition aura (Stage 4) remains the always-on group bonus even when no delve is active.

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
autoloads (in order): EventBus → GameState → SaveManager → CombatSim → WindowManager → BackendClient → UserSettings → AssetManager
                                   │ SaveManager._ready loads user://savegame.json (v2 JSON)
main scene: scenes/login/Login.tscn
   ├─ GameState.has_profile()  → change_scene to scenes/main/Main.tscn
   └─ fresh profile            → PoE-style class select (warrior/mage/hunter/rogue around a
                                  campfire, lore panel per class) → choose_class() + save → Main
Main.tscn (the MAIN OS window — closing it autosaves + quits)
   └─ Fight scene (permanent) + NavRail + ResourceStrip
Popup OS windows (WindowManager, hidden-not-freed on close, all can be open at once):
   camp (1) · hero (3) · leaderboard (L) · party (P) · settings (rail gear)  [2 = focus main]
```

UserSettings (autoload) holds DEVICE prefs (audio/display/combat) in
`user://settings.cfg` — NOT the save blob — and applies V-Sync/fullscreen/master
volume to the engine; gameplay readers query it (battlefield damage numbers).

Popup windows render a fixed **1920×1080 "stage" Control, manually scale-to-fit**
(`WindowManager._create`) — `Window.content_scale_*` is deliberately bypassed (it laid out
but didn't scale at render).

## 3. Directory map (what lives where)

```
autoload/
  EventBus.gd        all cross-screen signals (sim_*, equipment_changed, party_changed,
                     lineup_changed, hero_tab_requested, settings_changed, …)
  GameState.gd       the live profile: identity/class, currencies, progression, equipment
                     arrays, daily counters, party mirror, party_ids (the fighting four);
                     to_dict/from_dict (save schema v2, 42 keys); equip_from_bag /
                     unequip_to_bag / add_bag_item / set_party_slot (swap-safe lineup)
  SaveManager.gd     user://savegame.json, last_played_utc, offline elapsed (12 h cap),
                     v1→v2 migration (keeps timestamp, resets profile)
  WindowManager.gd   popup window registry (_DEFS) + stage scaling + per-window hotkeys;
                     open_hero_tab(i) routes the Fight dock's MANAGE → Roster tab
  BackendClient.gd   THE network seam (§5)
  UserSettings.gd    device prefs (settings.cfg) — applies V-Sync/fullscreen/volume
  AssetManager.gd    remote sprite/skin/item delivery (§6b): manifest sync, cache,
                     core/standard/lazy, SpriteFrames build from bundles
systems/
  combat/CombatSim.gd    10 t/s sim: wave/stage HP pools (geometric), gold/xp/loot/level,
                         speed 1×/2×/4×, energy regen, offline_rewards
  data/StatBlock.gd      flat + increased% stacking; effect-string parser ("+10 Strength",
                         "+8% Crit", "470–664") — ALL content strings are mechanically real
  data/PlayerStats.gd    cached aggregation: gear (forge-scaled) + class bonus + talents +
                         pet + relics + food + Team Aura + roster → derived stats + power
  data/GameContent.gd    every design table (party, gear, bag, pets, relics, gacha pool,
                         talent web via seeded PRNG, props, spawns, CLASSES, EQUIP_SLOTS,
                         HEROES (12-hero collection + active_party/aura_check/hero_recruited),
                         chest item-gen MIRROR of srv lib/itemGen.ts — keep in sync!,
                         MOCK_DELVERS / MOCK_PARTY_NAMES for the mock party world)
  data/Balance.gd        balance.json loader + dot-path access + live-ops apply_overrides
scenes/
  login/Login.gd         first-launch class selection (campfire, EmberFire draw class)
  main/Main.gd           main-window shell (Fight + rail + strip; WM_CLOSE → save + quit)
  fight/Fight.gd         HUD: wave bar, party-finder dock (FIND/MANAGE PARTY button),
                         team aura, loot ticker, hero frames, controls, offline popup,
                         mythic announcement ribbon (EventBus.mythic_announced, queued)
  fight/Battlefield.gd   2D left→right side-scroller (rebuilt 2026-06; was iso): hero holds
                         the LEFT facing right, foes rush in from the RIGHT to a clash line
                         and cluster (approach→engage→die on sim kills); cavern backdrop +
                         3 scrolling parallax layers; positions = scalar x (0..1) + lane.
                         COHERENT attacks: melee dashes to strike in-range, ranged fires;
                         a damage number is minted ON the struck foe and its HP bar drains
                         by a hit-count budget (kept in lockstep with sim_enemy_killed; only
                         the sim kills). Boss HP mirrors sim_boss_hp. Clickable Battle Caches
                         (chests → BackendClient.chest_open) scroll left; heal floaters via
                         sim_floater on the hero. RULE: any node freed early must unregister
                         its _bobs/_pulses entries or _process casts freed.
  camp/                  Camp scene + Board (quests/leaderboard/dungeon/MAIL tabs) /
                         Gacha/Forge/Kitchen modals (all live systems)
  hero/                  Hero window tabs (Q/W/E/R/T): EquipmentTab = 3-zone sheet/
                         paperdoll/inventory with full drag-and-drop (_DragCell), Pets
                         (summon-milestone unlocks), Relics (stage-milestone slots),
                         Talents, Roster (design v2 party-selection: pick the fighting
                         four, live Team Aura diagnostics, lock/recruit, slot-swap)
  settings/Settings.gd   Options window (audio/display/combat) → UserSettings
  party/PartyFinder.gd   party window (§6) + FRIENDS & GUILD panel + join-by-code
  leaderboard/           season header, divisions, categories, ranked table
  ui/                    Palette · Style (Style.fs readability scale) · Fonts · Tip
                         (multi-window tooltips) · UnitSprite (animated, asset-backed,
                         placeholder fallback) · PixelSlot
                         (labeled art drop-slots sized for pixellab.ai sprites) · StatBar ·
                         NavRail · ResourceStrip
data/balance.json        ALL tuning (enemy curves, rewards, energy, gacha, forge, heroes,
                         power weights, gear_rarity_mult incl. mythic)
test/unit/               GUT suite — 76 tests (§8)
test/CaptureShots.tscn   windowed screenshot harness (§8)
docs/backend-spec.md     the original server spec the srv repo implements (+ extensions)
docs/lore.md             lore bible: world, per-class act storylines, FACTION design
                         (pros/cons; data stub in GameContent.FACTIONS, not yet choosable)
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
- Wired endpoints (26): save (PUT/GET), sync, gacha/pull, forge/upgrade, kitchen/cook,
  dungeon/enter, talents/set, quests/claim, chest/open, announcements, leaderboard
  (submit/get), season, config, party (list/mine/create/join — by id or `DELV-XXXX`
  code — /leave), friends (get/add), guild (get/join), mail (list/claim). Friends &
  guild live in the Party Finder's left column; mail is the Notice Board's MAIL tab.
- **Save blob is `.strict()`-validated server-side (42 keys).** Never add keys to
  `GameState.to_dict()` without extending `srv/src/types/save.ts` in the same change
  (defaulted, so old blobs stay valid). Client-only state (e.g. the mock party, device
  settings) goes in `user://netstate.json` / `user://settings.cfg` instead. **`from_dict`
  must emit `lineup_changed` when `party_ids` changes** — runtime adoption (409 conflict)
  has to refresh the sim/HUD/battlefield, not just the boot path.

## 6. Party system (the "party game" core)

- Server: `parties/{id}` Firestore doc, members embedded (cap 4 → transactional), one party
  per player (`players/{uid}.party_id`), leader hand-off on leave, empty parties dissolve,
  presence TTL 120 s. List = open public parties, no composite index needed at v1.
  Every party carries a `DELV-XXXX` join code (members-only payload; never in the list) —
  private parties are joinable only by it.
- Client: `GameState.party` is a **read-only mirror** of the server's PartyView
  (`{}` = solo; `EventBus.party_changed` on replace). The Party Finder window renders it;
  all mutations go through `BackendClient.party_*`.
- Mock: ~6 bot parties seeded per session from `GameContent.MOCK_DELVERS`; your party
  persists across restarts via netstate.json; leaving hands the banner to the bots.

## 6b. Remote asset delivery (sprites / skins / items)

Live-content pipeline so the binary stays small and skins/items ship without a client
patch. **Bytes live in Google Cloud Storage behind Cloud CDN — never in Firestore, never
proxied through Express.** The server serves only a thin manifest.

- **Server** `GET /v1/assets/manifest?since=N` (public, never-500s like /v1/config):
  `{catalog_version, cdn_base, bundles[]}`. A bundle = `{id, kind, version, hash, bytes,
  url, priority, deps}`. Stored in `config/asset_catalog` (seeded from
  `src/types/assets.ts DEFAULT_CATALOG`), CDN origin from `ASSET_CDN_BASE` env. `since`
  shortcuts to `{unchanged:true}` when the client is current. Pure rules + tests in
  `src/lib/assets.ts` (validateCatalog / manifestSince / bundlesToDownload).
- **Priority model** (the chosen "tiny core + rest remote"): `core` = baked into the build
  at `res://assets/core/<id>/` (opens instantly, offline); `standard` = background-download
  on first launch; `lazy` = on demand (a skin only when equipped).
- **Client** `AssetManager` (autoload): boots by registering core + cached bundles, then
  `sync_catalog()` reconciles standard bundles (diff by per-bundle hash vs
  `user://assets/index.json`). Live mode downloads `.pkg` from `cdn_base+url` via HTTPRequest
  → sha-verify → ZIPReader unzip → `user://assets/<id>/`. **Mock mode** serves the same
  catalog (`BackendClient._mock_asset_catalog`, must stay field-parity with the server's
  DEFAULT_CATALOG) over `res://` folders. The 45 s heartbeat re-runs `sync_catalog` so new
  catalog rows (hot content) appear without a restart.
- **A bundle on disk** = `meta.json` + atlas PNG(s). Animated kinds (hero/enemy) describe
  `anims: {action: {sheet, frames, fps, dirs, loop}}`; `AssetManager.get_sprite_frames(id)`
  builds a cached SpriteFrames (grid: cols=frames, rows=dirs). Static kinds expose textures
  by key.
- **Rendering** `scenes/ui/UnitSprite.gd` (battlefield heroes+enemies) plays real frames
  when a bundle has art, else falls back to the labeled `PixelSlot` placeholder — so the
  game runs at every stage of art production. The code-driven advance/scroll/depth/bob is
  unchanged; UnitSprite only animates in place. `PixelSlot` gained an optional
  `bundle_id`/`sprite_key` so static art (login figures, buildings, chest) drops in too.
- **Skins**: `GameState.hero_skins` (hero_id → skin bundle id; save key `hero_skins`,
  cosmetic only). `GameContent.hero_bundle(id)` resolves skin-or-base; `set_hero_skin`
  requests the lazy bundle + emits `lineup_changed` (battlefield rebuilds with the new art).
- **No real sprites exist yet** — everything falls back to placeholders today. Drop a
  `<id>/` folder under `res://assets/core/` (or upload to GCS + add a catalog row) and it
  renders. Test bundles are generated procedurally in `test/unit/test_assets.gd`.

## 7. Implementation decisions vs the brief (CLAUDE.md §10 answers)

| Open question | What was built |
|---|---|
| Fight camera | 2D left→right side-scroller (rebuilt 2026-06): hero holds the LEFT, parallax background scrolls left (treadmill), foes rush in from the right |
| Clash behavior | Foes rush to a clash line near the hero, cluster, and die on sim kills; hero attacks the nearest in-range foe (melee dashes, ranged fires) |
| 5 main stats | STR / DEX / INT / VIT / LUK, as placeholdered |
| Hero acquisition | Fixed design party of 4 + gacha roster adds support DPS (managed in the Hero window's ROSTER tab, hotkey T); **player class** chosen once at first launch (warrior/mage/hunter/rogue) |
| Per-hero equipment | **v1 ships ONE shared paperdoll** (the player-class loadout). Per-hero loadouts would multiply save schema, drag-drop, and stat plumbing ×4 for little idle-game payoff — revisit post-v1 if hero identity matters more |
| Pet / relic acquisition | Derived from authoritative state, no schema additions: pets unlock at gacha-summon-count milestones (`GameContent.pet_owned`), the two empty relic slots fill at `max_stage` milestones (`GameContent.live_relics`) |
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

**The live work list is [TODO.md](../TODO.md)** (the srv repo has its own); keep both checked
off in the same commits that do the work.

**Deploy day:** follow `README → Deploy` in the srv repo (Firestore + Identity Platform
anonymous auth + Cloud Run + Scheduler), then flip `BackendClient.mock = false` and fill
`base_url` + `web_api_key`.
