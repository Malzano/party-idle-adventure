# The Delve

> Working title. A **party-based idle dungeon crawler** for **PC / Steam**, built in **Godot 4.x** with **typed GDScript**.

Dark gothic ARPG mood (Diablo / Path of Exile). A party of **4 heroes auto-fights 24/7** and keeps
progressing while the game is closed; power comes from gear, pets, relics, a talent tree, and
gacha-summoned heroes. The UI is themed **"Grimhollow"** — carved stone, beveled iron, ember glow.

The full design brief lives in [CLAUDE.md](CLAUDE.md).

---

## Status — early skeleton

The full **Grimhollow UI** is implemented across **multiple OS windows** — the main window
permanently hosts the Fight battlefield (the one screen that can never close); Camp, Hero, and
the Global Rankings each open in their own window, all usable simultaneously.

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
- Gothic tooltips everywhere, hotkey chips, rarity glows; all art sits in labeled **pixel-art
  drop-slots** sized for [pixellab.ai](https://www.pixellab.ai) sprites.

**Hotkeys:** `1` Camp · `2` focus Fight · `3` Hero · `L` Rankings · `Q/E/R/F` camp buildings ·
`Q/W/E/R` hero tabs & ranking categories · `Z/X` auto-toggles · `Esc` retreat / close.

**Next milestones** (see [CLAUDE.md §8](CLAUDE.md)): real combat data driving the sim (enemy HP
pools, per-hero DPS from the StatBlock), gear/affix model, unit tests (GUT), balance pass.

---

## Tech

- **Engine:** Godot **4.4+** (stable line). Pure GDScript — no .NET/C# build needed.
- **Resolution:** 1920×1080, 16:9, `canvas_items` stretch (`keep` aspect) for clean scaling + Steam Deck.
- **Saves:** JSON in `user://savegame.json`, storing a **last-played UTC timestamp** for offline gains.

## Run

1. Install Godot **4.4+** (standard edition).
2. Open this folder in the Godot editor (or `godot project.godot`). First open imports the SVG/font assets.
3. Press **F5 / Play**. The entry scene is `scenes/main/Main.tscn`. Switch screens with the rail or keys `1`/`2`/`3`.

## Project structure

```
res://
  autoload/      GameState.gd · EventBus.gd · SaveManager.gd   (singletons)
  scenes/
    main/        Main.tscn / Main.gd                            (root shell)
    camp/  fight/  hero/                                        (the three screens)
    ui/          Palette · Style · Fonts · NavRail · ResourceStrip · ScreenBase
  assets/
    fonts/       Spectral + Silkscreen (SIL OFL)
    icons/       UI SVG icons (tintable)
  data/          (planned) JSON / .tres balance + content definitions
```

Balance numbers are intended to stay **data-driven** under `res://data/` so tuning needs no code changes.

## Credits & licenses

- **Fonts:** [Spectral](https://fonts.google.com/specimen/Spectral) and
  [Silkscreen](https://fonts.google.com/specimen/Silkscreen), under the SIL Open Font License — see the
  `*-OFL.txt` files in [assets/fonts/](assets/fonts/).
- **UI design:** the "Grimhollow" mockup was produced in Claude Design and reimplemented in Godot.

> **Project license:** none yet. A `LICENSE` file should be added before reusing third-party code or
> accepting contributions — license compatibility (esp. GPL copyleft) matters once code is borrowed.
