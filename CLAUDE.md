# Project Brief — "The Delve" (working title)

A **party-based idle dungeon crawler** for **PC / Steam**, built in **Godot 4.x (latest stable)**.
Dark gothic ARPG mood (Diablo / Path of Exile). Auto-combat that runs offline; the player builds power
through gear, pets, relics, a talent tree, and gacha-summoned heroes.

> This document is the source of truth for the build. When something here is ambiguous, ask before
> inventing mechanics. Open questions are tracked at the bottom.

> **Implementation status (2026-06-12): the game below is BUILT** — dark-gothic multi-window UI,
> real sim + economy, login/class select, equipment drag-and-drop, battle chests, mythic
> broadcasts, 4-player parties, and a server-authoritative backend client (mock mode on; the
> server lives in the sister repo `party-idle-adventure-srv`). **New sessions: read
> [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) first** — it maps the codebase, conventions,
> gotchas, and validation commands, and records the decisions taken on §10's open questions.
> Keep that file updated when the architecture changes.

---

## 1. Tech stack & targets

- **Engine:** Godot **4.4+** (current stable line is 4.5.x / 4.6.x). Use **typed GDScript** everywhere.
- **Platform:** Desktop (Windows first, then Linux for Steam Deck). Mouse + keyboard primary; design with
  later controller support in mind (focus navigation on menus).
- **Base resolution:** 1920×1080, 16:9. Use a `canvas_items` stretch mode so the UI scales cleanly to
  other 16:9 resolutions and the Steam Deck (1280×800 is 16:10 — keep critical UI inside a safe area).
- **Save format:** JSON or `ConfigFile` in `user://`. Saves must store a **last-played UTC timestamp** for
  offline progress.
- **No external services for v1.** Multiplayer / real leaderboards are deferred (see §9). Anything
  "social" in v1 is simulated/local.

---

## 2. Core loop & reference

Inspired by *Ulala: Idle Adventure*. The party of **4 heroes** auto-fights 24/7 and keeps progressing
while the game is closed.

- **Roles:** Tank / Healer / DPS. A **Team Aura** bonus activates when the comp is "optimal"
  (1 Tank + 1 Healer + 2 *different* DPS) → flat % buff to all stats (mockup showed +18%).
- **Loop:** fight stages → earn gold/items/XP → upgrade gear, stats, talents, pets, relics → summon new
  heroes (gacha) → push deeper stages. Offline time is converted into the same rewards on next launch.

---

## 3. Combat must be a simulation, not an animation

This is the most important architectural rule. **Combat is a deterministic tick-based simulation** driven
by stats (party DPS, enemy HP, healing, etc.), decoupled from rendering and frame rate.

- A `CombatSim` runs at a fixed logical tick (e.g. 10 ticks/sec). Speed toggles (1× / 2× / 4×) just change
  how many ticks are processed per real second.
- The **visual battlefield is a presentation layer** that reads sim state and plays movement/attacks/
  damage numbers. The sim must be able to run **headless and fast** so offline progress is just
  "advance the sim N ticks" using elapsed real time.
- Offline calc on load: `elapsed = now_utc - last_played_utc`, clamp to a cap (e.g. 12h), run the sim that
  many ticks, then show the **"Welcome back, delver"** rewards popup (gold / levels / items).

---

## 4. Recommended project structure

```
res://
  scenes/
    main/            Main.tscn  (root, holds the persistent nav + screen container)
    camp/            Camp.tscn + building popups (Board, Craft, Restaurant, Gacha)
    fight/           Fight.tscn, Battlefield.tscn, HeroFrame.tscn, EnemyToken.tscn
    hero/            Hero.tscn  (tabs: Equipment / Pets / Relics / Talents)
    ui/              shared components: TopBar, NavRail, Tooltip, Modal, ItemSlot
  systems/
    combat/          CombatSim.gd, Combatant.gd, DamageNumber logic
    idle/            OfflineProgress.gd
    save/            SaveManager.gd
    data/            StatBlock.gd, Item.gd, Hero.gd, Party.gd, Gacha.gd, TalentTree.gd
  data/              JSON/.tres definitions: heroes, items, enemies, stages, talents, gacha tables
  assets/           art, fonts, sfx
  autoload/          GameState.gd (singleton), EventBus.gd (signals)
```

- Use an **autoload `GameState`** singleton for the player profile, party, currencies, and a single
  `EventBus` for cross-screen signals (e.g. `rewards_collected`, `hero_summoned`).
- Keep all balance numbers **data-driven** in `res://data/` so tuning doesn't require code changes.

---

## 5. The three screens

Navigation: a persistent **left rail / top bar** with CAMP (1), FIGHT (2), HERO (3), plus a top-right
resource strip: level, gold, premium currency, energy/stamina. (Matches the mockups already produced.)

### CAMP (hub)
Torchlit camp with clickable buildings, each opening a centered modal:
- **Notice Board** → tabs: Leaderboard, Daily Quests, Daily Dungeon.
- **Crafting House** → forge/upgrade items.
- **Restaurant** → consumable party buffs (food).
- **Skill Learning House (Gacha)** → summoning altar, x1 / x10 pulls, drop-rate + pity counter.

### FIGHT (idle auto-combat) — see §6 for the movement design
Wide isometric battlefield. Party of 4 roams **bottom-left → top-right**; enemies stream in from all
edges (mainly top-right). HUD: stage/wave bar, 4 hero frames with HP/mana + role tags, Team Aura
indicator, floating damage numbers, auto-loot ticker, control cluster (Speed 1×/2×/4×, Auto-Skill,
Auto-Advance, Retreat), Party Finder panel docked top corner. Offline-gains popup on return.

### HERO (profile) — tabbed
- **Equipment:** PoE-style paperdoll — center silhouette, slots around it (helm, chest, gloves, boots,
  weapon, offhand, 2 rings, amulet, belt), rarity-colored borders, hover tooltips with full item stats.
- **Stats:** 5 main stats prominent + expandable detailed/derived stats list. *(Placeholder mains:
  Strength, Dexterity, Intelligence, Vitality, Luck — confirm before locking.)*
- **Pets:** active pet slot + collection grid.
- **Relics:** equipped relics + their bonuses.
- **Talents:** large pan/zoom node web (PoE style), allocated nodes glow, hover tooltips per node.

---

## 6. Fight scene — roaming movement (the latest design decision)

The battlefield must read as **constant motion**, not a static arena:

- The party moves as a **tight cluster heading toward the top-right**, with a faint travel trail behind
  them in the bottom-left (footsteps / scuffed ground).
- **Camera follows the party**; the world scrolls past so the party stays heading toward the top-right of
  the frame → endless-travel feel. *(Confirm: scroll-follow vs. stage-reset — see open questions.)*
- **Enemies spawn from multiple edges**, heaviest from the **top-right**, plus flanks from right/top/
  bottom. Show depth: far (small/faint at edges), mid, and clashing. Edge **spawn markers** (warning
  glints) where new enemies are about to enter.
- The clash zone and floating damage numbers sit where party meets enemies.

Implementation: enemy tokens are sim entities given an **edge spawn point + approach vector** toward the
party's current position; the renderer tweens them in. The sim decides kills/damage; the visuals just
reflect it.

---

## 7. Data model (starting point)

- **StatBlock:** the 5 mains + derived (HP, ATK, DEF, crit, etc.). Heroes, gear, pets, relics, talents,
  and the Team Aura all contribute additively/multiplicatively into a final computed block.
- **Hero:** id, name, role (tank/healer/dps), class, level, base stats, equipped gear refs, skills.
- **Party:** up to 4 hero slots; computes Team Aura eligibility and the resulting buff.
- **Item:** slot, rarity, affixes (rolled), level requirement.
- **Gacha:** weighted tables per rarity + pity counter.
- **TalentTree:** node graph (id, position, prerequisites, stat grants, allocated flag).

---

## 8. Suggested build order (vertical slice first)

1. **Skeleton:** Main scene, nav rail, three empty screens that switch, `GameState` + `SaveManager`
   (save/load + last-played timestamp).
2. **CombatSim core (headless):** stats → DPS → kill enemies → emit rewards. Unit-test it.
3. **Fight screen v1:** wire the battlefield visuals to the sim, 4 hero frames, stage/wave bar, speed
   toggles. Static-ish first, then add the §6 roaming + edge spawns.
4. **Offline progress:** compute on load, "Welcome back" popup.
5. **Hero screen:** stats panel + equipment paperdoll feeding the StatBlock; then pets/relics/talents.
6. **Camp:** building modals; Gacha summon flow (adds heroes to roster).
7. **Polish:** Team Aura logic, daily quests/dungeon, balance pass, Steam build settings.

Build and verify each milestone before moving on. Prefer many small testable scripts over monoliths.

---

## 9. Deferred / out of scope for v1
- Real multiplayer, networked party finder, live leaderboards (simulate locally for now).
- Steam achievements / cloud saves / overlay (wire in once the slice is playable).
- Audio and final art (use placeholders; keep art swappable).

---

## 10. Open questions (please confirm before building the affected part)
1. **Fight camera:** scroll-follow the party (endless travel) **or** stage completes and resets to a fresh
   area? (§6)
2. **Clash behavior:** enemies reach & surround the party (defend the cluster) **or** get cut down before
   arriving (steamroll forward)?
3. **The 5 main stats:** confirm names/definitions (placeholder is STR/DEX/INT/VIT/LUK).
4. **Hero acquisition:** are heroes purely gacha-summoned, or also story/quest unlocks?
5. **Offline cap:** how many hours of offline progress before it stops accruing?
