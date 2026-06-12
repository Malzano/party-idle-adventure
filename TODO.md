# TODO — game client (party-idle-adventure)

> Working list for the Godot client. Companion file:
> [TODO.md in party-idle-adventure-srv](https://github.com/Malzano/party-idle-adventure-srv/blob/main/TODO.md).
> Context for any item: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
> Keep this file honest: check items off (or delete them) in the same commit that does the
> work; completed history lives in git, not here.

## 1. Go live against the backend (blocked on the srv deploy)

- [ ] Flip `BackendClient.mock = false`, set `base_url` (Cloud Run URL) + `web_api_key`
      (Identity Platform) after the server is deployed.
- [ ] **Wire the initial cloud-save pull at boot in live mode.** `get_save()` exists but
      nothing calls it — today only `PUT` on save + 409 adoption sync the blob. Decide the
      boot reconcile rule (server newer → adopt; local newer → push) and implement it in
      `BackendClient` next to `_boot_config()`.
- [ ] Live smoke test of every wired flow: anonymous auth, save/sync heartbeat, gacha,
      forge, kitchen, dungeon, talents, quests claim, chest open + announcements ribbon
      from ANOTHER player, leaderboard submit/get, season, party create/join/leave +
      presence after two heartbeats.
- [ ] Surface auth/network failure to the player (today errors only reach the status line
      of whichever window made the call; the heartbeat fails silently). A small "offline —
      retrying" chip near the resource strip would do.

## 2. Art & audio pass (placeholders are ready)

- [ ] Replace `PixelSlot` placeholders with sprites (each slot is labeled with its expected
      size, e.g. `200×320 warrior`) — plan is [pixellab.ai](https://www.pixellab.ai):
      login class figures + campfire, hero/enemy/elite battlefield tokens, props
      (tree/rock/pillar/brazier), Battle Cache chest, paperdoll silhouette + item icons,
      pet/relic art, camp buildings.
- [ ] SFX + music (deferred by CLAUDE.md §9): combat ticks, chest burst, mythic sting,
      gacha reveal, UI clicks, camp ambience.

## 3. Features not yet built (client side)

- [ ] **Friends / Guild UI** — server endpoints (`/v1/friends*`, `/v1/guild*`) are live;
      the Leaderboard's Friends/Guild scopes and a friend-code field in the Party Finder
      are the natural homes.
- [ ] **Mailbox UI** for season rewards (`GET /v1/mail`, `POST /v1/mail/claim`) — a Town
      Crier / Notice Board tab fits the camp.
- [ ] **Private parties end-to-end**: `is_public=false` exists in the schema, but the
      client has no invite-code / direct-join flow (and the server has no code lookup yet —
      coordinate with the srv TODO).
- [ ] **Roster management screen** for gacha heroes (today they only add support DPS;
      no list/inspect/dismiss UI).
- [ ] Per-hero equipment (CLAUDE.md hints at it; today one shared paperdoll). Decide
      whether v1 ships shared-loadout — if yes, record it in ARCHITECTURE §7 instead.
- [ ] Pet/relic acquisition loops (collections are static design content; only the active
      pet toggle is live).

## 4. Polish / balance / known nits

- [ ] Balance pass: chest item power vs forge/gacha curves; mythic 2.0× gear-power
      multiplier is a guess; offline gains vs active play.
- [ ] "Welcome back, delver" popup shows design-sample numbers on a brand-new profile
      (skip it when there are no offline rewards and the profile was created this session).
- [ ] Controller / focus navigation on menus (Steam Deck target, CLAUDE.md §1).
- [ ] Steam packaging: builds, achievements, cloud saves, overlay (CLAUDE.md §9).
- [ ] Add a `LICENSE` file before accepting contributions or borrowing code (README note).

## 5. Tech debt (tolerated, not forgotten)

- [ ] Warning sweep: static-from-instance calls (`GameState.now_utc()` via instance in
      BackendClient ×10), integer division (3 spots), `tr`/`sign` shadowing. All benign;
      fix in one mechanical pass.
- [ ] Non-equipment inventory tabs (consumables/materials/quest) are static design
      content — make them live when crafting consumes materials.
- [ ] `CombatSim` ticks during the Login scene (a fresh profile accrues a few seconds of
      defaults before "Begin the Delve"). Harmless; gate on `has_profile()` if it ever
      matters.
- [ ] Capture harness: add a camp + hero-window shot so visual regressions cover every
      screen.
