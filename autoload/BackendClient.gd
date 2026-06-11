extends Node
## BackendClient — the game's single seam to the grimhollow-api backend
## (github.com/Malzano/party-idle-adventure-srv). Every method speaks the
## server's EXACT request/response schemas.
##
## MOCK MODE (default until the backend is deployed): no network — responses
## are generated locally by running the same GameState/GameContent logic the
## modals used to call directly, then wrapped in the real server schema. Flip
## [member mock] to false and set [member base_url] + [member web_api_key]
## after deploying to Cloud Run; no call-site changes needed.
##
## Every method returns an envelope: {ok: bool, status: int, data: Dictionary}
## (data is the parsed JSON body — the server result or its error envelope).
## Always call with `await`; mock paths complete without suspending.

## Flip to false after deploying. Mock = fully offline, schema-faithful.
var mock: bool = true
## e.g. "https://grimhollow-api-xxxx-uc.a.run.app"
var base_url: String = ""
## Identity Platform web API key (Firebase console → project settings).
var web_api_key: String = ""

## Combat heartbeat cadence (seconds). The server allows 4/min.
const SYNC_INTERVAL := 45.0
const NETSTATE_PATH := "user://netstate.json"
const AUTH_PATH := "user://auth.json"

var _client_seq: int = 0
var _id_token: String = ""
var _refresh_token: String = ""
var _uid: String = ""
var _sync_accum: float = 0.0
var _talents_debounce: SceneTreeTimer = null
var _rng := RandomNumberGenerator.new()

## Server feature flags (refreshed from /v1/config on boot).
var features: Dictionary = {"cloud_save": true, "server_gacha": true, "leaderboard": true}


func _ready() -> void:
	_rng.randomize()
	_load_netstate()
	# Passive flows: cloud-save on every local save, talent sync on change.
	EventBus.game_saved.connect(func() -> void: put_save())
	EventBus.talents_changed.connect(_on_talents_changed)
	# Boot config: merge live-ops balance overrides (mock: no-op).
	_boot_config()


func _process(delta: float) -> void:
	# Combat heartbeat: the party fights 24/7, so this simply always ticks.
	_sync_accum += delta
	if _sync_accum >= SYNC_INTERVAL:
		_sync_accum = 0.0
		sync_combat()


func _boot_config() -> void:
	var res: Dictionary = await fetch_config()
	if bool(res.get("ok", false)):
		var data: Dictionary = res["data"]
		features = data.get("features", features)
		var overrides: Dictionary = data.get("balance_overrides", {})
		if not overrides.is_empty():
			Balance.apply_overrides(overrides)
			PlayerStats.invalidate()
			EventBus.sim_stats_changed.emit()


# =========================================================================
# Endpoints (request/response schemas mirror the server 1:1)
# =========================================================================

## PUT /v1/save — full save blob upload (fire-and-forget from game_saved).
func put_save() -> Dictionary:
	_client_seq += 1
	_save_netstate()
	var body := {
		"client_seq": _client_seq,
		"checksum": "",  # integrity-advisory; server recomputes (STRICT off)
		"save": {"version": 2, "state": GameState.to_dict()},
	}
	if mock:
		return _wrap(200, {
			"status": "accepted",
			"server_seq": _client_seq,
			"authoritative": {"pity": GameState.pity, "soulstones": GameState.premium_currency},
			"stored_last_played_utc": GameState.last_played_utc,
		})
	var res: Dictionary = await _api("PUT", "/v1/save", body)
	if bool(res["ok"]):
		_apply_authoritative(res["data"].get("authoritative", {}))
	elif int(res["status"]) == 409:
		_adopt_server_save(res["data"])
	return res


## GET /v1/save — fetch the cloud copy (used at boot in live mode).
func get_save() -> Dictionary:
	if mock:
		return _wrap(200, {
			"save": {"version": 2, "state": GameState.to_dict()},
			"server_seq": _client_seq,
			"stored_last_played_utc": GameState.last_played_utc,
		})
	return await _api("GET", "/v1/save", {})


## POST /v1/sync — lightweight combat heartbeat (fast-moving fields only).
func sync_combat() -> Dictionary:
	var patch := {
		"gold": GameState.gold,
		"xp": GameState.xp,
		"xp_to_next": GameState.xp_to_next,
		"player_level": GameState.player_level,
		"act": GameState.act,
		"stage": GameState.stage,
		"max_stage": GameState.max_stage,
		"energy": GameState.energy,
		"daily_day": GameState.daily_day,
		"daily_stages": GameState.daily_stages,
		"daily_damage": GameState.daily_damage,
		"last_played_utc": GameState.now_utc(),
	}
	if mock:
		return _wrap(200, {
			"status": "synced",
			"authoritative": {"pity": GameState.pity, "soulstones": GameState.premium_currency},
			"stored_last_played_utc": int(patch["last_played_utc"]),
			"server_time": GameState.now_utc(),
		})
	var res: Dictionary = await _api("POST", "/v1/sync", {"state_patch": patch})
	if bool(res["ok"]):
		_apply_authoritative(res["data"].get("authoritative", {}))
	return res


## POST /v1/gacha/pull — server-authoritative summons. Applies all side
## effects (spend, pity, roster) in both modes; callers render `results`.
func gacha_pull(count: int) -> Dictionary:
	if mock:
		var cost := Balance.inum("gacha.cost_x1", GameContent.GACHA_COST_X1) if count == 1 \
			else Balance.inum("gacha.cost_x10", GameContent.GACHA_COST_X10)
		if not GameState.spend_soulstones(cost):
			return _error(422, "insufficient_funds",
				"Need %d soulstones, have %d." % [cost, GameState.premium_currency])
		var p := GameState.pity
		var results: Array = []
		for i in count:
			var r := GameContent.gacha_roll_rarity(p, _rng)
			p = 0 if r == "legendary" else p + 1
			var hero: Dictionary = GameContent.gacha_pick(r, _rng)
			results.append(hero)
			GameState.add_roster_hero(hero)
		GameState.set_pity(p)
		return _wrap(200, {"results": results, "pity": p, "soulstones": GameState.premium_currency})
	var body := {"count": count, "idempotency_key": _uuid()}
	var res: Dictionary = await _api("POST", "/v1/gacha/pull", body)
	if bool(res["ok"]):
		var data: Dictionary = res["data"]
		for hero in data.get("results", []):
			GameState.add_roster_hero(hero)
		GameState.set_pity(int(data.get("pity", GameState.pity)))
		GameState.premium_currency = int(data.get("soulstones", GameState.premium_currency))
		EventBus.currencies_changed.emit()
	return res


## POST /v1/forge/upgrade.
func forge_upgrade() -> Dictionary:
	if mock:
		var r := GameState.try_forge_upgrade(_rng)
		if not bool(r["ok"]):
			return _error(422, "insufficient_funds", String(r["reason"]))
		return _wrap(200, {
			"ok": true,
			"success": bool(r["success"]),
			"forge_level": GameState.forge_level,
			"gold": GameState.gold,
			"iron_ingots": GameState.iron_ingots,
			"ember_dust": GameState.ember_dust,
			"cost": {
				"gold": Balance.forge_gold_cost(GameState.forge_level - (1 if bool(r["success"]) else 0)),
				"iron": Balance.inum("forge.iron_cost", 12),
				"dust": Balance.inum("forge.dust_cost", 3),
			},
		})
	var res: Dictionary = await _api("POST", "/v1/forge/upgrade", {})
	if bool(res["ok"]):
		var d: Dictionary = res["data"]
		GameState.forge_level = int(d.get("forge_level", GameState.forge_level))
		GameState.gold = int(d.get("gold", GameState.gold))
		GameState.iron_ingots = int(d.get("iron_ingots", GameState.iron_ingots))
		GameState.ember_dust = int(d.get("ember_dust", GameState.ember_dust))
		GameState.daily_forges += 1
		EventBus.currencies_changed.emit()
		EventBus.quests_changed.emit()
		if bool(d.get("success", false)):
			EventBus.loadout_changed.emit()
	return res


## POST /v1/kitchen/cook.
func kitchen_cook(recipe_name: String, effect: String, duration: int) -> Dictionary:
	if mock:
		GameState.set_food_buff(recipe_name, effect, duration)
		return _wrap(200, {
			"ok": true,
			"food_buff": GameState.food_buff,
			"food_buff_effect": GameState.food_buff_effect,
			"food_buff_until": GameState.food_buff_until,
		})
	var res: Dictionary = await _api("POST", "/v1/kitchen/cook", {"recipe": recipe_name})
	if bool(res["ok"]):
		var d: Dictionary = res["data"]
		var until := int(d.get("food_buff_until", 0))
		GameState.set_food_buff(
			String(d.get("food_buff", recipe_name)),
			String(d.get("food_buff_effect", effect)),
			maxi(0, until - GameState.now_utc()))
	return res


## POST /v1/dungeon/enter.
func dungeon_enter() -> Dictionary:
	if mock:
		if not GameState.enter_daily_dungeon():
			var code := "no_attempts" if GameState.dungeon_attempts <= 0 else "insufficient_funds"
			return _error(422, code, "Cannot enter the dungeon.")
		return _wrap(200, {
			"ok": true,
			"energy": GameState.energy,
			"dungeon_attempts": GameState.dungeon_attempts,
			"dungeon_buff_until": GameState.dungeon_buff_until,
		})
	var res: Dictionary = await _api("POST", "/v1/dungeon/enter", {})
	if bool(res["ok"]):
		var d: Dictionary = res["data"]
		GameState.energy = int(d.get("energy", GameState.energy))
		GameState.dungeon_attempts = int(d.get("dungeon_attempts", GameState.dungeon_attempts))
		GameState.dungeon_buff_until = int(d.get("dungeon_buff_until", GameState.dungeon_buff_until))
		EventBus.currencies_changed.emit()
		EventBus.quests_changed.emit()
	return res


## POST /v1/talents/set (debounced via EventBus.talents_changed).
func talents_set() -> Dictionary:
	if mock:
		return _wrap(200, {"ok": true, "talents_allocated": GameState.talents_allocated})
	return await _api("POST", "/v1/talents/set", {"talents_allocated": GameState.talents_allocated})


## POST /v1/quests/claim — claims + grants. Callers refresh via quests_changed.
func quest_claim(quest_id: int) -> Dictionary:
	if mock:
		if GameState.quests_claimed.has(quest_id):
			return _error(409, "already_claimed", "Quest already claimed today.")
		var q: Dictionary = GameContent.QUESTS[quest_id]
		if GameState.quest_progress(quest_id) < float(q["g"]):
			return _error(422, "not_complete", "Quest objective not complete.")
		GameState.claim_quest(quest_id)
		var granted := _grant_reward_text(String(q["rw"]))
		return _wrap(200, {
			"granted": granted,
			"balances": {"soulstones": GameState.premium_currency},
		})
	var res: Dictionary = await _api("POST", "/v1/quests/claim", {"quest_id": quest_id})
	if bool(res["ok"]):
		var d: Dictionary = res["data"]
		var granted: Dictionary = d.get("granted", {})
		GameState.claim_quest(quest_id)
		if int(granted.get("gold", 0)) > 0:
			GameState.add_gold(int(granted["gold"]))
		if int(granted.get("xp", 0)) > 0:
			GameState.add_xp(int(granted["xp"]))
		var bal: Dictionary = d.get("balances", {})
		GameState.premium_currency = int(bal.get("soulstones", GameState.premium_currency))
		EventBus.currencies_changed.emit()
	return res


## GET /v1/leaderboard?cat&scope — entries are GameContent.PLAYERS-shaped.
func leaderboard(cat: String, scope: String) -> Dictionary:
	if mock:
		var pool: Array = GameContent.PLAYERS.duplicate()
		if scope == "friends":
			pool = pool.filter(func(p: Dictionary) -> bool: return bool(p["friend"]) or bool(p["you"]))
		elif scope == "guild":
			pool = pool.filter(func(p: Dictionary) -> bool: return String(p["guild"]) == "ASH")
		pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return GameContent.lb_sort_key(a, cat) > GameContent.lb_sort_key(b, cat))
		var your_rank := 0
		for i in pool.size():
			if bool(pool[i]["you"]):
				your_rank = i + 1
				break
		return _wrap(200, {
			"entries": pool,
			"your_rank": your_rank,
			"season": {"num": 3, "name": String(GameContent.SEASON["name"]), "ends_at": 0},
		})
	return await _api("GET", "/v1/leaderboard?cat=%s&scope=%s&limit=50" % [cat, scope], {})


## POST /v1/leaderboard/submit — debounced score reporting.
func leaderboard_submit() -> Dictionary:
	var profile := PlayerStats.compute()
	var body := {
		"power": float(profile["total_power"]) / 1000.0,  # display-magnitude millions
		"stage": [GameState.act, GameState.stage],
		"boss": 0.0,
	}
	if mock:
		return _wrap(200, {"accepted": true, "your_rank": {"power": GameState.global_rank}})
	return await _api("POST", "/v1/leaderboard/submit", body)


## GET /v1/season.
func season() -> Dictionary:
	if mock:
		var tiers: Array = []
		for t in GameContent.TIERS:
			tiers.append({"name": t["name"], "rar": t["rar"], "range": t["range"], "reward": t["reward"]})
		return _wrap(200, {
			"season": {"num": 3, "name": String(GameContent.SEASON["name"]), "starts_at": 0, "ends_at": 0},
			"tiers": tiers,
			"you": GameContent.SEASON["you"],
		})
	return await _api("GET", "/v1/season", {})


## GET /v1/config — no auth; safe pre-login.
func fetch_config() -> Dictionary:
	if mock:
		return _wrap(200, {
			"min_client_version": "0.3.0",
			"config_version": 0,
			"balance_overrides": {},
			"features": features,
			"season": {"num": 3, "name": String(GameContent.SEASON["name"]), "ends_at": 0},
		})
	return await _api("GET", "/v1/config", {}, false)


# =========================================================================
# Internals
# =========================================================================

func _on_talents_changed() -> void:
	# Debounce rapid allocation clicks into one talents/set call.
	if _talents_debounce != null:
		return
	_talents_debounce = get_tree().create_timer(2.0)
	await _talents_debounce.timeout
	_talents_debounce = null
	talents_set()


func _apply_authoritative(auth: Dictionary) -> void:
	if auth.is_empty():
		return
	var soul := int(auth.get("soulstones", GameState.premium_currency))
	var pity := int(auth.get("pity", GameState.pity))
	if soul != GameState.premium_currency:
		GameState.premium_currency = soul
		EventBus.currencies_changed.emit()
	if pity != GameState.pity:
		GameState.set_pity(pity)


## 409 conflict: the server copy wins — adopt it wholesale (spec §4.1).
func _adopt_server_save(data: Dictionary) -> void:
	var save: Dictionary = data.get("save", {})
	var state: Dictionary = save.get("state", {})
	if state.is_empty():
		return
	GameState.from_dict(state)
	_apply_authoritative(data.get("authoritative", {}))
	EventBus.game_loaded.emit()
	EventBus.currencies_changed.emit()


## Mirrors the server's quest reward grants in mock mode.
func _grant_reward_text(rw: String) -> Dictionary:
	var granted := {"gold": 0, "xp": 0, "soulstones": 0, "items": []}
	var re := RegEx.new()
	re.compile(r"^(\d+)\s+(.+)$")
	for part in rw.split("·"):
		var m := re.search(part.strip_edges())
		if m == null:
			continue
		var n := int(m.get_string(1))
		var what := m.get_string(2).to_lower()
		if what.begins_with("gold"):
			granted["gold"] = n
			GameState.add_gold(n)
		elif what.begins_with("xp"):
			granted["xp"] = n
			GameState.add_xp(n)
		elif what.begins_with("soulstone"):
			granted["soulstones"] = n
			GameState.premium_currency += n
			EventBus.currencies_changed.emit()
	return granted


## One live HTTP round trip with auth + a single retry after token refresh.
func _api(method: String, path: String, body: Dictionary, authed: bool = true) -> Dictionary:
	if base_url.is_empty():
		return _error(0, "offline", "BackendClient.base_url is not configured.")
	if authed and _id_token.is_empty():
		var ok := await _ensure_auth()
		if not ok:
			return _error(401, "unauthenticated", "Could not authenticate.")
	var res: Dictionary = await _http(method, base_url + path, body, _id_token if authed else "")
	if authed and int(res["status"]) == 401:
		if await _refresh_auth():
			res = await _http(method, base_url + path, body, _id_token)
	return res


func _http(method: String, url: String, body: Dictionary, bearer: String) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 15.0
	add_child(req)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not bearer.is_empty():
		headers.append("Authorization: Bearer " + bearer)
	var m := HTTPClient.METHOD_GET
	match method:
		"POST":
			m = HTTPClient.METHOD_POST
		"PUT":
			m = HTTPClient.METHOD_PUT
	var payload := "" if method == "GET" else JSON.stringify(body)
	var err := req.request(url, headers, m, payload)
	if err != OK:
		req.queue_free()
		return _error(0, "network", "Request failed to start (%d)." % err)
	var result: Array = await req.request_completed
	req.queue_free()
	var status := int(result[1])
	var text := (result[3] as PackedByteArray).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	var data: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return {"ok": status >= 200 and status < 300, "status": status, "data": data}


## Firebase anonymous auth (Identity Platform REST) — live mode only.
func _ensure_auth() -> bool:
	_load_auth()
	if not _refresh_token.is_empty():
		return await _refresh_auth()
	var res: Dictionary = await _http("POST",
		"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=" + web_api_key,
		{"returnSecureToken": true}, "")
	if not bool(res["ok"]):
		return false
	var d: Dictionary = res["data"]
	_id_token = String(d.get("idToken", ""))
	_refresh_token = String(d.get("refreshToken", ""))
	_uid = String(d.get("localId", ""))
	_save_auth()
	return not _id_token.is_empty()


func _refresh_auth() -> bool:
	if _refresh_token.is_empty():
		return false
	var res: Dictionary = await _http("POST",
		"https://securetoken.googleapis.com/v1/token?key=" + web_api_key,
		{"grant_type": "refresh_token", "refresh_token": _refresh_token}, "")
	if not bool(res["ok"]):
		return false
	var d: Dictionary = res["data"]
	_id_token = String(d.get("id_token", ""))
	_refresh_token = String(d.get("refresh_token", _refresh_token))
	_uid = String(d.get("user_id", _uid))
	_save_auth()
	return not _id_token.is_empty()


func _load_auth() -> void:
	if not FileAccess.file_exists(AUTH_PATH):
		return
	var f := FileAccess.open(AUTH_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_refresh_token = String(parsed.get("refresh_token", ""))
		_uid = String(parsed.get("uid", ""))


func _save_auth() -> void:
	var f := FileAccess.open(AUTH_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"refresh_token": _refresh_token, "uid": _uid}))
	f.close()


func _load_netstate() -> void:
	if not FileAccess.file_exists(NETSTATE_PATH):
		return
	var f := FileAccess.open(NETSTATE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_client_seq = int(parsed.get("client_seq", 0))


func _save_netstate() -> void:
	var f := FileAccess.open(NETSTATE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"client_seq": _client_seq}))
	f.close()


func _uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	return bytes.hex_encode()


static func _wrap(status: int, data: Dictionary) -> Dictionary:
	return {"ok": true, "status": status, "data": data}


static func _error(status: int, code: String, message: String) -> Dictionary:
	return {"ok": false, "status": status, "data": {"error": {"code": code, "message": message}}}
