# Tutorial design brief — first-session spotlight coachmarks

> **Purpose.** A complete, self-contained brief for the new-player tutorial of
> **BinkBonk Idle** — a cozy/cute (Soul Strike / MapleStory energy) party idle
> adventure. It contains the UX pattern, the visual tokens, the final 15-beat copy,
> the real on-screen targets, and the constraints. The **visual source of truth** is
> the Claude Design prototype ("party idle game" project — `tutorial.jsx` +
> `tutorial.css`); this file records what shipped in the Godot build
> (`autoload/TutorialOverlay.gd` + `scenes/ui/TutorialLayer.gd`).

---

## 1. The pattern

First-session **spotlight coachmarks**: dim the active window under a soft navy scrim,
cut a rounded hole around ONE real control, and pin a cream wording box beside it.
Two advance modes:

- **Advance-by-Next** (info beats): a chubby "Next ›" button; Enter also advances.
- **Advance-by-Doing** (live beats): the spotlit control stays fully interactive and the
  tour only advances when the player actually does the thing (switch to 4×, toggle
  Auto-Skill, open HERO/CAMP, equip an item). A hint line ("▸ Tap 4× to continue")
  replaces the button. A "do" beat with nothing to do (empty bag) downgrades to Next —
  the player can never get stuck.

Esc (or "Skip tour") exits any time; the tour marks done in `user://tutorial.json` and
can be replayed from Options.

## 2. Visual style tokens

All from the shipped BinkBonk system (`Palette.gd` / `Style.gd` / `Fonts.gd`):

- Scrim: `rgba(18,20,45,.78)` (`.66` on the intro), soft navy — never pure black.
- Wording box: cream `#fffaec→#fff3da` card, 3px honey `#c08040` border, radius 16,
  candy corner dots, warm bottom ledge; tail chevron points at the hole.
- Headline: Baloo 2 (wght 800), cocoa `#4a3826`. Body: system sans, `#7a6248`.
- Progress: "STEP n / 15" pixel chip (Pixelify Sans) + honey XP-style progress sliver.
- Spotlight ring: 2px `#ffc84a` rounded ring with a soft glow; secondary ring + dashed
  gold drag-arrow on the equip beat.
- Buttons: chubby candy (`Style.make_button`) — peach CTA, ghost skip.

## 3. Coachmark anatomy

Four dim bands (top/bottom/left/right of the hole) swallow clicks everywhere except the
hole; the box auto-places below/above/left/right with flip + clamp; targets re-measure on
a 0.1s poll so moving layouts stay ringed. Multi-window aware: the layer mounts into the
design-space host of whichever OS window owns the beat's target.

## 4. The 15-beat sequence (final copy — shipped in TutorialOverlay.STEPS)

| # | Screen | Mode | Target | Headline | Body |
|---|--------|------|--------|----------|------|
| 1 | fight | intro | — | The party never stops! | Hi friend! Your party adventures without you — day and night, even while the game naps. Watch them skip along and bonk baddies. |
| 2 | fight | next | battlefield clash zone | Bonks and boo-boos | White numbers are bonks, big golden ones are critical bonks, and green means healing. Every number is real math, promise! |
| 3 | fight | next | wave bar | Five waves to victory | Each stage is five waves. Fill this bar to reach the boss and hop into the next stage. |
| 4 | fight | next | DPS readout | Your bonking speed | This is how fast your party bonks. Raise it with gear and talents — more bonk means further, faster! |
| 5 | fight | next | hero frame | Keep an eye on your pals | Each pal's life and mana live on these bars. If the red runs low, the adventure slows down while they catch their breath. |
| 6 | fight | **do** | speed cluster | Zoom zoom! | Click to fast-forward the fun — 1×, 2×, 4×. Try 4× now and watch the party zoom! *(▸ Tap 4×)* |
| 7 | fight | **do** | auto-skill toggle | Hands-free heroics | With Auto-Skill glowing, your pals cast their abilities all by themselves. It's an idle adventure — let it roll! *(▸ Toggle)* |
| 8 | fight | next | strip level | That's you! | Your name, level, and renown live here. Every bonked baddie feeds this bar — and your rank. |
| 9 | fight | next | strip coins | Shiny shiny coins | Coins roll in from every bonk. Spend them at the Tinker Shop and on the road to greatness. |
| 10 | fight | **do** | nav HERO | Dress up your hero | Press 3 or click HERO. Loot is just clutter until it's worn — let's get you looking snazzy. *(▸ Open HERO)* |
| 11 | profile | **do** | inventory + gear slot (arrow) | Pop it on! | Drag a piece of gear from the bag onto its slot and feel your power climb. Ooh, sparkly. *(▸ Equip)* |
| 12 | profile | next | Talents tab | Pick your sparkle | The talent web lives here — spend points to shape your build toward big bonks or big snuggles. Explore it later! |
| 13 | fight | **do** | nav CAMP | Back to the campfire | Press 1 or click CAMP. Between adventures, the meadow is where you grow stronger (and eat snacks). *(▸ Open CAMP)* |
| 14 | camp | next | **Stampede Gate** | Feeling brave? | The Stampede Gate opens the Star Stampede — a solo run where YOU steer with WASD while baddies pour in from everywhere. Pack your charm backpack first: where each charm sits matters! |
| 15 | camp | finish | Wishing Well | Make a wish! | The Wishing Well trades stardrops for wonderful new gear. Save up your wishes, then hop deeper, friend — adventure awaits! *(Finish ✦)* |

Beat 14 is the BinkBonk addition: it introduces the survival mode + backpack right where
its entrance lives (anchor key `camp.gate`, registered by the Stampede Gate building).

## 5. Per-screen element inventory (anchor keys, from the code)

- **Fight:** `fight.battlefield` (+`frac` clash-zone sub-rect), `fight.wavebar`,
  `fight.dps`, `fight.heroframe`, `fight.speed`, `fight.autoskill`.
- **Resource strip:** `strip.level`, `strip.gold` (main window only).
- **Nav rail:** `nav.hero`, `nav.camp` (RUMBLE/`survival` exists but is not toured —
  beat 14 sells it from the camp instead).
- **Hero window:** `hero.inventory`, `hero.gearslot`, `hero.talents`.
- **Camp:** `camp.gate` (Stampede Gate), `camp.altar` (Wishing Well, the finale).

## 6. Design knobs

- Beat count is data (`TutorialOverlay.STEPS`); the layer renders any count.
- `prefer` placement per beat; auto-flip handles window resizes.
- `advance_on` maps to EventBus signals: `speed4`, `autoskill`, `hero_open`, `equip`,
  `camp_open`.

## 7. Constraints

- 1920×1080 design space; the popup stage scales — target rects are converted through
  the owning host's transform (see `_resolve_rect` tests).
- The overlay must never hard-block progress: "do" beats poll real state, downgrade
  when impossible, and Esc always exits.
- Copy must respect the BinkBonk voice: friendly, bouncy, no gothic vocabulary, no
  threats — the world *invites*, it never warns.
- Readability floors: body ≥ 14px-equivalent (`Style.fs`), pixel labels ≥ 12.

## 8. Mockups

The original dark-gothic HTML mockups are superseded. The live visual reference is the
**Claude Design prototype** (project "party idle game": `tutorial.jsx`, `tutorial.css`) —
its STEPS array is the copy source of truth and matches §4 verbatim.

## 9. Implementation target

`autoload/TutorialOverlay.gd` (controller: anchors registry, step flow, persistence,
multi-window hosting) + `scenes/ui/TutorialLayer.gd` (visuals: bands, ring, wording box,
tail, progress). Covered by `test/unit/test_tutorial.gd` (15-step assertion, anchor
liveness, transform math, placement flips).
