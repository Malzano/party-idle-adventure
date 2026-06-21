# Floor 1 art-generation prompts — "The Sunken Reliquary"

Copy-paste prompts for **ChatGPT / GPT-4o image generation** to produce the parallax background +
every object for the game's first floor. Locked to the real in-game palette, sizes, perspective, and
theme so the results drop into the 2D side-scroller battlefield.

**How to use:** In a fresh ChatGPT chat, paste **§0 (the Style Bible)** first as its own message so the
model locks the look, then paste one asset prompt per message. Re-paste §0 if the style drifts. Ask for
**a transparent-background PNG** every time. Generate large, then downscale to the px size noted per asset.

**Bundle map (where each file goes in the repo):** characters → `res://assets/core/class.<id>/` or
`hero.<id>/`; enemies → `enemy.skeleton` / `enemy.ghoul` / `enemy.elite`; props → `props.dungeon/<kind>.png`;
chest → `chest/`. Each animated bundle is `meta.json` + atlas PNG (walk = 4 frames, idle = 2 frames, one
side-facing direction). The parallax background images need new layer bundles + a small code change to draw
textures instead of the current procedural layers — flag me to wire that when the art is ready.

**How these sprites move & "act" in-game (read before §3–§5):** the battlefield drives almost all motion in
CODE, not in the art — a **single static pose** already walks, attacks, takes hits, and dies:
- **Walk/travel** — the background scrolls and the engine adds a procedural bob, so the sprite reads as striding in place.
- **Facing** — the engine flips sprites horizontally. **Draw EVERYTHING facing RIGHT;** heroes stay right, enemies/bosses are auto-mirrored to face the party.
- **Attack** — melee = the engine dashes the hero forward & back; ranged = it fires a projectile. *No attack frames.*
- **Hit** — the struck sprite flashes bright. **Death** — it squashes flat and fades out. *No hit/death frames.*

So you only need **one clean pose per character.** *Optionally*, for extra life, add a **4-frame walk** and/or
**2-frame idle** atlas — the only frame animations the engine plays; attacks and deaths stay code-driven. Hand
me the PNG(s) and I package the bundle (`meta.json` + atlas).

---

## 0. STYLE BIBLE  (paste this FIRST, once)

> You are generating 2D game art for a dark-gothic idle dungeon-crawler (mood: Diablo / Path of Exile).
> Hold this style for everything that follows.
>
> **Art style:** crisp **pixel art**, limited palette, bold readable silhouettes, painterly dithered
> shading, gritty and grim — not cute, not cartoonish. Heavy contrast; subjects lit by warm torchlight
> from one side with deep black shadow on the other.
> **Perspective:** flat **2D side view** (orthographic, like a side-scroller / Castlevania) — NO 3/4,
> NO isometric, NO perspective foreshortening. Subjects stand upright with feet level along the bottom.
> **Palette (use these exact colors):** deepest backgrounds charcoal-black `#0a0908`, `#18150f`,
> `#211d16`; warm ember torchlight `#e8843a`, `#ffac5c`, `#b85a1f`; dull tarnished gold `#d3ad62`,
> `#f0cf86`; cold arcane cyan `#46c2d4`, `#7fe3f0`; blood red `#c0433a`; bone/parchment `#ece0c8`.
> Accents only — keep it dark.
> **Theme — Floor 1 "The Sunken Reliquary":** a flooded, half-collapsed gothic crypt / ossuary you
> descend into — cracked stone, ankle-deep black water, bone piles, broken pillars, iron braziers,
> tattered banners, faint cyan grave-mist.
> **Output rules:** ONE subject, centered, on a **fully transparent background** (alpha PNG), no ground,
> no cast shadow (the game adds shadows), no text, no UI, no frame, no border. Generate at high
> resolution for clean downscaling.

---

## 1. PARALLAX BACKGROUND  (3 transparent scrolling layers + 1 opaque ground strip)

> **Why the first batch was wrong:** each image baked in its own water/ground at the bottom, on a white
> background. Stacked, that gives multiple clashing waterlines and white boxes — and the painted water sat
> *below* where the hero actually stands. The engine puts the hero's **feet on a floor line two-thirds (66%)
> down from the top** (the bottom third of the frame is floor; the top two-thirds is open cavern). So the
> background must be split into **see-through scenery** + **one real floor**, all pinned to that same line.

**Shared rules for ALL FOUR images (read before generating any):**
- Canvas **1536×1024 landscape**. Treat the horizontal line **two-thirds down (~676 px)** as the **FLOOR LINE**.
- **Transparent background with real alpha.** Say *"transparent PNG, alpha channel, NO background, NO white
  fill, NO solid backdrop."* (The last batch came back on white — demand transparency explicitly.)
- **Tileable left↔right:** the left and right edges must match seamlessly for the scroll-wrap. Use an **even
  repeating rhythm** of pillars/arches — no single hero element dead-center.
- NO characters, NO text, NO border, NO cast shadows.

The three scenery layers (1a–1c) are **see-through** and must keep the **bottom third fully empty/transparent**
(the ground strip covers it). The ground strip (1d) is the **only** thing that paints a floor.

**1a — FAR layer (distant cathedral haze):**
> Far parallax layer for a dark gothic crypt side-scroller, established style, 1536×1024, **transparent PNG
> with alpha — no background, no white fill.** A faint, hazy silhouette of a vast sunken cathedral: rows of
> tall broken pointed arches and distant columns fading into charcoal-black fog, a sliver of cold cyan
> `#46c2d4` grave-light. Very low contrast, `#18150f` with cyan haze. Scenery occupies the **upper two-thirds
> only — the bottom third is completely empty/transparent.** Tileable left↔right (left and right edges match).
> No characters, no floor, no water, no text.

**1b — MID layer (pillars + arches — the main depth):**
> Mid parallax layer, established style, 1536×1024, **transparent PNG with alpha — no white background.** An
> evenly spaced colonnade of cracked gothic stone pillars and ribbed arches, a couple of guttering iron
> braziers casting ember `#e8843a` pools, one tattered banner. Medium contrast, charcoal stone with ember
> glow. **The pillar bases rest on a floor line two-thirds down; everything BELOW that line is fully
> transparent/empty — do NOT paint any floor or water.** Tileable left↔right (edges match for seamless repeat).
> No characters, no text.

**1c — NEAR layer (foreground dressing):**
> Near foreground parallax layer, established style, 1536×1024, **transparent PNG with alpha — no white
> background.** Sparse, larger, high-contrast crypt dressing standing along the floor line: a chunk of broken
> masonry, a toppled column, a bone pile, an iron rail — mostly black silhouette. All elements **REST ON the
> floor line two-thirds down; the bottom third below it is fully transparent**, and the empty gaps above are
> transparent too (this is scattered foreground props, not a solid wall). Tileable left↔right. No characters,
> no painted floor or water.

**1d — GROUND STRIP (the floor the hero walks on — the ONLY floor):**
> Floor layer for the crypt side-scroller, established style, 1536×1024, **transparent PNG with alpha.** The
> **top two-thirds is completely transparent/empty.** The **bottom third is a SOLID, opaque, walkable
> cracked-stone floor** — wet dark flagstones, cracks, with only a thin sheen of shallow water and faint
> ember reflections ON TOP of the stone (a wet floor you stand on, NOT deep water you sink into). Its **top
> edge — the walking surface — is a clean, roughly horizontal line two-thirds down the canvas.** Tileable
> left↔right (edges match). No characters, no pillars, no text.

> *(The dark cavern gradient + the warm ember glow on the LEFT and red danger glow on the RIGHT stay
> procedural in-engine, so the far layer can be fully transparent and composite over them — you don't need
> to generate those.)*

---

## 2. ENVIRONMENT PROPS  (side view, transparent, scroll past the party)

Each: single object, side view, transparent background. Downscale target in brackets.

- **Broken pillar** `[~86×158 px → props.dungeon/pillar.png]`
  > A single cracked, crumbling gothic stone pillar, side view, established style. Weathered grey-brown
  > stone, broken top, hairline cracks, faint moss, base in shadow. Transparent background.
- **Iron brazier (lit)** `[~56×84 → props.dungeon/brazier.png]`
  > A wrought-iron crypt brazier on a tripod with a low ember `#ffac5c` flame and glowing coals, side
  > view, established style. Dark iron, warm ember light from the fire. Transparent background.
- **Tomb / rubble pile** `[~94×60 → props.dungeon/rubble.png]`
  > A cracked stone sarcophagus lid half-buried in rubble and bone shards, side view, established style.
  > Grey weathered stone, a few scattered bones, dust. Transparent background.
- **Dead tree** `[~94×152 → props.dungeon/tree.png]`
  > A leafless, gnarled dead tree growing through cracked crypt stone, side view, established style. Black
  > twisted branches, no leaves, grim silhouette. Transparent background.
- **Mossy rock** `[~72×54 → props.dungeon/rock.png]`
  > A wet, mossy boulder with cracks, side view, established style. Dark grey stone, faint green moss,
  > sitting in shallow black water. Transparent background.

---

## 3. HEROES  (4 classes — FACING RIGHT, transparent)  `[~98×132 px each]`

All heroes **face RIGHT** (toward the enemies), full body, mid-stride combat-ready pose, side view.
Bundle: `class.<id>/fig.png` (static) — or ask for a "4-frame horizontal walk strip" for `hero.<id>`.

- **Warrior** `[class.warrior]`
  > A grim plate-armoured warrior delver, full body, side view facing RIGHT, established style. Dark
  > dented steel armour, a heavy two-handed sword resting on the shoulder, tattered crimson `#c0433a`
  > tabard, scarred and weathered. Heroic, battle-ready stance. Transparent background.
- **Mage** `[class.mage]`
  > A hooded arcane mage delver, full body, side view facing RIGHT, established style. Dark robes with
  > cold cyan `#46c2d4` arcane glow at the hands and a glowing orb, gold `#d3ad62` trim, gaunt face in
  > shadow under the hood. Casting stance. Transparent background.
- **Hunter** `[class.hunter]`
  > A cloaked ranger/hunter delver, full body, side view facing RIGHT, established style. Dark leather
  > armour and hood, a drawn longbow with a faint ember `#e8843a` arrow nocked, quiver on the back,
  > lean and agile. Aiming stance. Transparent background.
- **Rogue** `[class.rogue]`
  > A hooded rogue delver, full body, side view facing RIGHT, established style. Dark close-fitting
  > leathers, twin daggers with faint cyan `#7fe3f0` edge-glow, a half-mask, crouched and ready to
  > strike. Transparent background.

---

## 4. ENEMIES  (Floor 1 roster — FACING RIGHT, transparent)

> **Draw enemies FACING RIGHT** (same direction as the heroes). The engine **mirrors them automatically**
> (`scale.x = -1`) so they face left toward your party — a left-facing drawing would end up facing the wrong
> way. One authoring direction for everything; the game flips per side.

Grim, decayed, crypt-dwelling. Bundle in brackets.

- **Crypt Rat** (trash) `[~72×96 → enemy.skeleton or a new enemy.crypt_rat]`
  > A large diseased crypt rat, side view facing RIGHT, established style. Matted dark fur, glowing
  > sickly cyan eyes, bony tail, hunched and snarling, scuttling pose. Transparent background.
- **Hollow Ghoul** (trash) `[~72×96 → enemy.ghoul]`
  > A gaunt undead ghoul, side view facing RIGHT, established style. Grey rotting flesh over bone,
  > sunken glowing cyan eye-sockets, tattered grave-shroud, long clawed arms, shambling lurch.
  > Transparent background.
- **Bonepicker Brute** (elite) `[~104×134 → enemy.elite]`  *(no baked aura — the engine adds the elite glow)*
  > A hulking undead bone-brute elite, full body, side view facing RIGHT, established style. A massive
  > ogre-sized skeleton wrapped in dried sinew and rusted scrap armour, wielding a bone club. Imposing,
  > menacing. Isolated figure on a FULLY TRANSPARENT background — NO aura, NO flames, NO black backdrop,
  > NO dark halo behind the figure, nothing but the figure on transparent alpha. No shadow, no text.

---

## 5. BOSSES  (large, FACING RIGHT — engine mirrors them to face the party, transparent)  `[~150×188 px each]`

> **No baked auras.** The engine draws a colored glow/ring behind elites and bosses, so a painted flame
> aura is redundant AND it makes background-removal bleed into opaque black (a dark halo). Generate the
> figure ONLY, isolated on transparent alpha.

- **Marrow Knight** (mini-boss, sub-stage 1-5) `[enemy.elite variant]`
  > A towering undead knight boss, full body, side view facing RIGHT, established style. Blackened
  > bone-plate armour fused with marrow, a great two-handed sword, a cracked helm with cold cyan
  > `#46c2d4` soul-fire in the visor. Grand, threatening boss silhouette. Isolated figure on a FULLY
  > TRANSPARENT background — NO aura, NO flames, NO black backdrop, NO dark halo behind the figure. No
  > shadow, no text.
- **The Bone Warden** (floor boss, sub-stage 1-10) `[enemy.elite variant]`
  > The Bone Warden — a colossal crypt-lord boss, full body, side view facing RIGHT, established style. A
  > giant armoured skeleton draped in a tattered gold-trimmed `#d3ad62` royal shroud, crowned, holding a
  > bone scepter, a chest-cage of fused skulls. Epic final-boss presence, intricate. Isolated figure on a
  > FULLY TRANSPARENT background — NO aura, NO flames, NO black backdrop, NO dark halo behind the figure.
  > No shadow, no text.

---

## 6. PROJECTILES + COMBAT VFX  (small, transparent, glowing)

- **Mage orb** `[~32×32 → spark]`
  > A glowing arcane energy orb projectile, established style. Bright cyan `#7fe3f0` core fading to
  > `#46c2d4`, soft glow halo, a tiny sparkle. Side view, motion to the RIGHT. Transparent background.
- **Hunter arrow** `[~48×16 → spark]`
  > A glowing ember arrow streak projectile, established style. Bright `#ffac5c` tip with an ember
  > `#e8843a` trailing streak, pointing RIGHT. Transparent background.
- **Impact flash** `[~48×48]`
  > A small bright impact burst / hit-spark, established style, warm ember `#ffac5c` with cyan flecks,
  > radial. Transparent background.

---

## 7. BATTLE CACHE (chest)  `[~58×48 → chest/chest.png]`

> A closed crypt treasure chest, side view, established style. Dark iron-banded wood, tarnished gold
> `#d3ad62` lock and trim, a faint gold `#f0cf86` glint, sitting on wet stone. Grim but enticing.
> Transparent background.

---

## Tips for consistency
- Keep the **same chat** so the model remembers the Style Bible; if it drifts, re-paste §0.
- Always end with **"transparent background, no shadow, no text."**
- For animations, ask: *"now the same <subject>, as a 4-frame horizontal walk-cycle sprite strip, evenly
  spaced, identical style and proportions, transparent background."* (GPT image gen is inconsistent at
  multi-frame sheets — generating one clean pose and animating in-engine/with a pixel tool is often
  cleaner; the game also runs fine with a single static frame.)
- Hand me the PNGs and I'll wire them into the bundles + (for the background) swap the procedural parallax
  layers to draw your images.
