# The Delve

> Working title. A **party-based idle dungeon crawler** for **PC / Steam**, built in **Godot 4.x** with **typed GDScript**.

Dark gothic ARPG mood (Diablo / Path of Exile). A party of **4 heroes auto-fights 24/7** and keeps
progressing while the game is closed; power comes from gear, pets, relics, a talent tree, and
gacha-summoned heroes. The UI is themed **"Grimhollow"** — carved stone, beveled iron, ember glow.

The full design brief lives in [CLAUDE.md](CLAUDE.md); the **implementation map (read first):
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**.

---

## Status — playable vertical slice, server-integrated (mock mode)

The full **Grimhollow UI** is implemented across **multiple OS windows** — the main window
permanently hosts the Fight battlefield (the one screen that can never close); Camp, Hero,
Global Rankings, and the Party Finder each open in their own window, all usable simultaneously.

**Done**
- **Multi-window shell** (`WindowManager`): main window = Fight + nav rail + resource strip;
  Camp / Hero / Leaderboard pop out as separate windows (state survives close/reopen). Closing the
  main window autosaves and quits.
- **CombatSim** (autoload, 10 ticks/s): wave/stage progression, gold/XP/levels, loot + floater
  events, party vitals, speed 1×/2×/4×, Team Aura check, retreat, energy regen — and **offline
  progress** computed with the same per-tick math (12 h cap) feeding the "Welcome back, delver" popup.
- **FIGHT:** roaming iso battlefield (footstep trail, ember path chevrons, edge spawn markers,
  depth-tiered enemies w/ lunge trails, striding heroes), wave bar, Party Finder, Team Aura,
  auto-loot ticker, 4 hero HUD frames, speed/auto-skill/auto-advance/retreat controls.
- **CAMP:** night scene (stars, ruins, campfire, path glows, drifting embers), 4 buildings with
  modals — **gacha** (×1/×10 flip-reveal, live drop rates, soft/hard pity), Notice Board
  (quests / mini-leaderboard / daily dungeon), Forge upgrade, Hearthfire Kitchen buffs, Town Crier.
- **HERO:** 3-zone Equipment tab (character sheet · rune-ringed paperdoll · tabbed 6×5 inventory),
  Pets (active companion + collection), Relics (equipped + vault + set bonus), and a pan/zoom
  **talent web** (~140 nodes, allocate/refund rules, identical layout to the design via the same
  seeded PRNG).
- **LEADERBOARD:** season header, division ladder, 4 ranking categories (`Q/W/E/R`),
  Global/Friends/Guild scopes, podium, ranked table, pinned YOU bar.
- **LOGIN:** PoE-style first-launch character creation — four classes (Warrior / Mage /
  Hunter / Rogue) around a campfire, lore panel per class, real stat bonuses; existing
  profiles skip straight in.
- **Equipment is live state:** drag-and-drop between bag and paperdoll (swap-aware,
  right-click quick equip), canonical rolled items up to **mythic** (SSR) rarity.
- **Battle caches:** clickable chests spawn along the route; the **backend** decides the
  contents. Mythic drops broadcast to every player via a crimson ribbon under the wave bar.
- **PARTY FINDER:** 4-player groups — browse/forge/join/leave; member presence (online,
  level, stage, power) refreshes with the 45 s combat heartbeat.
- **Backend client** (`autoload/BackendClient.gd`): every server call in the live schemas of
  [grimhollow-api](https://github.com/Malzano/party-idle-adventure-srv), with **mock mode
  on** by default — flip `mock = false` + set the Cloud Run URL after deploying.
- Gothic tooltips everywhere, hotkey chips, rarity glows; all art sits in labeled **pixel-art
  drop-slots** sized for [pixellab.ai](https://www.pixellab.ai) sprites.

**Hotkeys:** `1` Camp · `2` focus Fight · `3` Hero · `L` Rankings · `P` Party Finder ·
`Q/E/R/F` camp buildings · `Q/W/E/R` hero tabs & ranking categories · `Z/X` auto-toggles ·
`Esc` retreat / close.

**The math is real** (CLAUDE.md §3/§7):
- **`StatBlock`** stacks flat + increased% mods from every source — gear (incl. forge upgrades),
  allocated talents, the active pet, equipped relics, timed food buffs, Team Aura, and
  gacha-roster support — via an effect-string parser, so all content is mechanically live.
- **CombatSim** fights real per-stage enemy HP pools (geometric growth); gold/XP apply your
  gold-find / XP-gain bonuses and the daily-dungeon gold rush; offline progress runs the same
  per-wave math (12 h cap) and advances actual stages while you're away.
- **Economy loops close:** forge upgrades persist (success rolls, growing costs, real stat
  growth), meals buff the party on a timer, the daily dungeon costs energy (3 attempts/day),
  daily quests track real sim events and pay parsed rewards, and every summon adds support DPS.
- **All tuning lives in [`data/balance.json`](data/balance.json)** — rebalancing needs no code.

**Tests:** [GUT](https://github.com/bitwes/Gut) (MIT, dev-only — see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)) with **66 unit tests** across the parser,
balance curves, player stats, sim determinism + offline cap, gacha pity, economy, save
round-trip (incl. class + equipment), chest/item-gen contract, battlefield lifecycle, and the
party contract — plus a windowed screenshot harness (`test/CaptureShots.tscn`):

```
godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit
```

**Backend:** implemented in the sister repo
[party-idle-adventure-srv](https://github.com/Malzano/party-idle-adventure-srv)
(TypeScript / Express 5 / Firestore, Cloud Run-ready) from
[docs/backend-spec.md](docs/backend-spec.md). The client is fully wired through
`BackendClient.gd` and ships in mock mode until the server is deployed.

**Next milestones:** deploy the backend + flip mock off, sprite pass (PixelSlot swap-in),
friends/guild/mail client UI, balance pass, Steam polish — the maintained list is
[TODO.md](TODO.md). Full state of the project: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## Tech

- **Engine:** Godot **4.4+** (stable line). Pure GDScript — no .NET/C# build needed.
- **Resolution:** 1920×1080, 16:9, `canvas_items` stretch (`keep` aspect) for clean scaling + Steam Deck.
- **Saves:** JSON in `user://savegame.json`, storing a **last-played UTC timestamp** for offline gains.

## Run

1. Install Godot **4.4+** (standard edition).
2. Open this folder in the Godot editor (or `godot project.godot`). First open imports the SVG/font assets.
   **The 2D canvas is blank by design** — the whole UI is built in code.
3. Press **F5 / Play**. The entry scene is `scenes/login/Login.tscn` (class selection on a
   fresh profile, straight into the game otherwise). Switch screens with the rail or hotkeys.

## Project structure

```
res://
  autoload/      EventBus · GameState · SaveManager · CombatSim(systems) · WindowManager · BackendClient
  systems/
    combat/      CombatSim.gd (10 ticks/s headless sim + offline progress)
    data/        StatBlock · PlayerStats · GameContent · Balance
  scenes/
    login/       first-launch class selection
    main/        Main.tscn (main-window shell: Fight + rail + strip)
    fight/       Fight HUD + Battlefield (living world, chests, mythic ribbon)
    camp/  hero/  party/  leaderboard/                  (popup OS windows)
    ui/          Palette · Style · Fonts · Tip · PixelSlot · StatBar · NavRail · ResourceStrip
  data/          balance.json — ALL tuning (live-overridable via /v1/config)
  test/          GUT unit suite + CaptureShots screenshot harness
  assets/        fonts (Spectral + Silkscreen, OFL) · tintable SVG icons
```

All tuning is **data-driven** in [data/balance.json](data/balance.json) — rebalancing needs no
code changes. The deep map (boot flow, conventions, gotchas, backend contract) is in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Credits & licenses

- **Fonts:** [Spectral](https://fonts.google.com/specimen/Spectral) and
  [Silkscreen](https://fonts.google.com/specimen/Silkscreen), under the SIL Open Font License — see the
  `*-OFL.txt` files in [assets/fonts/](assets/fonts/).
- **UI design:** the "Grimhollow" mockup was produced in Claude Design and reimplemented in Godot.

> **Project license:** proprietary placeholder — see [LICENSE](LICENSE) (all rights reserved;
> swap for a real license before accepting contributions). Third-party components keep their
> own terms (GUT — MIT; fonts — SIL OFL).
