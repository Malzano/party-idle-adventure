# BinkBonk Idle — art regeneration prompt pack

The UI is code‑drawn and already reskinned. The **battlefield/camp art is committed PNGs**
in `assets/core/<bundle>/<key>.png` — 47 files still in the old gothic style. This pack
regenerates them cozy. **Drop the new PNG at the SAME path** (same folder + filename +
pixel size) and the game picks it up on the next `--import`; the folder names
(`bg.reliquary`, `enemy.ghoul`, …) are internal keys and are never shown, so you don't
touch any code.

## How to use
1. Generate each image with the **shared style preamble** + the per‑asset line.
2. Save it to the exact path at (about) the listed size.
3. Re‑import: open the project once in Godot, or run `--headless --path . --import`.

**Transparency is mandatory** for every character / enemy / prop / building / chest —
the game composites them over the scene. Only the four **parallax** layers are full‑bleed
(no transparency needed except where noted). ChatGPT/DALL·E is fine for the parallax
backdrops but **weak at clean transparent pixel sprites** — for characters/enemies prefer
a pixel‑art tool (PixelLab.ai, Aseprite + a generator, Retro Diffusion) or explicitly
demand "transparent background, no ground shadow baked in, single centered figure".

## Palette (BinkBonk tokens — quote these hexes so art matches the UI)
- Night sky: `#232849` → `#2a3057`; moon cream `#fff3da`; stars `#fff3da`.
- Meadow grass: `#24413a` deep → `#3c6b52` light; path `#c9a86a`.
- Panels/cream: `#fff3da`; honey wood `#c08040`; gold `#f0a32b` / bright `#ffc84a`.
- Peach accent `#ff9052`; sky `#4db5ff`; mint `#3dc98a`; hearth glow `#ffb36e`.
- Candy rarities: common `#a89a84`, uncommon `#3dc98a`, rare `#4da3ff`, epic `#b46ef5`,
  legendary `#ffab2e`, mythic `#e0455e`.
- Enemy tints: Gloopy Slime/Gloop `#e06868`, Puffling `#ff9aa8`, Chonk `#b46ef5`,
  Grumble/Mushroom King `#e0455e`.

---

## SHARED STYLE PREAMBLE (prepend to every prompt)
> Cozy, cute 2D game art in a warm pixel/hand‑painted hybrid style — think Soul Strike /
> MapleStory / Ragnarok Mobile: rounded chunky shapes, soft rim light, big friendly
> silhouettes, gentle candy‑pastel palette on a cozy starlit‑meadow theme (night navy sky,
> soft moon, mint‑green grass, honey‑wood, peach and gold accents). Storybook‑charming,
> never gothic, never scary. Clean readable shapes at small size.

---

## 1 · Parallax backdrop — `assets/core/bg.reliquary/` (4 × 1536×1024, full‑bleed)
Side‑scroller layers, aligned so a horizontal band ~66% down the frame is the ground line;
each layer tiles horizontally. Consistent lighting across all four (moonlit night meadow).

- **`far.png`** — Far layer: deep night‑navy sky `#232849→#2a3057`, a big soft glowing moon
  upper‑right, scattered twinkling stars, and low **rounded rolling hills** silhouetted on
  the horizon. Hazy, low contrast, distant.
- **`mid.png`** — Mid layer: a row of **giant friendly mushrooms**, curved lantern posts with
  warm firefly glow, and a couple of round leafy trees, all as soft mid‑tone silhouettes.
  Transparent above the horizon so the far layer shows through.
- **`near.png`** — Near layer: foreground **grass tufts, clover, glowing flowers and berry
  bushes** along the bottom, a few fireflies. Mostly transparent; detail only in the
  lower third.
- **`floor.png`** — Ground strip: a **soft dirt path through mint‑green meadow grass**, gentle
  pebbles and flowers, warm moonlit tint; the walkable surface sits ~two‑thirds down the
  image (it's pinned to the battlefield ground line).

## 2 · Player characters — `assets/core/class.<id>/fig.png` (single centered figure, ~360×512, transparent)
Cute chibi adventurers, ~2‑head‑tall, facing right (3/4), idle/walk pose, no baked shadow.

- **`class.warrior/fig.png`** — *the Big‑Hearted*: a round, rosy‑cheeked knight in soft
  honey‑and‑cream armor hugging an oversized fluffy shield, holding a big friendly bonk
  hammer. Cozy, sturdy, huggable.
- **`class.mage/fig.png`** — *the Plucky* Sparkmage: a small bright‑eyed mage in a starry
  peach‑and‑sky robe and a slightly‑too‑big pointy hat, a star‑tipped wand fizzing with
  gold sparkles.
- **`class.hunter/fig.png`** — *the Keen‑Eyed*: a nimble ranger in leafy green with a twig
  bow and an acorn‑tipped arrow, a firefly on the shoulder.
- **`class.rogue/fig.png`** — *the Sneaky*: a tiptoeing little rogue in a berry‑purple hood
  and scarf, a butter‑knife dagger, mischievous grin, tiny cookie poking from a pouch.

*(Optional, lower priority — the 12 roster pals: `assets/core/hero.<id>/idle.png` +
`walk.png`, ~140×132, transparent, matching the roster names Bonk/Pyra/Mimsy/Lulu/
Brambles/Sunny/Chomps/Twig/Glow/Pebble/Zappy/Goober. Mostly unused since 1 account = 1
character.)*

## 3 · Enemies — `assets/core/enemy.<key>/…` (transparent, facing left)
Squishy, cute, "overexcited not evil" — big eyes, breathing‑squash blobs. Replace at the
same paths; the folder keys map to the cozy roster.

- **`enemy.ghoul/fig.png`** (~512×448) — **Gloopy Slime**: a jiggly coral‑red `#e06868`
  slime blob with two big shiny eyes and a little smile, a gloopy highlight.
- **`enemy.skeleton/fig.png`** (~512×236) — **Crumb Mouse**: a tiny round cookie‑crumb
  mouse, beige with a crumb texture, twitchy whiskers, nibbling.
- **`enemy.elite/idle.png` + `walk.png`** (horizontal sprite‑sheet, frame ≈ same height,
  transparent) — **Royal Gloop / Mushroom King** elite: a bigger regal purple `#b46ef5`
  mushroom‑capped blob wearing a tiny gold crown, grumpy‑but‑cute brows. `idle` = gentle
  bob (3–4 frames), `walk` = squish‑hop (4–6 frames), evenly spaced left‑to‑right.

## 4 · Scenery props — `assets/core/props.dungeon/<key>.png` (transparent, ground‑anchored)
Cozy meadow dressing; keep the keys, swap the art.

- **`pillar.png`** (~144×512) — a tall **glowing lantern post** with a warm firefly lantern.
- **`tree.png`** (~268×512) — a round, leafy **storybook tree** with a few berries.
- **`brazier.png`** — a small **campfire / toasty marshmallow pot** with a soft flame.
- **`rock.png`** — a **mossy round rock** with little flowers on top.
- **`tomb.png`** — a **giant spotted toadstool mushroom** (replaces the tombstone).

## 5 · Camp buildings — `assets/core/buildings.camp/<key>.png` (transparent)
Chunky cute storybook buildings on the night‑meadow. Keys = building ids.

- **`altar.png`** (~340×300) — **Wishing Well**: a round stone well with a honey‑wood roof,
  a glowing star hovering above the bucket, sparkles.
- **`board.png`** (~240×220) — **Bulletin Board**: a cork board on posts with colorful
  sticky notes, stickers and a little bunting.
- **`forge.png`** (~280×240) — **Tinker Shop**: a cozy workshop hut with a glowing window,
  gears, glue and glitter, a tiny anvil.
- **`kitchen.png`** (~230×200) — **Snack Shack**: a warm food stall with a striped awning,
  steaming pot, cupcakes and cookies.
- **`arena.png`** (~250×190) — **Stampede Gate** *(new key)*: a shimmering round starlit
  gate/portal of twinkling stars, warm glow spilling out.

## 6 · Bits
- **`assets/core/campfire/fire.png`** (~60×46, transparent) — a small cozy **Snug Hearth**
  campfire, warm friendly flame, a marshmallow on a stick.
- **`assets/core/chest/chest.png`** (~512×237, transparent) — a **Battle Cache** as a cute
  wooden **picnic hamper / gift box** with a honey‑gold latch and a bow, faint sparkle.

---

## Not needed here
- **Star Stampede** (survival) entities are drawn in code (star‑blob hero, blob baddies,
  sparkle bolts) and already read cozy — no PNGs required.
- The **2.5D** path (`Combat3DView`) uses `.glb` models under `assets/models/` — separate
  pipeline (see that folder's README).
- Icons (`assets/icons/*.svg`) are vector; the coin/energy/crest can be nudged in‑repo if
  you want (stardrop is already a star now).
