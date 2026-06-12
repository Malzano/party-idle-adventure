# TODO — game client (party-idle-adventure)

> Working list for the Godot client. Companion file:
> [TODO.md in party-idle-adventure-srv](https://github.com/Malzano/party-idle-adventure-srv/blob/main/TODO.md).
> Context for any item: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · lore/factions:
> [docs/lore.md](docs/lore.md).
> Keep this file honest: check items off (or delete them) in the same commit that does the
> work; completed history lives in git, not here.
>
> *2026-06-12: former §3 (features), §4 (polish/balance), §5 (tech debt) shipped — friends/
> guild/mail UI, private parties with invite codes, Roster tab, pet/relic milestone
> acquisition, welcome-back fix, focus navigation, LICENSE, affix calibration, warning
> sweep, live materials tab. What remains of them is folded below.*

## 1. Go live against the backend (blocked on the srv deploy)

- [ ] Flip `BackendClient.mock = false`, set `base_url` (Cloud Run URL) + `web_api_key`
      (Identity Platform) after the server is deployed.
- [ ] **Wire the initial cloud-save pull at boot in live mode.** `get_save()` exists but
      nothing calls it — today only `PUT` on save + 409 adoption sync the blob. Decide the
      boot reconcile rule (server newer → adopt; local newer → push) and implement it in
      `BackendClient` next to `_boot_config()`.
- [ ] Live smoke test of every wired flow (26 endpoints): anonymous auth, save/sync
      heartbeat, gacha, forge, kitchen, dungeon, talents, quests claim, chest open +
      another player's mythic on the ribbon, leaderboard submit/get, season, party
      create/join(+by code)/leave + presence after two heartbeats, friends add/list,
      guild join, mail list/claim.
- [ ] Surface auth/network failure to the player (today errors only reach the status line
      of whichever window made the call; the heartbeat fails silently). A small "offline —
      retrying" chip near the resource strip would do.

## 2. Art & audio pass (placeholders are ready)

- [ ] Replace `PixelSlot` placeholders with sprites (each slot is labeled with its expected
      size, e.g. `200×320 warrior`) — plan is [pixellab.ai](https://www.pixellab.ai):
      login class figures + campfire, hero/enemy/elite battlefield tokens, props
      (tree/rock/pillar/brazier), Battle Cache chest, paperdoll silhouette + item icons,
      pet/relic art, camp buildings, roster portraits.
- [ ] SFX + music (deferred by CLAUDE.md §9): combat ticks, chest burst, mythic sting,
      gacha reveal, UI clicks, camp ambience.

## 3. Next features (designed, not yet wired)

- [ ] **Factions / OATHS tab** — full design with pros/cons in
      [docs/lore.md §3](docs/lore.md) and a mechanical data stub in
      `GameContent.FACTIONS` (StatBlock-parsable). Needs: Notice Board OATHS tab (swear at
      Act 2, one re-swear/season for 200 soulstones), `PlayerStats` faction block (same
      pattern as the class bonus), the four "special" hooks (offline cap, forge cost,
      chest band, party presence bonus), and a `faction` save key in BOTH repos.
- [ ] **Story into the game** — per-class act storylines are written
      ([docs/lore.md §2](docs/lore.md)); surface them as stage-transition cards or a codex
      panel (beats are one-liners on purpose).
- [ ] **Private-party niceties**: copy-code button (clipboard), maybe a "invite a friend"
      shortcut joining friends list ↔ party code.

## 4. Polish / balance leftovers

- [ ] **Steam packaging** — *blocked on user input*: needs a Steamworks app id + SDK
      decision (GodotSteam vs. Steamworks SDK direct). Then: builds, achievements, cloud
      saves, overlay, and Steam Input controller bindings (focus navigation foundation is
      already in — `Style.focus_ring`, focusable buttons, keyboard class-select).
- [ ] Balance re-check once live: chest item flat affixes were calibrated to design
      anchors (epic ilvl-72 armour ∈ [288, 432]); revisit power weights after real
      player data, and the mythic 2.2× rarity power vs forge curves.

## 5. Tech debt

- [ ] Non-equipment consumable/quest inventory tabs are still design content (materials
      tab is live) — make consumables live when cooked food becomes an inventory item.
- [ ] Emulator-style runtime check for the popup windows in the capture harness (party
      finder + camp + hero are covered; Board MAIL tab and Roster tab have no dedicated
      shot yet).
