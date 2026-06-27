# 3D models for the 2.5D combat scenes (Survival + Fight)

Drop a **`.glb`** here named by its **entity key** and it auto‑appears in‑game
(`Combat3DView.auto_load_models()` scans this folder). No code edit needed —
just drop the file and **re‑import** (open the Godot editor once, or run
`Godot --headless --path . --import`).

## Keys (file name → what it skins)
| File | Used for |
|------|----------|
| `class_warrior.glb` / `class_mage.glb` / `class_hunter.glb` / `class_rogue.glb` | the player delver (by chosen class) |
| `enemy_swarmer.glb` / `enemy_grunt.glb` / `enemy_brute.glb` | the swarm archetypes |
| `boss.glb` | the world boss (Survival) / floor boss (Fight) |
| `shot.glb` | projectiles (hunter/mage) |
| `gem.glb` | xp/score motes |
| `chest.glb` | battle caches (Fight) |

Any key without a file falls back to a tinted placeholder primitive, so the
game is fully playable before the art lands — add models incrementally.

## Model conventions (so they drop in clean)
- **Forward = ‑Z**, **origin at the feet** (so it stands on the ground plane).
- Scale to roughly **1.7 m tall** for a character (the world is ~`0.02` units per
  sim‑pixel; placeholders are ~1.5 m). Tune per‑model in Blender, not in code.
- Keep them **low‑poly** — they're small on a top‑down map and there can be 100+.
- glTF Binary (`.glb`) with embedded textures. Baked `idle`/`walk`/`attack`
  animations are supported by Godot; animation playback hook‑up is a later step.

## Suggested pipeline
1. AI image→3D (Meshy / Tripo / Rodin) from the existing 2D character art, **or**
   a free low‑poly pack (Quaternius / Kenney) for enemies/props.
2. (Humanoids) auto‑rig + animations free via **Mixamo**.
3. Blender for scale/orientation/pivot fixes → export `.glb` here.
