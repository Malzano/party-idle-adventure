# The Delve

> Working title. A **party-based idle dungeon crawler** for **PC / Steam**, built in **Godot 4.x** with **typed GDScript**.

Dark gothic ARPG mood (Diablo / Path of Exile). A party of **4 heroes auto-fights 24/7** and keeps
progressing while the game is closed; power comes from gear, pets, relics, a talent tree, and
gacha-summoned heroes. The UI is themed **"Grimhollow"** — carved stone, beveled iron, ember glow.

The full design brief lives in [CLAUDE.md](CLAUDE.md).

---

## Status — early skeleton

This repo currently contains the **project skeleton + UI shell**. It runs, but combat and the deep
screen interiors are not built yet.

**Done**
- **App shell:** persistent left nav rail (Camp / Fight / Hero, `1`/`2`/`3` hotkeys, ember active state)
  + floating top-right resource strip; a screen host swaps between the three screens; autosave on exit.
- **Autoloads:** `GameState` (profile / currencies / last-played UTC), `SaveManager` (JSON save/load in
  `user://` + offline-elapsed calc), `EventBus` (signal hub).
- **Grimhollow design system:** color tokens (`Palette`), beveled-iron styleboxes (`Style`), Spectral +
  Silkscreen fonts, tintable SVG icons. Screens are styled placeholders listing their planned features.

**Next milestones** (see [CLAUDE.md §8](CLAUDE.md))
- Deterministic, headless **CombatSim** (the core architectural rule — sim ≠ animation).
- **Offline progress** → "Welcome back" rewards.
- Hero screen (stats, equipment paperdoll, pets, relics, talent web), Camp buildings + **gacha**,
  Fight isometric roaming battlefield, then polish (Team Aura, dailies, balance).

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
