# Art drop folder

Copy GPT / Spritesheets.ai exports **into this folder** (`docs/art/incoming/`) and tell Claude.
Use the names below so each file maps cleanly to its in-game bundle. If a sprite sheet came with a
JSON/metadata file, drop that too (same base name) — it tells me the frame count + grid.

## Characters (sprite sheets — walk; optional idle/attack)
- `warrior_walk.png`   (+ `warrior_walk.json`)   → class.warrior
- `mage_walk.png`                                  → class.mage
- `hunter_walk.png`                                → class.hunter
- `rogue_walk.png`                                 → class.rogue
- optional: `<class>_idle.png`, `<class>_attack.png`
- optional: `<class>_pose.png`  (the single static ChatGPT pose, if no sheet yet)

## Enemies (sprite sheet or static)
- `enemy_crypt_rat.png`   → enemy.skeleton
- `enemy_ghoul.png`       → enemy.ghoul
- `enemy_brute.png`       → enemy.elite (elite)

## Bosses
- `boss_marrow_knight.png`   (mini-boss 1-5)
- `boss_bone_warden.png`     (floor boss 1-10)

## Props (static, single object)
- `prop_pillar.png`  `prop_brazier.png`  `prop_rubble.png`  `prop_tree.png`  `prop_rock.png`

## Parallax background (4 layers — see floor1-prompts.md §1)
- `parallax_far.png`  `parallax_mid.png`  `parallax_near.png`  `parallax_ground.png`

## VFX + chest
- `vfx_orb.png`  `vfx_arrow.png`  `vfx_impact.png`  `chest.png`

> If a name doesn't fit what you generated, just drop the file with any clear name and tell me what it is.
