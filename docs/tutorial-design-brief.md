# Tutorial design brief — first-session spotlight coachmarks

> **Purpose.** A complete, self-contained brief to design the new-player tutorial for
> **Party Idle Adventure** (working title) — a dark-gothic (Diablo/PoE) party idle
> dungeon-crawler. Hand this whole file to a design pass. It contains the UX pattern,
> the exact visual tokens pulled from the live game code, the 14-step sequence with
> final copy, the real on-screen elements to highlight per screen, the open design
> knobs, and four ready-to-render HTML mockups (the visual vocabulary).
>
> **You do not need the source repo.** The game's UI is built 100% in code (no layout
> files), so the code is not useful for visual design — everything visual you need is
> below. The mockups are built from the real element positions + the exact palette, so
> they are faithful to the shipping look.

---

## 1. The pattern

A **first-session spotlight tutorial**: dim the screen, punch a **spotlight** around ONE
real UI control, and show a **wording box** (headline + 1–2 line copy + Skip/Next +
step progress). The player steps through 14 beats that walk them through the core loop.
Some steps are **advance-by-doing** — the spotlit control stays live and the tutorial
advances when the player actually does the thing (changes speed, equips gear, opens a
window).

Three layout variants (all four mockups in §8):
- **Centered intro** — no spotlight; the whole battlefield is the subject (step 1).
- **Single spotlight** — one control lit, info-only, advances on Next (e.g. step 6).
- **Multi-highlight + arrow** — two elements lit with a drag arrow between (step 11).
- **Building spotlight** — a Camp building lit (step 14, the finale).

---

## 2. Visual style tokens (pulled from the live game)

**Fonts**
- Display / headings / building names: **Spectral** (serif). Sizes ~16–26px.
- Body / labels: sans. Sizes ~10–15px.
- Numerics, chips, hotkeys: **Silkscreen** (pixel). Sizes ~8–12px.
- All in-game text uses a 1px shadow/outline for glow.

**Palette (hex)**
| Role | Colors |
|---|---|
| Text | `#ece0c8` primary · `#b3a489` dim · `#7d7058` muted |
| Ember (accent / CTA) | `#ffac5c` bright · `#e8843a` base · `#b85a1f` deep · `#ff7a4d` hot |
| Gold (headings) | `#f0cf86` bright · `#d3ad62` · `#8a6e36` dim |
| Cyan (mana / toggles) | `#7fe3f0` bright · `#46c2d4` · `#1d6f7d` deep |
| Bars | HP `#c0433a` · Mana `#3f9fd0` · XP/forge `#c9a24a` |
| Floaters | damage `#fff2dd` · heal `#8ef08a` |
| Rarity | common `#8c8579` · uncommon `#5fa64e` · rare `#4a8fd6` · epic `#a661d6` · legendary `#e6a93a` · mythic `#e0455e` |
| Roles | Tank `#d6a24a` · Healer `#6fcf6a` · DPS `#e0584a` · Mage `#46c2d4` |
| Surfaces | `#0a0908` · `#110f0d` · `#18150f` · `#211d16` · `#2a251c` (darkest→lightest) |
| Iron edge (borders) | `#0c0a07` |

**Panels & chrome recipe**
- Standard panel (`panel_box`): bg `#211d16`, 1px `#0c0a07` border, soft drop shadow.
- Modal scrim: black @ ~72%.
- Ember CTA button: bg `#e8843a`, text `#1c0f04` (near-black), border `#3a1d08`.
- Ghost button: translucent bg `rgba(56,51,39,.55)`, 1px iron border.
- Stone button: bg `#322c22`, iron border.
- Corner radii: 3px (buttons), 4px (slots/pills), 6–8px (panels/cards).

---

## 3. Coachmark anatomy

**Scrim:** fill the active screen with `rgba(8,7,5,0.74)` (reuse the modal scrim alpha).

**Spotlight:** a padded transparent hole around the target's rect, with a **2px `#ffac5c`
rounded border** (radius 6–8) and a soft ember glow. The hole passes mouse-through on
advance-by-doing steps so the real control stays clickable; clicks on the dark area are
swallowed.

**Wording box** (`panel_box`, ~14–16px padding):
1. `STEP n / 14` — muted `#7d7058`, ~10px, letter-spaced.
2. Thin ember **progress bar** (or 14 dots — see §6).
3. **Headline** — Spectral, `#f0cf86`, ~16px (20px on the centered intro).
4. **Body** — sans, `#ece0c8`, ~13px, 1–2 lines max.
5. Footer row: `Skip tour` ghost (left) · `Next ›` ember CTA (right).
   First step uses `Begin ›`; final step uses `Finish ✦`.
6. Optional small pointer/tail toward the spotlight.

---

## 4. The 14-step sequence (final copy)

Voice: terse, second person, the world addressing a grim traveler. Opens beats with
"Delver,"; closes on a forward push. Uses the game's nouns (delve, carve, the dark,
soulstones, the forge). 1–2 sentences per box.

| # | Screen | Spotlight target (real control) | Headline | Wording-box copy | Advance |
|---|--------|---------------------------------|----------|------------------|---------|
| 1 | Fight | Battlefield (centered, no hole) | The delve never stops | Delver, your party fights without you — day and night, even when the game is shut. Watch them carve forward. | Begin |
| 2 | Fight | Floating damage numbers | Blood and mercy | Cream numbers are damage, ember crits bite deepest, green is healing. Every strike is real math, not theatre. | Next |
| 3 | Fight | Wave progress bar | Five waves to glory | Each stage is five waves. Fill this bar to push the boss and break into the next stage. | Next |
| 4 | Fight | Party DPS readout | Your killing speed | This is how fast your party deals death. Raise it with gear and talents — higher means deeper, faster. | Next |
| 5 | Fight | Hero frame (HP/mana) | Watch their vitals | Your delver's life and mana ride these bars. If the red runs dry, the advance stalls. | Next |
| 6 | Fight | SPEED 1×/2×/4× | Bend the clock | Click to fast-forward the carnage — 1×, 2×, 4×. Try 4× now and watch the bodies fall faster. | **Do** (change speed) |
| 7 | Fight | Auto-Skill toggle | Hands off the reins | With Auto-Skill lit, your abilities fire themselves. This is an idle crawl — let it run. | **Do** (toggle) |
| 8 | Resource strip | Portrait + name + XP bar | Your mark on the world | Your name, level, and renown sit here. Slain foes feed this bar — and your rank. | Next |
| 9 | Resource strip | Gold counter | The coin of the dead | Gold pours in from every kill. You'll spend it at the forge and on the road to power. | Next |
| 10 | Nav rail | HERO button | Tend your delver | Press 3 or click HERO. Loot means nothing until it's worn — let's arm you. | **Do** (open Hero) |
| 11 | Hero | Bag item → empty slot | Drag it onto your bones | Drag a piece of gear from the bag onto its slot. Feel your power climb. | **Do** (equip) |
| 12 | Hero | Talents tab | Carve your path | The talent web waits here — spend points to twist your build toward ruin or resilience. Explore it later. | Next |
| 13 | Nav rail | CAMP button | Return to the fire | Press 1 or click CAMP. Between delves, the camp is where you grow stronger. | **Do** (open Camp) |
| 14 | Camp | Summoning Altar building | Summon greater arms | The altar trades soulstones for gear from beyond. Save your pulls, then push deeper, delver. The dark won't wait. | Finish |

---

## 5. Per-screen element inventory (real controls, from the code)

The real, highlightable controls per screen — positions are at the 1920×1080 design
resolution. Tutorial targets are **bold**.

### Fight screen / battlefield HUD
- **Wave/stage label** — top-center: `STAGE 4-7 · Obsidian Abyss`.
- **Wave progress bar** (XP-gold fill) + `Wave 3 / 5` + **Party DPS** (e.g. `2.4M`) + 5 wave pips — top-center strip.
- **Hero frame** (bottom-left): portrait + role tag, `Warrior · Lv 42`, **HP bar** (`184K/184K`), mana bar, skill pips.
- **Floating damage numbers** on the battlefield: cream damage, ember crits, green heals.
- Control cluster (bottom-right): **SPEED `1× 2× 4×`**, **Auto-Skill** toggle, Auto-Advance toggle, Retreat.
- Party Finder panel (top-left): 4 hero slots, `CHARACTER`, `FIND PARTY / PARTY · 2/4`.
- Party Aura badge (top-right): `PARTY AURA · +20%`.
- Auto-loot ticker (right edge). Boss banner + boss HP (boss waves only). Battle Cache chests on the field. `Welcome back, delver` offline popup (returns).

### Resource strip (persistent chrome, top)
- **Portrait + character name + level + XP bar**.
- **Gold** counter (+ button), premium currency (soulstones), energy/stamina.

### Nav rail (persistent, left)
- **CAMP (1)** · FIGHT (2) · **HERO (3)** buttons.

### Hero window — Equipment tab
- Header: portrait, `Vael, the Forsaken`, **TOTAL POWER** readout, tabs Equipment/Pets/Relics/**Talents**.
- Char sheet: level badge, Attack DPS / Armour / Maximum Life rows, STR/DEX/INT/VIT/LCK attributes, detailed stats.
- Center **paperdoll**: silhouette + 10 gear slots (5 left, 5 right), GEAR POWER plate.
- Right **inventory bag**: tab selector (Equipment/Materials/Food/Quest), 6-col grid of 30 **item cells** (rarity border + icon + level + qty), footer currencies + `X / 30 SLOTS`.

### Camp hub
- Title `Hollowreach Camp` + `Camp Level 8 · …`.
- **Summoning Altar** (center-upper, featured, `NEW BANNER` badge, "Skill Learning House").
- Notice Board (`3 NEW`, Quests/Leaderboard/Daily), Crafting House (Forge/Upgrade/Salvage), Hearthfire Kitchen (cook buffs), Town Crier ticker.
- Modals open from each building (Gacha ×1/×10, Forge upgrade, Kitchen cook, Board tabs).

---

## 6. Design knobs / open questions for the design pass

- **Headline casing** — mockups use sentence case ("Bend the clock"); the in-game UI
  leans `TITLE CASE` / `UPPERCASE`. Pick one.
- **Progress indicator** — thin ember bar (as rendered) vs 14 discrete dots.
- **Wording-box placement** — fixed corner vs anchored to each spotlight (auto-flipping
  to stay on-screen). Mockups show anchored.
- **Pointer/tail** — keep the little diamond tail toward the spotlight, or drop it.
- **Intro framing** — centered "Begin" card (shown) vs starting straight on step 2.
- **Skip affordance** — per-box `Skip tour` (shown) vs a single corner `Skip ✕`.
- **Replay** — surfaced in Settings as "Replay tutorial".

---

## 7. Constraints

- **Resolution-agnostic.** Base 1920×1080 16:9; must scale cleanly. Steam Deck is
  1280×800 (16:10, letterboxed) — keep wording boxes inside a ~5% safe-area inset and
  auto-flip the anchor so nothing clips behind a letterbox bar. Buttons min ~120×40 for
  controller/touch.
- **Multi-window.** Camp / Hero / Leaderboard each open as their own OS window; the
  overlay mounts into whichever window owns the current step's target, and drives
  navigation between steps.
- **Voice** (recap): dark-gothic, terse, second person; the game's own nouns; menacing
  but instructive, never cute; 1–2 sentences per box; headlines ~5-word fragments.

---

## 8. Mockups (HTML sources)

Four self-contained HTML fragments covering the visual vocabulary. Hardcoded dark-gothic
hex (they depict the game, so they do not invert for light mode). Drop any of these into
a design tool to render/iterate. The spotlight is done two ways: a transparent element
with a huge `box-shadow` (single highlight) or a flat scrim with specific elements raised
above it via `z-index` (multi-highlight).

### 8a. Centered intro (step 1)

```html
<div style="position:relative; height:380px; background:#100e0b; border:1px solid #0c0a07; border-radius:8px; overflow:hidden; font-family:sans-serif;">
  <div style="position:absolute; left:8%; bottom:6%; width:230px; height:170px; background:#3a2410; opacity:.5; border-radius:50%;"></div>
  <div style="position:absolute; right:6%; top:8%; width:210px; height:160px; background:#3c1414; opacity:.45; border-radius:50%;"></div>
  <div style="position:absolute; left:50%; top:16px; transform:translateX(-50%); font-size:12px; letter-spacing:2px; color:#f0cf86;">STAGE 4-7 · OBSIDIAN ABYSS</div>
  <div style="position:absolute; inset:0; background:rgba(7,6,4,0.64); z-index:2;"></div>
  <div style="position:absolute; left:50%; top:50%; transform:translate(-50%,-50%); width:360px; z-index:5; background:#211d16; border:1px solid #0c0a07; border-radius:10px; padding:22px 24px; text-align:center;">
    <div style="font-size:10px; letter-spacing:2px; color:#7d7058;">STEP 1 / 14</div>
    <div style="margin:6px auto 0; width:90px; height:3px; background:#2a251c; border-radius:2px; overflow:hidden;"><div style="width:7%; height:100%; background:#e8843a;"></div></div>
    <div style="font-size:20px; color:#f0cf86; margin:14px 0 8px;">The delve never stops</div>
    <div style="font-size:13px; line-height:1.6; color:#ece0c8;">Delver, your party fights without you — day and night, even when the game is shut. Watch them carve forward.</div>
    <div style="display:flex; align-items:center; justify-content:center; gap:10px; margin-top:18px;">
      <span style="font-size:12px; color:#b3a489; padding:7px 14px; border:1px solid #3a3327; border-radius:4px;">Skip tour</span>
      <span style="font-size:12px; color:#1c0f04; background:#e8843a; padding:7px 20px; border-radius:4px;">Begin ›</span>
    </div>
  </div>
</div>
```

### 8b. Single spotlight — Fight / Speed (step 6)

```html
<div style="position:relative; height:380px; background:#100e0b; border:1px solid #0c0a07; border-radius:8px; overflow:hidden; font-family:sans-serif;">
  <div style="position:absolute; left:6%; bottom:4%; width:230px; height:170px; background:#3a2410; opacity:.5; border-radius:50%;"></div>
  <div style="position:absolute; right:5%; top:6%; width:210px; height:160px; background:#3c1414; opacity:.45; border-radius:50%;"></div>
  <div style="position:absolute; left:50%; top:16px; transform:translateX(-50%); width:58%; text-align:center;">
    <div style="font-size:12px; letter-spacing:2px; color:#f0cf86;">STAGE 4-7 · OBSIDIAN ABYSS</div>
    <div style="display:flex; align-items:center; gap:8px; margin-top:7px;">
      <span style="font-size:11px; color:#b3a489; white-space:nowrap;">WAVE 3/5</span>
      <div style="flex:1; height:9px; background:#241f17; border:1px solid #0c0a07; border-radius:5px; overflow:hidden;"><div style="width:58%; height:100%; background:#c9a24a;"></div></div>
      <span style="font-size:11px; color:#ffac5c; white-space:nowrap;">DPS 2.4M</span>
    </div>
  </div>
  <div style="position:absolute; left:33%; top:47%; font-size:13px; color:#fff2dd;">3214</div>
  <div style="position:absolute; left:53%; top:37%; font-size:17px; color:#ffac5c;">8472</div>
  <div style="position:absolute; left:43%; top:60%; font-size:13px; color:#8ef08a;">+42</div>
  <div style="position:absolute; left:16px; bottom:16px; width:214px; background:#161310; border:1px solid #0c0a07; border-bottom:2px solid #d6a24a; border-radius:4px; padding:8px; display:flex; gap:8px;">
    <div style="width:42px; height:42px; background:#241f17; border:1px solid #0c0a07; border-radius:3px;"></div>
    <div style="flex:1; min-width:0;">
      <div style="font-size:12px; color:#ece0c8;">Warrior · Lv 42</div>
      <div style="margin-top:6px; height:8px; background:#241f17; border-radius:4px; overflow:hidden;"><div style="width:100%; height:100%; background:#c0433a;"></div></div>
      <div style="margin-top:4px; height:6px; background:#241f17; border-radius:3px; overflow:hidden;"><div style="width:84%; height:100%; background:#3f9fd0;"></div></div>
    </div>
  </div>
  <div style="position:absolute; right:14px; bottom:18px; display:flex; align-items:center; gap:7px; padding:7px 11px; background:#1a1610; border:1px solid #0c0a07; border-radius:6px; font-size:11px; color:#7fe3f0;"><span style="width:8px;height:8px;border-radius:50%;background:#46c2d4;display:inline-block;"></span>Auto-Adv</div>
  <div style="position:absolute; right:120px; bottom:18px; display:flex; align-items:center; gap:7px; padding:7px 11px; background:#1a1610; border:1px solid #0c0a07; border-radius:6px; font-size:11px; color:#7fe3f0;"><span style="width:8px;height:8px;border-radius:50%;background:#46c2d4;display:inline-block;"></span>Auto-Skill</div>
  <div style="position:absolute; right:224px; bottom:14px; display:flex; align-items:center; gap:8px; padding:8px 12px; background:#19150f; border:2px solid #ffac5c; border-radius:8px; box-shadow:0 0 0 2000px rgba(7,6,4,0.77);">
    <span style="font-size:10px; letter-spacing:1px; color:#d3ad62;">SPEED</span>
    <span style="font-size:12px; color:#1c0f04; background:#e8843a; padding:4px 9px; border-radius:4px;">1×</span>
    <span style="font-size:12px; color:#b3a489; background:#2a251c; padding:4px 9px; border-radius:4px;">2×</span>
    <span style="font-size:12px; color:#b3a489; background:#2a251c; padding:4px 9px; border-radius:4px;">4×</span>
  </div>
  <div style="position:absolute; right:150px; bottom:92px; width:250px; z-index:5; background:#211d16; border:1px solid #0c0a07; border-radius:8px; padding:14px 16px;">
    <div style="font-size:10px; letter-spacing:2px; color:#7d7058;">STEP 6 / 14</div>
    <div style="margin-top:4px; height:3px; background:#2a251c; border-radius:2px; overflow:hidden;"><div style="width:43%; height:100%; background:#e8843a;"></div></div>
    <div style="font-size:16px; color:#f0cf86; margin:9px 0 6px;">Bend the clock</div>
    <div style="font-size:13px; line-height:1.5; color:#ece0c8;">Click to fast-forward the carnage — 1×, 2×, 4×. Try 4× now and watch the bodies fall faster.</div>
    <div style="display:flex; align-items:center; justify-content:flex-end; gap:8px; margin-top:13px;">
      <span style="font-size:12px; color:#b3a489; padding:6px 12px; border:1px solid #3a3327; border-radius:4px;">Skip tour</span>
      <span style="font-size:12px; color:#1c0f04; background:#e8843a; padding:6px 14px; border-radius:4px;">Next ›</span>
    </div>
    <div style="position:absolute; left:70px; bottom:-7px; width:12px; height:12px; background:#211d16; border-right:1px solid #0c0a07; border-bottom:1px solid #0c0a07; transform:rotate(45deg);"></div>
  </div>
</div>
```

### 8c. Multi-highlight + drag arrow — Hero / equip (step 11)

```html
<div style="position:relative; height:380px; background:#100e0b; border:1px solid #0c0a07; border-radius:8px; overflow:hidden; font-family:sans-serif;">
  <div style="position:absolute; left:14px; top:14px; bottom:14px; width:176px; background:#161310; border:1px solid #0c0a07; border-radius:6px; padding:12px;">
    <div style="font-size:13px; color:#f0cf86;">Vael, the Forsaken</div>
    <div style="font-size:10px; color:#7d7058; margin-top:2px;">Warrior · Lv 42 · Prestige I</div>
    <div style="margin-top:12px; background:#100d09; border:1px solid #0c0a07; border-radius:5px; padding:9px 10px;">
      <div style="font-size:9px; letter-spacing:1px; color:#7d7058;">TOTAL POWER</div>
      <div style="font-size:22px; color:#f0cf86; margin-top:2px;">48,210</div>
    </div>
    <div style="margin-top:12px; display:flex; flex-direction:column; gap:7px; font-size:12px;">
      <div style="display:flex; justify-content:space-between;"><span style="color:#b3a489;">Attack DPS</span><span style="color:#ffac5c;">2.4M</span></div>
      <div style="display:flex; justify-content:space-between;"><span style="color:#b3a489;">Armour</span><span style="color:#ece0c8;">8,140</span></div>
      <div style="display:flex; justify-content:space-between;"><span style="color:#b3a489;">Maximum Life</span><span style="color:#c0433a;">184K</span></div>
    </div>
  </div>
  <div style="position:absolute; left:206px; top:14px; bottom:14px; width:226px; background:#13110d; border:1px solid #0c0a07; border-radius:6px;">
    <div style="position:absolute; left:50%; top:24px; transform:translateX(-50%); width:96px; height:300px; background:#1a1610; border:1px solid #241f17; border-radius:14px;"></div>
    <div style="position:absolute; left:50%; bottom:18px; transform:translateX(-50%); font-size:9px; letter-spacing:1px; color:#7d7058; background:#100d09; border:1px solid #0c0a07; padding:3px 8px; border-radius:3px;">GEAR POWER 31,540</div>
    <div style="position:absolute; right:12px; top:60px; width:40px; height:40px; background:#100d09; border:2px solid #a661d6; border-radius:5px;"></div>
    <div style="position:absolute; right:12px; top:150px; width:40px; height:40px; background:#100d09; border:2px solid #4a8fd6; border-radius:5px;"></div>
    <div style="position:absolute; left:12px; top:150px; width:40px; height:40px; background:#100d09; border:2px solid #e6a93a; border-radius:5px;"></div>
    <div style="position:absolute; left:12px; top:60px; width:40px; height:40px; background:#1c1409; border:2px dashed #ffac5c; border-radius:5px; z-index:3; display:flex; align-items:center; justify-content:center; color:#d3ad62; font-size:9px;">HELM</div>
  </div>
  <div style="position:absolute; left:450px; top:14px; bottom:14px; width:184px; background:#13110d; border:1px solid #0c0a07; border-radius:6px; padding:10px;">
    <div style="display:flex; justify-content:space-between; align-items:center; font-size:11px;"><span style="color:#f0cf86; letter-spacing:1px;">◆ EQUIPMENT</span><span style="color:#7d7058;">12 / 30</span></div>
    <div style="margin-top:10px; display:grid; grid-template-columns:repeat(4, 1fr); gap:6px;">
      <div style="aspect-ratio:1; background:#100d09; border:2px solid #ffac5c; border-radius:4px; z-index:3; position:relative; display:flex; align-items:center; justify-content:center; box-shadow:0 0 0 1px #1c0f04;"><span style="width:16px;height:16px;background:#e6a93a;border-radius:3px;"></span></div>
      <div style="aspect-ratio:1; background:#100d09; border:1px solid #4a8fd6; border-radius:4px;"></div>
      <div style="aspect-ratio:1; background:#100d09; border:1px solid #5fa64e; border-radius:4px;"></div>
      <div style="aspect-ratio:1; background:#100d09; border:1px solid #2a251c; border-radius:4px;"></div>
      <div style="aspect-ratio:1; background:#100d09; border:1px solid #a661d6; border-radius:4px;"></div>
      <div style="aspect-ratio:1; background:#100d09; border:1px solid #2a251c; border-radius:4px;"></div>
      <div style="aspect-ratio:1; background:#100d09; border:1px solid #8c8579; border-radius:4px;"></div>
      <div style="aspect-ratio:1; background:#100d09; border:1px solid #2a251c; border-radius:4px;"></div>
    </div>
  </div>
  <div style="position:absolute; inset:0; background:rgba(7,6,4,0.74); z-index:2;"></div>
  <svg viewBox="0 0 648 380" style="position:absolute; inset:0; width:100%; height:100%; z-index:4; pointer-events:none;">
    <defs><marker id="ah" viewBox="0 0 10 10" refX="7" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M1 1L8 5L1 9" fill="none" stroke="#ffac5c" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></marker></defs>
    <path d="M468 74 C 408 56, 330 70, 270 96" fill="none" stroke="#ffac5c" stroke-width="2" stroke-dasharray="6 5" marker-end="url(#ah)"/>
  </svg>
  <div style="position:absolute; left:206px; bottom:20px; width:300px; z-index:5; background:#211d16; border:1px solid #0c0a07; border-radius:8px; padding:14px 16px;">
    <div style="font-size:10px; letter-spacing:2px; color:#7d7058;">STEP 11 / 14</div>
    <div style="margin-top:4px; height:3px; background:#2a251c; border-radius:2px; overflow:hidden;"><div style="width:79%; height:100%; background:#e8843a;"></div></div>
    <div style="font-size:16px; color:#f0cf86; margin:9px 0 6px;">Drag it onto your bones</div>
    <div style="font-size:13px; line-height:1.5; color:#ece0c8;">Drag a piece of gear from the bag onto its slot. Feel your power climb.</div>
    <div style="display:flex; align-items:center; justify-content:flex-end; gap:8px; margin-top:13px;">
      <span style="font-size:12px; color:#b3a489; padding:6px 12px; border:1px solid #3a3327; border-radius:4px;">Skip tour</span>
      <span style="font-size:12px; color:#1c0f04; background:#e8843a; padding:6px 14px; border-radius:4px;">Next ›</span>
    </div>
  </div>
</div>
```

### 8d. Building spotlight — Camp / altar (step 14, finale)

```html
<div style="position:relative; height:380px; background:#0d0b08; border:1px solid #0c0a07; border-radius:8px; overflow:hidden; font-family:sans-serif;">
  <div style="position:absolute; left:10%; bottom:0; width:280px; height:150px; background:#3a2410; opacity:.4; border-radius:50%;"></div>
  <div style="position:absolute; left:18px; top:14px;">
    <div style="font-size:18px; color:#f0cf86;">Hollowreach Camp</div>
    <div style="font-size:11px; color:#7d7058; margin-top:2px;">Camp Level 8 · 4 buildings · 2 expansions locked</div>
  </div>
  <div style="position:absolute; left:34px; top:210px; width:158px; height:120px; background:#161310; border:1px solid #0c0a07; border-radius:6px; padding:12px;">
    <div style="position:absolute; top:8px; right:8px; font-size:8px; letter-spacing:1px; color:#1c0f04; background:#e8843a; padding:2px 6px; border-radius:2px;">3 NEW</div>
    <div style="height:48px; background:#100d09; border:1px solid #241f17; border-radius:4px;"></div>
    <div style="font-size:13px; color:#f0cf86; margin-top:8px;">Notice Board</div>
    <div style="font-size:10px; color:#7d7058; margin-top:2px;">Quests · Leaderboard · Daily</div>
  </div>
  <div style="position:absolute; right:34px; top:186px; width:168px; height:128px; background:#161310; border:1px solid #0c0a07; border-radius:6px; padding:12px;">
    <div style="height:54px; background:#100d09; border:1px solid #241f17; border-radius:4px;"></div>
    <div style="font-size:13px; color:#f0cf86; margin-top:8px;">Crafting House</div>
    <div style="font-size:10px; color:#7d7058; margin-top:2px;">Forge · Upgrade · Salvage</div>
  </div>
  <div style="position:absolute; left:236px; top:248px; width:150px; height:96px; background:#161310; border:1px solid #0c0a07; border-radius:6px; padding:10px;">
    <div style="height:34px; background:#100d09; border:1px solid #241f17; border-radius:4px;"></div>
    <div style="font-size:12px; color:#f0cf86; margin-top:6px;">Hearthfire Kitchen</div>
  </div>
  <div style="position:absolute; left:228px; top:52px; width:194px; height:152px; background:#1a1610; border:2px solid #ffac5c; border-radius:8px; padding:14px; box-shadow:0 0 0 2000px rgba(8,7,5,0.78);">
    <div style="position:absolute; top:10px; right:10px; font-size:8px; letter-spacing:1px; color:#1c0f04; background:#e6a93a; padding:2px 7px; border-radius:2px;">NEW BANNER</div>
    <div style="height:74px; background:#120f0a; border:1px solid #3a2a12; border-radius:5px; display:flex; align-items:center; justify-content:center; color:#e6a93a; font-size:24px;">◆</div>
    <div style="font-size:16px; color:#f0cf86; margin-top:10px; text-align:center;">Summoning Altar</div>
    <div style="font-size:10px; color:#b3a489; margin-top:2px; text-align:center;">Skill Learning House</div>
  </div>
  <div style="position:absolute; left:184px; top:222px; width:282px; z-index:5; background:#211d16; border:1px solid #0c0a07; border-radius:8px; padding:14px 16px;">
    <div style="font-size:10px; letter-spacing:2px; color:#7d7058;">STEP 14 / 14</div>
    <div style="margin-top:4px; height:3px; background:#2a251c; border-radius:2px; overflow:hidden;"><div style="width:100%; height:100%; background:#e8843a;"></div></div>
    <div style="font-size:16px; color:#f0cf86; margin:9px 0 6px;">Summon greater arms</div>
    <div style="font-size:13px; line-height:1.5; color:#ece0c8;">The altar trades soulstones for gear from beyond. Save your pulls, then push deeper, delver. The dark won't wait.</div>
    <div style="display:flex; align-items:center; justify-content:flex-end; gap:8px; margin-top:13px;">
      <span style="font-size:12px; color:#b3a489; padding:6px 12px; border:1px solid #3a3327; border-radius:4px;">Skip</span>
      <span style="font-size:12px; color:#1c0f04; background:#e8843a; padding:6px 16px; border-radius:4px;">Finish ✦</span>
    </div>
  </div>
</div>
```

---

## 9. Implementation target (for context, not design)

The eventual build is a code-side `TutorialOverlay` (a dim+spotlight `CanvasLayer` mounted
into the active window) driven by a data-driven step list, resolving targets by string key
through an anchor registry, persisting a `tutorial_done` flag in `user://netstate.json`
(not the save blob). Design should produce: final copy + casing, the wording-box layout,
the spotlight/scrim treatment, and the box anchoring rules. Nothing in the design needs to
account for the code — just the visuals and copy above.
