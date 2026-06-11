# Grimhollow Backend — v1 Specification

Spec for a **separate backend repository** serving the Grimhollow client (Godot 4.6, PC/Steam,
offline-first idle ARPG). Target platform: **Google Cloud Platform**. This document is
self-contained: everything needed to implement the server is here, including the exact client
save schema, gacha math, and balance numbers it must mirror.

Source-of-truth references in the game repo (for cross-checking only, not required reading):

| Concern | Game file |
|---|---|
| Save blob writer/reader | `autoload/SaveManager.gd`, `autoload/GameState.gd` |
| Balance numbers | `data/balance.json` (typed access via `systems/data/Balance.gd`) |
| Gacha algorithm + leaderboard shapes | `systems/data/GameContent.gd` |
| Leaderboard UI consumer | `scenes/leaderboard/Leaderboard.gd` |
| Combat / offline reward math | `systems/combat/CombatSim.gd` |

---

## 1. Overview & goals

Grimhollow is **offline-first**. The client owns moment-to-moment gameplay: a deterministic
tick simulation (`CombatSim`, 10 ticks/s) computes combat, gold/XP, and offline progress from a
local JSON save at `user://savegame.json`. The save stores a `last_played_utc` timestamp; on
launch the client fast-forwards the sim by elapsed time (capped at 12 h). **None of that moves
to the server.** The game must remain fully playable with zero connectivity.

What moves server-side, and why:

| Feature | Why server-side |
|---|---|
| **Cloud save sync** | Device loss/reinstall recovery; later Steam-account portability. |
| **Gacha rolls + pity + soulstones** | The only real-money-adjacent economy. Client-side rolls are trivially editable in a JSON save; pity and premium balance must be authoritative. |
| **Leaderboards (4 categories × 3 scopes)** | Currently simulated from a static `GameContent.PLAYERS` array. Real rankings need a shared store + validation. |
| **Seasons & divisions** | Rollover, reward grants, and division cutoffs are inherently shared state. |
| **Daily quest claims** | Rewards include soulstones; claims must be replay-proof and reset at a server-enforced 00:00 UTC. |
| **Minimal social (friends, guilds)** | Only enough to power the Friends/Guild leaderboard scopes. |
| **Live-ops config** | Push `balance.json` overrides without shipping a client patch. |

**Out of scope for the v1 server:** real-time multiplayer, networked party finder (stays
simulated in the client), chat, trading, Steam achievements/cloud, push notifications, web
dashboard. The mailbox is write-only from server jobs and read via save sync (no dedicated
mailbox UI endpoints in v1 beyond what §4 lists).

Design principles:

1. **Client remains the simulation authority for combat**; the server never re-runs combat. It
   validates *rates and bounds* instead (§6).
2. **Server is the authority for: soulstones, pity, gacha results, quest claims, leaderboard
   entries, seasons.** When online, the client treats its local copies of those as display
   caches.
3. **Latest-timestamp-wins** whole-blob save sync. No field-level merging in v1 (§4.1).
4. Everything is **stateless HTTP behind Cloud Run** so the service scales to zero between
   sessions of a small player base.

---

## 2. Architecture (GCP)

```
            ┌────────────────────────────────┐
            │  Godot 4.6 client (PC/Steam)   │
            │  local save: user://savegame.json
            └───────┬───────────▲────────────┘
                    │ HTTPS, Authorization: Bearer <Firebase ID token>
                    │
   ┌────────────────▼──────────────────┐        ┌─────────────────────┐
   │  Cloud Run: grimhollow-api        │◄───────│  Cloud Scheduler    │
   │  containerized REST /v1/*         │  OIDC  │  00:00 UTC daily    │
   │  (Go or Node/TypeScript)          │        │  + season rollover  │
   └──┬───────────┬───────────┬────────┘        └─────────────────────┘
      │           │           │
┌─────▼─────┐ ┌───▼────────┐ ┌▼───────────────────┐
│ Firestore │ │ Identity   │ │ Memorystore (Redis)│
│ (native)  │ │ Platform / │ │ leaderboard cache  │
│ primary DB│ │ Fb Auth    │ │ (OPTIONAL, v1.1)   │
└───────────┘ │ anonymous  │ └────────────────────┘
              └────────────┘
  Supporting: Secret Manager (API keys, HMAC pepper)
              Artifact Registry + GitHub Actions (build & deploy)
              Cloud Armor / Cloud Run ingress rules (rate limiting, OPTIONAL)
              Cloud Logging + Error Reporting (built-in)
```

Component choices:

- **Cloud Run** — single containerized REST service. Any language; Go or Node/TS recommended
  (first-class Firestore + Firebase Admin SDKs). Min instances = 0, max = 10, concurrency 80.
  Request timeout 30 s. One service, one container, no microservices in v1.
- **Firestore (native mode)** — primary store. Document model fits the save-blob + per-season
  snapshot pattern; free tier covers early scale. See §5.
- **Identity Platform / Firebase Auth** — **anonymous sign-in** for device auth. The Godot
  client calls the Firebase Auth REST API directly (no SDK needed). UID = `player_id`
  everywhere. Anonymous accounts are upgradeable later by *linking* Google or (via a custom
  token minting endpoint) Steam — see §3.
- **Cloud Scheduler** — two cron jobs hitting OIDC-protected internal endpoints (§7).
- **Secret Manager** — Firebase service-account key (if not using ambient Cloud Run identity),
  checksum pepper, any third-party keys.
- **Artifact Registry + GitHub Actions** — `docker build` → push → `gcloud run deploy` on
  merge to `main` (dev project) and on tag (prod project).
- **Memorystore (Redis)** — *optional, defer.* Top-50 leaderboard reads can be served from a
  60 s in-process cache per Cloud Run instance at v1 scale. Redis is **not** scale-to-zero
  (~$35+/mo idle) — add it only when read volume hurts.
- **Cloud Armor** — optional; per-IP throttling at the edge. v1 can rely on per-UID
  application-level rate limits (§6.5).

**Cost note:** with scale-to-zero Cloud Run, Firestore free tier (50K reads / 20K writes per
day), and no Memorystore, an early playtest population (< 1K DAU) runs at **≈ $0–10/month**.
The first real cost lever is Firestore leaderboard reads — mitigate with the in-process cache
and `limit=50` pages before reaching for Redis.

---

## 3. Authentication

Flow (v1, anonymous device identity):

1. First online launch: client calls Identity Platform REST
   `POST https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=<WEB_API_KEY>` with
   `{"returnSecureToken": true}` → `{idToken, refreshToken, localId}`.
2. Client stores `refreshToken` in `user://auth.json` (this file is the device identity —
   document in-game that deleting it orphans the cloud profile until account linking exists).
3. Every API call sends `Authorization: Bearer <idToken>`. ID tokens expire after 1 h; refresh
   via `POST https://securetoken.googleapis.com/v1/token?key=<WEB_API_KEY>` with
   `{"grant_type":"refresh_token","refresh_token":...}`.
4. Server verifies the ID token with the Firebase Admin SDK on every request.
   **`player_id` = Firebase UID (`localId`).** No other identifier is ever trusted.

Server behavior:

- 401 `unauthenticated` for missing/expired/invalid tokens. Client refreshes and retries once.
- First authenticated call from a new UID lazily creates `players/{uid}` (§5) with defaults.

Future (documented now so v1 doesn't paint into a corner):

- **Google account linking:** client calls Firebase `accounts:signInWithIdp` with the same
  `idToken` to link — UID is preserved, no server change needed.
- **Steam:** server endpoint validates a Steam session ticket (Steamworks Web API
  `ISteamUserAuth/AuthenticateUserTicket`) and mints a **Firebase custom token** bound to the
  existing UID (link) or a new one (fresh install). Requires the Admin SDK only; design the
  players doc with an optional `identities: {steam_id, google_sub}` map from day one.

---

## 4. REST API v1 contract

Conventions:

- Base URL: `https://api.<env>.grimhollow.example/v1` (Cloud Run custom domain or run.app URL).
- All bodies are JSON, `Content-Type: application/json`.
- All endpoints (except `/healthz` and `/internal/*`) require `Authorization: Bearer <ID token>`.
- Timestamps are **unix seconds, UTC** (matches the client's `now_utc()`); the client formats.
- Error envelope, all non-2xx:

```json
{ "error": { "code": "insufficient_funds", "message": "Need 160 soulstones, have 12." } }
```

- Common error codes: `401 unauthenticated`, `403 forbidden`, `404 not_found`,
  `409 conflict`, `422 invalid_payload`, `429 rate_limited`, `500 internal`.

### 4.1 `PUT /v1/save` — cloud save sync

Uploads the full local save blob — byte-for-byte the same structure the client writes to
`user://savegame.json` — wrapped with a client sequence number and checksum.

Request:

```json
{
  "client_seq": 1042,
  "checksum": "9f3c…64-hex-chars…ab",
  "save": {
    "version": 2,
    "state": {
      "player_name": "Vael",
      "player_title": "the Forsaken",
      "player_class": "Pyromancer",
      "prestige": "III",
      "global_rank": 11,
      "player_level": 47,
      "xp": 12480,
      "xp_to_next": 14000,
      "gold": 248910,
      "premium_currency": 1204,
      "ember_dust": 38,
      "energy": 86,
      "energy_max": 120,
      "act": 4,
      "stage": 7,
      "max_stage": 407,
      "pity": 47,
      "talents_allocated": [0, 1, 2, 3, 4, 5],
      "active_pet": 0,
      "roster_extra": [ { "n": "Korr", "r": "rare", "role": "3★ DPS · Reaver" } ],
      "quests_claimed": [0, 1],
      "iron_ingots": 46,
      "forge_level": 7,
      "food_buff": "Emberroot Stew",
      "food_buff_effect": "+12% party ATK · 30 min",
      "food_buff_until": 1781234567,
      "dungeon_buff_until": 0,
      "dungeon_attempts": 3,
      "daily_day": 20618,
      "daily_stages": 3,
      "daily_damage": 3100000.0,
      "daily_meals": 1,
      "daily_summons": 1,
      "daily_forges": 2,
      "last_played_utc": 1781234890
    }
  }
}
```

- `client_seq` — monotonically increasing per device, persisted client-side. Used for replay
  rejection (§6.4), not for conflict resolution.
- `checksum` — lowercase hex SHA-256 of the canonical JSON of `save.state` (keys sorted,
  no whitespace, UTF-8). Integrity check only — *not* an anti-cheat measure (the client is
  open); it catches truncated/corrupt uploads.

Server processing order:

1. Schema-validate `save.state` against the exact key/type table in §6.2 → `422` on failure.
2. Sanity-cap validation (§6.3) against the previously stored blob → `422` with code
   `cap_violation` on failure (do **not** store).
3. **Conflict rule (v1, deliberately simple): latest-timestamp-wins, whole blob.**
   - If incoming `state.last_played_utc` **>** stored `state.last_played_utc` → accept,
     overwrite the stored blob.
   - Else → `409 conflict`; the response carries the server copy and the client must adopt it
     wholesale (overwrite `user://savegame.json`, reload `GameState`).
   - No field-level merging (no "max of currencies", etc.) in v1. Rationale: one PC device is
     the dominant case; merging currency by max is an exploit vector (play offline on two
     devices, merge, repeat). Revisit only when multi-device is real.
4. **Server-owned field override:** regardless of accept/conflict, the stored blob's `pity`
   and `premium_currency` are forced to the server ledger values (`players/{uid}.pity`,
   `players/{uid}.soulstones`) before persisting/returning. The client's values for those two
   keys are advisory only once a cloud profile exists.

Response `200` (accepted):

```json
{
  "status": "accepted",
  "server_seq": 1042,
  "authoritative": { "pity": 47, "soulstones": 1204 },
  "stored_last_played_utc": 1781234890
}
```

Response `409` (conflict — server copy wins):

```json
{
  "status": "conflict",
  "winner": "server",
  "save": { "version": 2, "state": { "player_name": "Vael", "...": "full server blob" } },
  "authoritative": { "pity": 47, "soulstones": 1204 }
}
```

Errors: `422 invalid_payload` (schema), `422 cap_violation` (detail string names the failed
check), `422 checksum_mismatch`, `429 rate_limited`.

Notes: blob is ~2–4 KB today — store inline in Firestore (1 MiB doc limit). If a future schema
exceeds ~200 KB, switch to a GCS object + pointer (§5 anticipates this).

### 4.2 `GET /v1/save`

Returns the stored save (with authoritative `pity`/`premium_currency` already substituted in).

Response `200`:

```json
{
  "save": { "version": 2, "state": { "...": "full blob" } },
  "server_seq": 1042,
  "stored_last_played_utc": 1781234890
}
```

`404 not_found` if the player has never uploaded. Client flow on launch: GET, compare
`stored_last_played_utc` with local `last_played_utc`, keep the newer, then PUT if local won.

### 4.3 `POST /v1/gacha/pull` — server-authoritative summons

The server holds pity and soulstones; results are rolled server-side. The client's
`GameContent.gacha_roll_rarity()` becomes display-only (rate panel) when online.

Request:

```json
{ "count": 10, "idempotency_key": "c1b2…uuid…" }
```

- `count` ∈ {1, 10} only → `422` otherwise.
- `idempotency_key` — client-generated UUID. If the server has a stored result for
  `(uid, idempotency_key)` (retain ≥ 24 h), return it verbatim without re-rolling or
  re-charging. Mandatory: a retried request after a network drop must not double-charge.

Costs (mirror `data/balance.json` → `gacha`): **x1 = 160 soulstones, x10 = 1600**.
Insufficient balance → `402`-style `422` with code `insufficient_funds` (no partial pulls).

**Exact roll algorithm** — must match the client's `GameContent.gacha_roll_rarity` so the
published rates panel stays truthful. Constants from `balance.json`:
`base_legendary = 0.006`, `soft_pity = 74`, `soft_pity_step = 0.06`, `hard_pity = 90`,
`epic = 0.051`, `rare = 0.18`.

For each pull in the batch, **sequentially**, with `pity` = pulls since last legendary
(running value within the batch):

```
five_chance = base_legendary                       # 0.006
if pity >= soft_pity:                              # pity >= 74
    five_chance = base_legendary + (pity - (soft_pity - 1)) * soft_pity_step
                                                   # = 0.006 + (pity - 73) * 0.06
if pity >= hard_pity:                              # pity >= 90
    five_chance = 1.0                              # guaranteed

x = rng.uniform()                                  # one draw in [0, 1)
if x < five_chance:                       rarity = "legendary"
elif x < five_chance + epic:              rarity = "epic"        # +0.051
elif x < five_chance + epic + rare:       rarity = "rare"        # +0.18
else:                                     rarity = "uncommon" if rng.uniform() < 0.5
                                                  else "common"  # second draw

if rarity == "legendary": pity = 0
else:                     pity += 1
```

After the rarity, pick a hero uniformly among pool entries of that rarity (fallback to the
`common` entries if a rarity has none). v1 pool (mirror of `GameContent.HEROES_POOL`; serve it
from server config so banners can rotate):

```json
[
  { "n": "Ashling",   "r": "legendary", "role": "5★ DPS · Pyromancer" },
  { "n": "Mordrake",  "r": "epic",      "role": "4★ Tank · Bulwark" },
  { "n": "Seraphine", "r": "epic",      "role": "4★ Healer · Lightbinder" },
  { "n": "Korr",      "r": "rare",      "role": "3★ DPS · Reaver" },
  { "n": "Wisp",      "r": "rare",      "role": "3★ Support · Lantern" },
  { "n": "Grub",      "r": "common",    "role": "Shard · Iron" }
]
```

Use a CSPRNG. Charge, roll, persist (new pity, new balance, appended `roster_extra` heroes in
the stored save blob), and write the idempotency record **in one Firestore transaction**.

Response `200`:

```json
{
  "results": [
    { "n": "Korr", "r": "rare", "role": "3★ DPS · Reaver" },
    { "n": "Grub", "r": "common", "role": "Shard · Iron" }
  ],
  "pity": 49,
  "soulstones": 1044
}
```

Errors: `422 invalid_payload`, `422 insufficient_funds`, `429 rate_limited`.

### 4.4 `POST /v1/leaderboard/submit`

Client reports its current scores; the server validates against caps and snapshots into the
current season's board. Call after meaningful changes (stage advance, power recompute), rate
limited (§6.5).

Request:

```json
{ "power": 188.4, "stage": [7, 40], "boss": 96.8, "weekly": 224 }
```

- `power`, `boss` — **millions**, floats (matches `GameContent.PLAYERS`).
- `stage` — `[act, sub]`, ints, `act >= 1`, `1 <= sub <= 50`.
- `weekly` — accepted for shape compatibility but **ignored**: the server computes weekly climb
  (rank delta since the weekly anchor, §5/§7) and `trend` itself. Log mismatches.

Server validation: monotonic stage (never lower than the stored snapshot), power/boss within
plausibility caps derived from the player's synced save (§6.3.5), profile fields (`name`,
`lv`, `guild`, `tier`) sourced from `players/{uid}` + season division — never from this request.

Response `200`:

```json
{ "accepted": true, "your_rank": { "power": 11, "stage": 9, "boss": 1, "weekly": 1 } }
```

Errors: `422 cap_violation`, `429 rate_limited`.

### 4.5 `GET /v1/leaderboard?cat=power&scope=global&limit=50`

- `cat` ∈ `power | stage | boss | weekly` (default `power`).
- `scope` ∈ `global | friends | guild` (default `global`).
- `limit` 1–100 (default 50).

Entries mirror the client's `GameContent.PLAYERS` element shape **exactly** so
`Leaderboard.gd` can render them without translation:

```json
{
  "entries": [
    { "name": "Mournheart", "guild": "VIG", "lv": 88, "tier": "Hollow Sovereign",
      "power": 412.6, "stage": [9, 12], "boss": 88.4, "weekly": 142,
      "trend": 0, "you": false, "friend": false },
    { "name": "Vael", "guild": "ASH", "lv": 47, "tier": "Emberlord",
      "power": 188.4, "stage": [7, 40], "boss": 96.8, "weekly": 224,
      "trend": 3, "you": true, "friend": true }
  ],
  "your_rank": 11,
  "season": { "num": 3, "name": "Emberfall", "ends_at": 1782300000 }
}
```

- Entries come **pre-sorted** by the requested category, descending. Sort keys match the
  client's `lb_sort_key`: `power` → power; `stage` → `act*100 + sub`; `boss` → boss;
  `weekly` → weekly.
- `trend` — signed rank delta vs. the previous daily snapshot (▲/▼/– in the UI).
- `you` is true on the caller's own row (whether or not it is inside `limit`); `your_rank` is
  the caller's absolute rank in this cat+scope (0 when unranked).
- If the caller's row falls outside `limit`, append it as a final extra entry (the UI pins a
  YOU bar; an explicit row keeps the client logic trivial).
- `friend` is true when the entry's uid is in the caller's friend list.
- `scope=guild` with no guild → empty `entries`, `your_rank: 0`.

### 4.6 `GET /v1/season`

Season meta + divisions ladder + the caller's division standing. `tiers` mirrors
`GameContent.TIERS` (minus the client-local `you` flag, which the client derives from
`you.tier`); `you` mirrors `GameContent.SEASON.you`.

Response `200`:

```json
{
  "season": { "num": 3, "name": "Emberfall", "starts_at": 1779700000, "ends_at": 1782300000 },
  "tiers": [
    { "name": "Hollow Sovereign", "rar": "legendary", "range": "Top 10",    "reward": "Mythic Cache · Title" },
    { "name": "Emberlord",        "rar": "epic",      "range": "Top 50",    "reward": "Epic Cache · 1,200 Gold" },
    { "name": "Goldmark",         "rar": "rare",      "range": "Top 500",   "reward": "Rare Cache · 600 Gold" },
    { "name": "Ironclad",         "rar": "uncommon",  "range": "Top 5,000", "reward": "Uncommon Cache" },
    { "name": "Ashbound",         "rar": "common",    "range": "All Delvers", "reward": "Participation Cache" }
  ],
  "you": { "tier": "Emberlord", "next": "Hollow Sovereign", "pct": "Top 0.2%", "to_next": 1, "prog": 88 }
}
```

Division assignment uses the **power** category rank against the tier cutoffs.

### 4.7 `POST /v1/quests/claim`

Server-validated daily quest claims. Progress is *reported* via save sync (`daily_*` counters
in the blob); the server checks the last synced counters, so the client should `PUT /v1/save`
before claiming (the client integration in §8 does this).

Quest definitions (mirror of `GameContent.QUESTS`, served from `quest_defs`, §5). `quest_id`
is the array index 0–4:

| id | title | counter | goal | reward |
|---|---|---|---|---|
| 0 | Clear 3 dungeon stages | `daily_stages` | 3 | 240 gold · 40 XP |
| 1 | Summon a hero | `daily_summons` | 1 | 1 soulstone |
| 2 | Cook a party meal | `daily_meals` | 1 | Hearth Token |
| 3 | Deal 5,000,000 damage | `daily_damage` (raw, goal × 1e6) | 5,000,000 | 120 gold · Relic Shard |
| 4 | Salvage 5 items at the Forge | `daily_forges` | 5 | Iron ×3 |

Request:

```json
{ "quest_id": 0 }
```

Server checks, in order: quest_id ∈ 0–4 → `422`; not already claimed today (server-side claim
ledger keyed by UTC day — **not** the blob's `quests_claimed`) → `409 already_claimed`; the
stored save's `daily_day` equals the current UTC day **and** the matching counter ≥ goal →
`422 not_complete`. On success, grant rewards into the server ledger / stored blob
(soulstones to the ledger; gold/XP/materials patched into the stored blob and echoed back).

Response `200`:

```json
{
  "granted": { "gold": 240, "xp": 40, "soulstones": 0, "items": [] },
  "balances": { "soulstones": 1204 }
}
```

Errors: `409 already_claimed`, `422 not_complete`, `422 invalid_payload`, `429 rate_limited`.

### 4.8 Social (minimal — exists to power leaderboard scopes)

`GET /v1/friends` → `200`:

```json
{
  "friend_code": "GRIM-7H3K-Q2",
  "friends": [
    { "uid": "abc123", "name": "Drossel", "lv": 79, "guild": "VIG", "power": 344.2 }
  ]
}
```

`POST /v1/friends/add` with `{ "code": "GRIM-9XAB-T4" }` → `200 { "added": { "uid": "...",
"name": "Sablewing" } }`. v1 is **mutual-on-add** (no request/accept flow). Errors:
`404 not_found` (bad code), `409 already_friends`, `422` (self-add), cap 50 friends → `422
friend_limit`.

`GET /v1/guild` → `200`:

```json
{
  "guild": { "id": "ash", "tag": "ASH", "name": "Ashen Covenant",
             "members": [ { "uid": "...", "name": "Ironwake", "lv": 81, "power": 362.9 } ] }
}
```

`404 not_found` when guildless. `POST /v1/guild/join` with `{ "tag": "ASH" }` → `200` with the
same guild object. v1: open join, one guild per player, member cap 50, leave = join another
(no dedicated leave endpoint). Seed the five design guilds (ASH, VIG, HEX, GLD, TMB); no
guild-creation endpoint in v1.

### 4.9 `GET /v1/config` — live-ops balance overrides

Server-pushed overrides mirroring `data/balance.json` sections, so tuning needs no client
patch. The client deep-merges `balance_overrides` **over** its local file (server wins per
key) inside `Balance.gd` (§8.4). Only include keys that differ from the shipped defaults.

Response `200` (no auth required, but accept the header if present):

```json
{
  "min_client_version": "0.3.0",
  "config_version": 17,
  "balance_overrides": {
    "gacha":   { "cost_x10": 1450 },
    "rewards": { "offline_cap_hours": 14 },
    "energy":  { "dungeon_attempts_per_day": 5 }
  },
  "features": { "cloud_save": true, "server_gacha": true, "leaderboard": true },
  "season": { "num": 3, "name": "Emberfall", "ends_at": 1782300000 }
}
```

Valid override sections (must match `balance.json` top level): `enemy`, `rewards`, `energy`,
`gacha`, `forge`, `heroes`, `roster`, `dps_model`, `derived_bases`, `power`. The **server's
gacha/quest/cap math must read the same override values** it publishes — one config source.

### 4.10 `GET /healthz`

No auth. `200` with body `ok` when the service can reach Firestore (one cheap read). Used by
Cloud Run health checks and uptime monitoring.

### 4.11 Internal (Cloud Scheduler only — see §7)

`POST /internal/reset-daily`, `POST /internal/season-rollover`. Not reachable by players:
require a Google-signed **OIDC** token for a dedicated scheduler service account (verify
audience = the Cloud Run URL, email = the SA). Return `200` with a summary JSON.

---

## 5. Firestore data model

Native mode, single database. Collections:

### `players/{uid}`

```json
{
  "created_at": 1779000000,
  "updated_at": 1781234890,
  "name": "Vael",
  "level": 47,
  "guild_id": "ash",
  "friend_code": "GRIM-7H3K-Q2",
  "identities": { "steam_id": null, "google_sub": null },

  "soulstones": 1204,
  "pity": 47,

  "save": {
    "server_seq": 1042,
    "checksum": "9f3c…ab",
    "blob": { "version": 2, "state": { "...": "full §4.1 state" } },
    "gcs_uri": null
  },

  "rate": { "save_last": 1781234890, "gacha_minute": [1781234801, 1781234855] },
  "flags": { "suspect_score": 0, "banned": false }
}
```

- `name`/`level`/`guild_id` are denormalized from the blob on every accepted save (leaderboard
  submit reads profile data from here, never from the request).
- `save.gcs_uri` — null in v1; set (and `blob` cleared) if a future schema outgrows inline
  storage; points at `gs://grimhollow-saves/{uid}.json`.
- `friend_code` — generated once (e.g. `GRIM-` + 6 chars base32, collision-checked); also
  indexed for lookup (single-field index on `friend_code`).

Subcollections:

- `players/{uid}/friends/{friend_uid}` → `{ "since": 1780000000 }` (written to **both** sides
  on add; 50-doc cap enforced in the transaction).
- `players/{uid}/claims/{yyyymmdd}` → `{ "claimed": [0, 1], "updated_at": ... }` — the
  authoritative daily-claim ledger (auto-resets by keying on the day; old docs TTL-deleted).
- `players/{uid}/mail/{auto_id}` → season rewards mailbox:

```json
{ "type": "season_reward", "season": 3, "tier": "Emberlord",
  "granted": { "gold": 1200, "items": ["epic_cache"] }, "read": false, "created_at": 1782300001 }
```

- `players/{uid}/idempotency/{key}` → stored gacha response + `created_at` (TTL 24 h via
  Firestore TTL policy).

### `leaderboard_s{num}/{uid}` — one collection per season (e.g. `leaderboard_s3`)

```json
{
  "name": "Vael",
  "guild": "ASH",
  "guild_id": "ash",
  "lv": 47,
  "tier": "Emberlord",
  "power": 188.4,
  "stage": [7, 40],
  "stage_key": 740,
  "boss": 96.8,
  "weekly": 224,
  "trend": 3,
  "rank_anchor": { "power": 14, "at": 1781100000 },
  "updated_at": 1781234890
}
```

- `stage_key = act * 100 + sub` — the sortable scalar (matches the client sort key).
- `weekly`/`trend` are recomputed by the daily job (§7) from `rank_anchor`; clients never set
  them.
- Per-season collections make rollover trivial (freeze = stop writing; next season = new
  collection) and keep indexes small.

**Composite indexes** (per season collection; scope filter + category sort):

| Query | Index |
|---|---|
| global × each cat | single-field descending on `power`, `stage_key`, `boss`, `weekly` |
| guild × each cat | `guild_id ASC, power DESC` (and same for `stage_key`, `boss`, `weekly`) |

Friends scope: fetch the caller's friend uids (≤ 50), then `documentId IN` batched reads
(chunks of 30) and sort in memory — no index needed at the 50-friend cap.

### `guilds/{id}`

```json
{ "tag": "ASH", "name": "Ashen Covenant", "color": "#e8843a",
  "member_count": 14, "created_at": 1779000000 }
```

Membership = `players.guild_id` + denormalized `guild_id` on leaderboard docs (queryable
without a members subcollection; `member_count` maintained transactionally on join).

### `seasons/{num}` (doc id = season number as string)

```json
{
  "num": 3, "name": "Emberfall", "status": "active",
  "starts_at": 1779700000, "ends_at": 1782300000,
  "tiers": [ { "name": "Hollow Sovereign", "rar": "legendary", "range": "Top 10",
               "cutoff_rank": 10, "reward": { "label": "Mythic Cache · Title",
               "gold": 0, "items": ["mythic_cache", "title_sovereign"] } } ]
}
```

`tiers` carries both the display strings the client shows (§4.6) and machine-readable
`cutoff_rank` + structured `reward` for the rollover job.

### `quest_defs/{id}` (doc id = "0".."4")

```json
{ "title": "Clear 3 dungeon stages", "counter": "daily_stages", "goal": 3,
  "reward": { "label": "240 Gold · 40 XP", "gold": 240, "xp": 40, "soulstones": 0, "items": [] } }
```

### `config/live` (single doc)

The §4.9 payload, edited by hand or a future admin tool; the API serves it from a 60 s
in-process cache.

---

## 6. Anti-cheat & validation

Philosophy: the client is fully open (JSON save on disk), so **never trust client numbers for
anything shared or monetized**. Combat is not re-simulated; instead the server enforces
*schema, bounds, rates, and monotonicity*, and keeps the genuinely abusable systems (gacha,
quest rewards, leaderboards) fully server-side.

### 6.1 Layers

1. Authoritative systems: soulstones, pity, gacha results, quest claims, season rewards.
2. Save schema validation (6.2) — reject malformed blobs outright.
3. Sanity caps (6.3) — reject impossible deltas between consecutive accepted saves.
4. Replay/idempotency (6.4).
5. Per-UID rate limits (6.5).
6. A `suspect_score` counter on `players/{uid}` incremented on every cap violation; flag for
   review / leaderboard exclusion past a threshold rather than hard-banning on first offense
   (clock skew and bugs happen).

### 6.2 Save schema — exact keys & types

`save.version` must equal **2** (int). `save.state` must contain **exactly** these 35 keys
(reject unknown keys; reject missing keys — the client always writes all of them):

| Key | Type | Constraints |
|---|---|---|
| `player_name` | string | 1–24 chars, printable; profanity-filter for leaderboard display |
| `player_title` | string | ≤ 48 chars |
| `player_class` | string | ≤ 24 chars |
| `prestige` | string | ≤ 8 chars |
| `global_rank` | int | ≥ 0 (display-only relic; ignored by server logic) |
| `player_level` | int | 1 – 2000 |
| `xp` | int | 0 ≤ xp < `xp_to_next` |
| `xp_to_next` | int | ≥ 1; ≈ `14000 * 1.15^(player_level - 47)` within 2× tolerance |
| `gold` | int | 0 – 1e15 |
| `premium_currency` | int | ≥ 0 (overwritten by server ledger, §4.1) |
| `ember_dust` | int | 0 – 1e9 |
| `energy` | int | 0 ≤ energy ≤ `energy_max` |
| `energy_max` | int | 1 – 1000 (design default 120) |
| `act` | int | 1 – 100 |
| `stage` | int | 1 – 50 (`enemy.stages_per_act`) |
| `max_stage` | int | encoded `act*100 + stage`; sub-part 1–50; ≥ current `act*100+stage` |
| `pity` | int | 0 – 90 (overwritten by server ledger) |
| `talents_allocated` | int[] | ≤ 400 entries, each 0 ≤ id < 400, unique, contains 0 |
| `active_pet` | int | 0 – 63 |
| `roster_extra` | array | each elem `{n: string ≤ 24, r: enum rarity, role: string ≤ 48}`; ≤ 5000 elems |
| `quests_claimed` | int[] | each 0–4, unique |
| `iron_ingots` | int | 0 – 1e9 |
| `forge_level` | int | 7 – 200 (base is 7; see 6.3.4) |
| `food_buff` | string | ≤ 32 chars |
| `food_buff_effect` | string | ≤ 64 chars |
| `food_buff_until` | int | 0 or within `now ± 7 days` |
| `dungeon_buff_until` | int | 0 or within `now ± 1 day` |
| `dungeon_attempts` | int | 0 – `energy.dungeon_attempts_per_day` (default 3) |
| `daily_day` | int | `floor(now_utc / 86400) ± 1` |
| `daily_stages` | int | 0 – 100000 |
| `daily_damage` | float | ≥ 0, finite |
| `daily_meals` | int | 0 – 1000 |
| `daily_summons` | int | 0 – 1000 |
| `daily_forges` | int | 0 – 10000 |
| `last_played_utc` | int | ≤ `now_utc + 300` (5 min skew allowance); > 1.6e9 |

`rarity` enum everywhere: `common | uncommon | rare | epic | legendary`.

### 6.3 Rate caps (between consecutive accepted saves)

Let `Δt = max(60, incoming.last_played_utc − stored.last_played_utc)` seconds, and
`s = (act − 1) * 50 + stage` (the global **stage index** — note this differs from the
`max_stage` encoding) computed from the **incoming** blob's max stage.

All constants come from the same balance config the server publishes (§4.9 defaults shown):

1. **Gold/hour cap.** Per-wave gold at stage index `s` is
   `wave_gold(s) = 12.0 * 1.024^(s−1)` (`rewards.gold_base/gold_growth`). Cap:

   ```
   Δgold ≤ (Δt / 3600) * MAX_WAVES_PER_HOUR * wave_gold(s) * (1 + GOLD_FIND_CAP) * DUNGEON_MULT
   ```

   Server tunables: `MAX_WAVES_PER_HOUR = 7200` (2 waves/s — generous: at 4× speed and 10
   ticks/s a wave cannot clear faster than one tick), `GOLD_FIND_CAP = 2.0` (gear/talents
   realistically reach ~+40% gold find; 200% is a loose ceiling), `DUNGEON_MULT = 3.0`
   (`energy.dungeon_gold_mult`). Allow a +20% grace factor before flagging.
2. **XP/hour cap.** Same shape with `wave_xp(s) = 4.0 * 1.022^(s−1)` and `XP_GAIN_CAP = 2.0`.
   Derive a **level cap** from it: simulate the `xp_to_next` curve
   (`next = floor(next * 1.15)`, base 14000 at level 47) and reject level jumps the capped XP
   could not buy.
3. **Stage rate cap.** `Δstage_index ≤ (Δt / 3600) * MAX_WAVES_PER_HOUR / 5`
   (`enemy.waves_per_stage = 5`).
4. **Forge plausibility.** Each upgrade from level `L` costs
   `floor(4200 * 1.6^(L−7))` gold + 12 iron + 3 dust, at 82% success
   (`forge` section). Going from stored level `L0` to incoming `L1` costs at least
   `Σ_{k=L0..L1−1} 4200 * 1.6^(k−7)` gold (success-only lower bound). Reject when
   `gold_spent_lower_bound > stored.gold + Δgold_cap` for the interval.
5. **Leaderboard submit caps** (§4.4): `stage_key` must equal the synced save's
   `max_stage` (±1 stage grace for in-flight progress); `power ≤ POWER_CAP(level, s)` — a
   server curve fitted generously above the design values (e.g. Vael: lv 47, stage 7-40,
   power 188.4M; Mournheart: lv 88, stage 9-12, power 412.6M). Start with
   `POWER_CAP = 1.0M * player_level + 0.5M * s` and tune from telemetry; `boss ≤ power`.
6. **Monotonic checks:** `max_stage`, `player_level`, `forge_level`, and the size of
   `roster_extra` never decrease across accepted saves. `roster_extra` growth must not exceed
   the count of server-rolled gacha results since the last save (when `server_gacha` is on).

Violations → `422 cap_violation`, blob not stored, `suspect_score += 1`.

### 6.4 Replay protection

- `PUT /v1/save`: reject `client_seq ≤ stored server_seq` with `409 stale_seq` (response
  includes the server copy, same shape as a timestamp conflict). Prevents replaying an old
  capture to resurrect spent currency.
- `POST /v1/gacha/pull` and `POST /v1/quests/claim`: idempotency keys / day-keyed claim
  ledger (§4.3, §4.7) make replays harmless.
- Optional hardening (v1.1): `X-Request-Id` UUID header on all writes, kept in a short-TTL
  dedupe set.

### 6.5 Per-UID rate limits (application-level, Firestore- or memory-backed)

| Endpoint | Limit |
|---|---|
| `PUT /v1/save` | 1 / 30 s, burst 3 |
| `POST /v1/gacha/pull` | 6 / min |
| `POST /v1/leaderboard/submit` | 2 / min |
| `POST /v1/quests/claim` | 10 / min |
| `GET` reads (any) | 60 / min |

Over limit → `429` with `Retry-After` (seconds). Add Cloud Armor per-IP rules in front if
unauthenticated abuse (token-mint spam) appears.

---

## 7. Daily & season jobs (Cloud Scheduler)

Both jobs target the same Cloud Run service, OIDC-authenticated (§4.11). Make both
**idempotent** (safe to retry) and record a `jobs/{name}_{date}` marker doc to skip
duplicate triggers.

### `POST /internal/reset-daily` — cron `0 0 * * *` (00:00 UTC)

1. Snapshot ranks: for the active season collection, recompute each doc's `trend`
   (yesterday's rank − today's rank, per the power category) and refresh `weekly` = anchor
   rank − current rank, re-anchoring `rank_anchor` every Monday 00:00 UTC.
2. Nothing else needs server work: daily quests reset implicitly — claims are keyed by
   `players/{uid}/claims/{yyyymmdd}` and the client zeroes its own `daily_*` counters via
   `GameState.check_daily_reset()` (unix-day comparison), and `dungeon_attempts` refills
   client-side the same way. The server only validates `daily_day` freshness on claims (§4.7).
3. Optionally prune expired idempotency/claims docs if not using Firestore TTL.

### `POST /internal/season-rollover` — cron `5 0 * * *`, no-ops unless `now ≥ ends_at`

1. Mark `seasons/{n}.status = "ended"`. The `leaderboard_s{n}` collection is now frozen
   (API rejects submits for ended seasons).
2. Compute final ranks (power category) and division assignment per the season's
   `tiers[].cutoff_rank`.
3. For every ranked player, write a `players/{uid}/mail/{auto}` reward doc (§5) with the
   division's structured reward. Grants land in the ledger/blob when the client next syncs
   (v1: server applies gold/items into the stored blob lazily at next `GET /v1/save`, or the
   client gets a "Season ended" toast from `/v1/config.season` change — pick at impl time;
   the mailbox doc is the durable record either way).
4. Create `seasons/{n+1}` (`status: "active"`, 28-day default duration, next name from a
   configured list) and start serving `leaderboard_s{n+1}`. Entries repopulate as players
   submit — no copy-forward.

---

## 8. Client integration points (Godot)

Exact touchpoints in the game repo. Recommended future autoload:
**`systems/net/BackendClient.gd`** (do **not** create until the backend exists) — owns the
Firebase token lifecycle, an `HTTPRequest` pool, JSON envelope handling, retry with
exponential backoff + jitter (1 s → 2 s → 4 s → give up and queue), and an offline write queue
persisted to `user://netqueue.json` (replayed in order on reconnect; gacha/claim entries carry
their idempotency keys so replays are safe).

1. **Save sync — `autoload/SaveManager.gd`.**
   - `save_game()` currently writes `{version, state}` to `user://savegame.json`. After a
     successful local write, also call `BackendClient.put_save(payload)` (fire-and-forget;
     local write must never block on the network). On `409`, overwrite the local file with the
     returned server blob, `GameState.from_dict(save.state)`, and re-run the offline
     computation.
   - `load_game()`: after the local load, `GET /v1/save`; if `stored_last_played_utc` is
     newer than local, adopt the server blob (then the existing
     `_compute_offline_progress()` runs against the adopted timestamp). If local is newer,
     `PUT` it.
   - Apply `authoritative.pity / soulstones` from every save response to
     `GameState.set_pity()` / `GameState.premium_currency` (+
     `EventBus.currencies_changed.emit()`).
2. **Gacha — `scenes/camp/GachaModal.gd`.** The pull path currently spends via
   `GameState.spend_soulstones()`, rolls with `GameContent.gacha_roll_rarity()` /
   `gacha_pick()`, and updates `GameState.set_pity()` + `add_roster_hero()`. When
   `features.server_gacha` is true: flush a save sync, then `POST /v1/gacha/pull` and drive
   the existing flip-reveal UI from `results[]`, then apply returned `pity`/`soulstones`.
   The local roll functions remain for the drop-rates panel and for offline/feature-flag-off
   play. Gacha is **online-only** once a cloud profile exists (queueing pulls offline would
   desync pity).
3. **Leaderboard — `scenes/leaderboard/Leaderboard.gd`.** `_ranked()` reads
   `GameContent.PLAYERS` and sorts/filters locally. Replace the data source with the cached
   response of `GET /v1/leaderboard?cat={_cat}&scope={_scope}` — the entry dictionaries are
   shape-identical, so podium/table/YOU-bar code is untouched; server pre-sorts, so drop the
   local `sort_custom`. Refetch on cat/scope change (60 s client cache per cat+scope).
   Season header fields come from `GET /v1/season` (`ends_at` → the client formats the
   "12d 04h 38m" countdown string currently hardcoded in `GameContent.SEASON.ends`).
   Submit scores via `POST /v1/leaderboard/submit` on `EventBus.sim_stage_changed` and
   `EventBus.sim_stats_changed` (debounced ≥ 60 s).
4. **Config merge — `systems/data/Balance.gd`.** Add an
   `apply_overrides(overrides: Dictionary)` static method that deep-merges over the cached
   `_data` after `_ensure()` (same spirit as the existing `reset_cache()` test seam). On
   boot, `GET /v1/config`; merge; then `PlayerStats.invalidate()` +
   `EventBus.sim_stats_changed` so live values reprice. Persist the last-seen overrides to
   `user://config_cache.json` and apply them on offline boots. If
   `min_client_version` exceeds the running version, show a non-blocking "update available"
   notice (never hard-lock a paid offline game).
5. **Quests — Notice Board (camp).** Claim buttons call `PUT /v1/save` then
   `POST /v1/quests/claim {quest_id}` instead of `GameState.claim_quest()` alone; on success
   apply `granted` locally and still call `claim_quest()` for UI state.
6. All HTTP from Godot uses `HTTPRequest` nodes (or a thin wrapper) — JSON via
   `JSON.stringify` / `JSON.parse_string`, checksum via `HashingContext` SHA-256.

---

## 9. Versioning & rollout

- **API versioning:** `/v1` path prefix. Within v1, changes are **additive only** — new
  optional fields and new endpoints; never remove/rename/retype. Breaking changes → `/v2`
  served side-by-side until the old client population drains.
- **Save schema versioning:** the blob's `version` (currently 2) belongs to the client.
  Server accepts `version >= 2` and validates the keys it knows; a future client bump adds
  keys behind a server deploy that whitelists them first (server-first deploy order).
- **Client gating:** `min_client_version` in `/v1/config` (semver string). Server may also
  read an optional `X-Client-Version` header and reject ancient clients on write endpoints
  with `426`-style `403 client_too_old`.
- **Environments:** two GCP projects — `grimhollow-dev`, `grimhollow-prod` — each with its
  own Firestore, Identity Platform, scheduler, and Cloud Run service. GitHub Actions:
  merge to `main` → deploy dev; version tag (`v*`) → deploy prod (manual approval gate).
  The Godot client picks the base URL + Firebase web API key from an environment block
  (`dev` builds point at dev).
- **Migrations:** Firestore is schemaless; run one-off migration scripts as Cloud Run jobs
  in the same repo (`/cmd/migrate-*` or `scripts/`), never inline in request handlers.
- **Observability:** structured JSON logs (uid, endpoint, latency, error code), Error
  Reporting on panics/5xx, an uptime check on `/healthz`, and a log-based alert on
  `cap_violation` spikes.

---

## 10. Open questions for the user

1. **Steam identity timeline.** v1 ships anonymous device auth; Steam linking (§3) needs a
   Steamworks app id + the custom-token endpoint. Is Steam auth wanted before or after the
   first public playtest? (Affects whether `identities.steam_id` gets real plumbing now.)
2. **GDPR / data deletion.** Player saves contain a chosen display name (PII-ish). Do we need
   a self-serve "delete my cloud data" path in v1 (an authenticated
   `DELETE /v1/account` wiping `players/{uid}` + leaderboard docs), or is support-email
   deletion acceptable at playtest scale?
3. **Regions.** Single-region (`europe-west` vs `us-central` vs `asia-southeast` — where is
   the launch audience?) for Cloud Run + Firestore. Firestore location is **permanent per
   project**, so this must be decided before creating the prod project.
4. **Expected DAU for sizing.** The §2 cost note assumes < 1K DAU. If marketing plans imply
   10K+ at launch, revisit: Memorystore for leaderboards, Firestore read budgets, and Cloud
   Run min-instances ≥ 1 to kill cold starts.
5. **Conflict-rule UX.** Latest-timestamp-wins can silently discard a few minutes of play on a
   second device. Acceptable for v1 (PC-only), or should the client prompt "Local vs Cloud —
   keep which?" when both have meaningful deltas?
6. **Leaderboard display names.** Server-side profanity filtering / uniqueness for
   `player_name`? v1 spec assumes filter-on-write, non-unique names (uid disambiguates).
7. **Season cadence & rewards.** §7 assumes 28-day seasons and the §4.6 tier rewards as gold +
   item-id caches. Confirm cadence and what an "Epic Cache" concretely contains before the
   rollover job grants anything.
