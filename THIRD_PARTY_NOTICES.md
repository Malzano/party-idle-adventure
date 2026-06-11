# Third-Party Notices

This project bundles the following third-party software and assets.

## GUT — Godot Unit Test (dev dependency)

- **Path:** `addons/gut/` (vendored from release v9.6.0)
- **Source:** https://github.com/bitwes/Gut
- **License:** MIT — Copyright (c) 2018 Tom "Butch" Wesley
- **License text:** see `addons/gut/LICENSE.md`

GUT is a development-only dependency used to run the unit-test suite in
`test/unit/`. It is **excluded from shipped builds** — export presets must not
include `addons/gut/**` or `test/**` in exported packs.

## Spectral (font)

- **Path:** `assets/fonts/Spectral-*.ttf`
- **Copyright:** © 2017 Production Type (Jean-Baptiste Levée et al.)
- **License:** SIL Open Font License 1.1 — see `assets/fonts/Spectral-OFL.txt`

## Silkscreen (font)

- **Path:** `assets/fonts/Silkscreen-*.ttf`
- **Copyright:** © 2001 Jason Kottke
- **License:** SIL Open Font License 1.1 — see `assets/fonts/Silkscreen-OFL.txt`
