extends Node
## BackendClient — the game's single seam to the party-idle-api backend
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

# Live against party-idle-dev (Cloud Run, asia-southeast1) as of 2026-06-13.
# Set mock=true to run fully offline (schema-faithful, no network) — every flow
# still works locally. The save is local-first; network sync is additive, so a
# down/slow backend never blocks boot or play.
var mock: bool = false
## Cloud Run service URL (no trailing slash). party-idle-dev / asia-southeast1.
var base_url: String = "https://party-idle-api-909650956354.asia-southeast1.run.app"
## Identity Platform browser API key (party-idle-dev). Anonymous sign-in enabled.
var web_api_key: String = "AIzaSyB4CGGcEsncE7WSgwmx56lBHH3QPJNiJIg"

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
		poll_announcements()
		AssetManager.sync_catalog()  # hot content: new skins/items reflect w/o restart
		if GameState.in_party():
			party_mine()  # presence refresh for the Party Finder


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


## POST /v1/chest/open — battlefield treasure chest. The server (or its mock
## mirror) rolls the loot; rewards are applied to GameState here, and mythic
## drops raise EventBus.mythic_announced. Response schema:
## {ok, reward:{kind, gold, iron, dust, item, banked}, daily_chests, announcement}.
func chest_open() -> Dictionary:
	if mock:
		if GameState.daily_chests >= 40:
			return _error(422, "chest_cap", "Daily chest limit reached.")
		var s_index := Balance.stage_index(GameState.act, GameState.stage)
		var wave_gold := Balance.wave_gold(s_index)
		var reward := {"kind": "gold", "gold": 0, "iron": 0, "dust": 0, "item": null, "banked": false}
		var roll := _rng.randf()
		if roll < 0.5:
			reward["gold"] = roundi(wave_gold * (6.0 + _rng.randf() * 6.0))
			GameState.add_gold(int(reward["gold"]))
		elif roll < 0.7:
			reward["kind"] = "materials"
			reward["iron"] = 2 + _rng.randi_range(0, 4)
			reward["dust"] = (1 + _rng.randi_range(0, 1)) if _rng.randf() < 0.5 else 0
			GameState.iron_ingots += int(reward["iron"])
			GameState.ember_dust += int(reward["dust"])
			EventBus.currencies_changed.emit()
		else:
			reward["kind"] = "item"
			var rarity := GameContent.roll_chest_item_rarity(_rng)
			var ilvl := maxi(1, roundi(float(s_index) * 0.45 + 5.0))
			var item := GameContent.generate_item(ilvl, rarity, _rng)
			reward["item"] = item
			if GameState.add_bag_item(item):
				reward["banked"] = true
			else:
				reward["gold"] = roundi(wave_gold * 4.0)
				GameState.add_gold(int(reward["gold"]))
		GameState.daily_chests += 1
		var announcement: Variant = null
		if reward["item"] != null and String((reward["item"] as Dictionary)["r"]) == "mythic":
			announcement = {"player": GameState.player_name, "item": (reward["item"] as Dictionary)["n"], "rarity": "mythic"}
			EventBus.mythic_announced.emit(GameState.player_name, String((reward["item"] as Dictionary)["n"]))
		return _wrap(200, {"ok": true, "reward": reward, "daily_chests": GameState.daily_chests, "announcement": announcement})
	var res: Dictionary = await _api("POST", "/v1/chest/open", {})
	if bool(res["ok"]):
		var d: Dictionary = res["data"]
		var rw: Dictionary = d.get("reward", {})
		if int(rw.get("gold", 0)) > 0:
			GameState.add_gold(int(rw["gold"]))
		if int(rw.get("iron", 0)) > 0 or int(rw.get("dust", 0)) > 0:
			GameState.iron_ingots += int(rw.get("iron", 0))
			GameState.ember_dust += int(rw.get("dust", 0))
			EventBus.currencies_changed.emit()
		if rw.get("item") != null and bool(rw.get("banked", false)):
			GameState.add_bag_item(rw["item"])
		GameState.daily_chests = int(d.get("daily_chests", GameState.daily_chests))
		var ann: Variant = d.get("announcement")
		if ann != null:
			EventBus.mythic_announced.emit(String((ann as Dictionary).get("player", "")), String((ann as Dictionary).get("item", "")))
	return res


## GET /v1/announcements?since= — global mythic broadcasts, polled with the
## heartbeat. New entries raise EventBus.mythic_announced for the ribbon.
var _last_announcement_at: int = 0

func poll_announcements() -> void:
	if mock:
		return  # mock: only your own drops announce (no fake other players)
	var res: Dictionary = await _api("GET", "/v1/announcements?since=%d" % _last_announcement_at, {})
	if not bool(res["ok"]):
		return
	var list: Array = res["data"].get("announcements", [])
	for a in list:
		var ann: Dictionary = a
		_last_announcement_at = maxi(_last_announcement_at, int(ann.get("at", 0)))
		if String(ann.get("player", "")) != GameState.player_name:
			EventBus.mythic_announced.emit(String(ann.get("player", "A delver")), String(ann.get("item", "an artifact")))


# =========================================================================
# Party (/v1/party/*) — 4-player groups, presence via the sync heartbeat.
# GameState.party mirrors the server's PartyView; mock mode simulates the
# other players (GameContent.MOCK_DELVERS) and persists YOUR party in
# user://netstate.json (client state — never in the authoritative save).
# =========================================================================

const PARTY_CAP := 4
const PRESENCE_TTL := 120  # seconds; mirrors the server's lib/party.ts

var _mock_parties: Array = []        # open parties run by fake delvers
var _mock_parties_seeded := false
var _mock_my_party: Dictionary = {}  # raw doc of the party you're in


## GET /v1/party/list — newest open public parties.
func party_list() -> Dictionary:
	var now := GameState.now_utc()
	if mock:
		_ensure_mock_parties()
		var views: Array = []
		for doc: Dictionary in _mock_parties:
			if (doc["members"] as Array).size() < PARTY_CAP:
				_drift_mock_members(doc["members"], now)
				views.append(_party_view(doc, now))
		views.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["avg_stage_key"]) > int(b["avg_stage_key"]))
		return _wrap(200, {"parties": views, "server_time": now})
	return await _api("GET", "/v1/party/list", {})


## GET /v1/party/mine — refreshes the GameState.party mirror.
func party_mine() -> Dictionary:
	var now := GameState.now_utc()
	if mock:
		if _mock_my_party.is_empty():
			return _wrap(200, {"party": null, "server_time": now})
		_drift_mock_members(_mock_my_party["members"], now)
		_refresh_self_member(now)
		var v := _party_view(_mock_my_party, now, true)
		GameState.set_party(v)
		_save_netstate()
		return _wrap(200, {"party": v, "server_time": now})
	var res: Dictionary = await _api("GET", "/v1/party/mine", {})
	if bool(res["ok"]):
		var pv: Variant = res["data"].get("party")
		GameState.set_party(pv if pv != null else {})
	return res


## POST /v1/party/create {name, is_public}. One party per player.
func party_create(party_name: String, is_public: bool = true) -> Dictionary:
	if mock:
		if not _mock_my_party.is_empty():
			return _error(409, "already_partied", "Leave your current party first.")
		var clean := party_name.strip_edges()
		while clean.contains("  "):
			clean = clean.replace("  ", " ")
		if clean.length() < 3 or clean.length() > 24:
			return _error(422, "bad_party_name", "Party name must be 3-24 characters.")
		var now := GameState.now_utc()
		var me := _self_member(now)
		_mock_my_party = {
			"id": "mock-self-%08x" % (_rng.randi() & 0x7fffffff),
			"name": clean,
			"leader_uid": me["uid"],
			"is_public": is_public,
			"join_code": _new_party_code(),
			"status": "open",
			"members": [me],
		}
		var v := _party_view(_mock_my_party, now, true)
		GameState.set_party(v)
		_save_netstate()
		return _wrap(200, {"party": v})
	var res: Dictionary = await _api("POST", "/v1/party/create", {"name": party_name, "is_public": is_public})
	if bool(res["ok"]):
		GameState.set_party(res["data"]["party"])
	return res


## POST /v1/party/join {party_id} | {code} — private parties only by code.
func party_join(party_id: String, code: String = "") -> Dictionary:
	if mock:
		if not _mock_my_party.is_empty():
			return _error(409, "already_partied", "Leave your current party first.")
		_ensure_mock_parties()
		var doc: Dictionary = {}
		if party_id == "" and code != "":
			var norm := code.strip_edges().to_upper()
			if not _is_party_code(norm):
				return _error(422, "bad_party_code", "Malformed party code.")
			for p: Dictionary in _mock_parties:
				if String(p.get("join_code", "")) == norm:
					doc = p
					break
			if doc.is_empty():
				return _error(404, "not_found", "No party with that code.")
		else:
			for p: Dictionary in _mock_parties:
				if String(p["id"]) == party_id:
					doc = p
					break
		if doc.is_empty():
			return _error(404, "not_found", "That party no longer exists.")
		var members: Array = doc["members"]
		if String(doc["status"]) != "open" or members.size() >= PARTY_CAP:
			return _error(409, "party_full", "That party is already full.")
		var now := GameState.now_utc()
		members.append(_self_member(now))
		doc["status"] = "full" if members.size() >= PARTY_CAP else "open"
		_mock_parties.erase(doc)
		_mock_my_party = doc
		var v := _party_view(doc, now)
		GameState.set_party(v)
		_save_netstate()
		return _wrap(200, {"party": v})
	var res: Dictionary = await _api("POST", "/v1/party/join", {"party_id": party_id, "code": code})
	if bool(res["ok"]):
		GameState.set_party(res["data"]["party"])
	return res


## POST /v1/party/leave. Leader hand-off; empty parties dissolve.
func party_leave() -> Dictionary:
	if mock:
		if _mock_my_party.is_empty():
			return _error(404, "not_found", "You are not in a party.")
		var my_uid := String(_self_member(GameState.now_utc())["uid"])
		var members: Array = _mock_my_party["members"]
		var rest: Array = members.filter(func(m: Dictionary) -> bool: return String(m["uid"]) != my_uid)
		if not rest.is_empty():
			# The bots keep the party going — it reopens in the finder.
			_mock_my_party["members"] = rest
			_mock_my_party["status"] = "open"
			if String(_mock_my_party["leader_uid"]) == my_uid:
				_mock_my_party["leader_uid"] = (rest[0] as Dictionary)["uid"]
			_mock_parties.append(_mock_my_party)
		_mock_my_party = {}
		GameState.set_party({})
		_save_netstate()
		return _wrap(200, {"left": true})
	var res: Dictionary = await _api("POST", "/v1/party/leave", {})
	if bool(res["ok"]):
		GameState.set_party({})
	return res


## Mirrors the server's PartyView assembly (services/parties.ts view()):
## join_code rides only members' payloads (mine/create/join), never the list.
func _party_view(doc: Dictionary, now: int, include_code: bool = false) -> Dictionary:
	var members: Array = []
	var key_sum := 0
	for m_v in doc["members"]:
		var m := (m_v as Dictionary).duplicate()
		var stage: Array = m["stage"]
		m["online"] = now - int(m["last_seen_at"]) <= PRESENCE_TTL
		m["leader"] = String(m["uid"]) == String(doc["leader_uid"])
		key_sum += int(stage[0]) * 100 + int(stage[1])
		members.append(m)
	var v := {
		"id": doc["id"],
		"name": doc["name"],
		"is_public": doc["is_public"],
		"status": doc["status"],
		"member_count": members.size(),
		"avg_stage_key": roundi(float(key_sum) / maxf(1.0, float(members.size()))),
		"members": members,
	}
	if include_code:
		v["join_code"] = String(doc.get("join_code", ""))
	return v


func _new_party_code() -> String:
	var out := "DELV-"
	for _i in 4:
		out += _CODE_ALPHABET[_rng.randi_range(0, _CODE_ALPHABET.length() - 1)]
	return out


func _is_party_code(s: String) -> bool:
	var re := RegEx.new()
	re.compile("^DELV-[0-9A-HJKMNP-TV-Z]{4}$")
	return re.search(s.to_upper()) != null


func _self_member(now: int) -> Dictionary:
	var profile: Dictionary = PlayerStats.compute()
	return {
		"uid": _uid if _uid != "" else "me",
		"name": GameState.player_name if GameState.player_name != "" else "Delver",
		"class_id": GameState.class_id,
		"level": GameState.player_level,
		"power": int(profile["total_power"]),
		"stage": [GameState.act, GameState.stage],
		"last_seen_at": now,
		"joined_at": now,
	}


func _refresh_self_member(now: int) -> void:
	var fresh := _self_member(now)
	var members: Array = _mock_my_party["members"]
	for i in members.size():
		var m: Dictionary = members[i]
		if String(m["uid"]) == String(fresh["uid"]):
			fresh["joined_at"] = m["joined_at"]
			members[i] = fresh
			return


## Seed ~6 open parties from the fake-delver pool, staged near the player.
func _ensure_mock_parties() -> void:
	if _mock_parties_seeded:
		return
	_mock_parties_seeded = true
	var now := GameState.now_utc()
	var pool: Array = GameContent.MOCK_DELVERS.duplicate()
	var names: Array = GameContent.MOCK_PARTY_NAMES.duplicate()
	for i in 6:
		var count := 1 + _rng.randi_range(0, 2)
		var members: Array = []
		for _j in count:
			if pool.is_empty():
				break
			var pick := _rng.randi_range(0, pool.size() - 1)
			members.append(_mock_bot_member(pool.pop_at(pick), now))
		if members.is_empty():
			break
		_mock_parties.append({
			"id": "mock-p%d" % i,
			"name": names[i % names.size()],
			"leader_uid": (members[0] as Dictionary)["uid"],
			"is_public": true,
			"join_code": _new_party_code(),
			"status": "open",
			"members": members,
		})


func _mock_bot_member(d: Dictionary, now: int) -> Dictionary:
	var act := clampi(GameState.act + _rng.randi_range(-1, 1), 1, 99)
	return {
		"uid": "bot-" + String(d["name"]).to_lower(),
		"name": String(d["name"]),
		"class_id": String(d["class_id"]),
		"level": int(d["lv"]),
		"power": int(d["lv"]) * 2800 + _rng.randi_range(0, 40000),
		"stage": [act, _rng.randi_range(1, 50)],
		"last_seen_at": now - _rng.randi_range(0, 170),
		"joined_at": now - _rng.randi_range(600, 86400),
	}


## Bots keep playing: presence refreshes, stages creep up.
func _drift_mock_members(members: Array, now: int) -> void:
	for m_v in members:
		var m: Dictionary = m_v
		if not String(m["uid"]).begins_with("bot-"):
			continue
		if _rng.randf() < 0.8:
			m["last_seen_at"] = now - _rng.randi_range(0, 60)
		if _rng.randf() < 0.12:
			var stage: Array = m["stage"]
			stage[1] = int(stage[1]) + 1
			if int(stage[1]) > 50:
				stage[1] = 1
				stage[0] = int(stage[0]) + 1


# =========================================================================
# Social (/v1/friends*, /v1/guild*) + Mailbox (/v1/mail*) — schemas mirror
# srv services/social.ts and services/mail.ts. Mock state (friends, guild,
# mailbox) persists in netstate.json; bots come from GameContent.MOCK_DELVERS.
# =========================================================================

const _CODE_ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const _MOCK_GUILDS := {
	"ASH": "Ashen Covenant",
	"HLW": "The Hollowed",
	"EMB": "Emberwatch",
}

var _mock_friends: Array = []      # bot names added as friends
var _mock_guild := ""              # joined guild tag ("" = none)
var _mock_mail: Array = []         # MailItem dicts (id/type/season/tier/granted/read/created_at)
var _mock_mail_seeded := false


## GET /v1/friends — {friend_code, friends: [{uid, name, lv, guild, power}]}.
func friends_get() -> Dictionary:
	if mock:
		var friends: Array = []
		for bot_name in _mock_friends:
			friends.append(_friend_summary(String(bot_name)))
		return _wrap(200, {"friend_code": _my_friend_code(), "friends": friends})
	return await _api("GET", "/v1/friends", {})


## POST /v1/friends/add {code} — mutual on add.
func friends_add(code: String) -> Dictionary:
	if mock:
		var norm := code.strip_edges().to_upper()
		if not _is_friend_code(norm):
			return _error(422, "invalid_payload", "Malformed friend code.")
		if norm == _my_friend_code():
			return _error(422, "invalid_payload", "You cannot add yourself.")
		for d in GameContent.MOCK_DELVERS:
			var bot_name := String(d["name"])
			if _derived_code(bot_name) == norm:
				if _mock_friends.has(bot_name):
					return _error(409, "already_friends", "Already friends.")
				if _mock_friends.size() >= 50:
					return _error(422, "friend_limit", "Friend list is full.")
				_mock_friends.append(bot_name)
				_save_netstate()
				return _wrap(200, {"added": {"uid": "bot-" + bot_name.to_lower(), "name": bot_name}})
		return _error(404, "not_found", "No player with that friend code.")
	var res: Dictionary = await _api("POST", "/v1/friends/add", {"code": code})
	return res


## GET /v1/guild — 404 when guildless.
func guild_get() -> Dictionary:
	if mock:
		if _mock_guild == "":
			return _error(404, "not_found", "You are not in a guild.")
		return _wrap(200, {"guild": _guild_view(_mock_guild)})
	return await _api("GET", "/v1/guild", {})


## POST /v1/guild/join {tag} — open join, one guild per player.
func guild_join(tag: String) -> Dictionary:
	if mock:
		var norm := tag.strip_edges().to_upper()
		if not _MOCK_GUILDS.has(norm):
			return _error(404, "not_found", "No guild with that tag.")
		_mock_guild = norm
		_save_netstate()
		return _wrap(200, {"guild": _guild_view(norm)})
	return await _api("POST", "/v1/guild/join", {"tag": tag})


## GET /v1/mail — {mail: [{id, type, season, tier, granted, read, created_at}]}.
func mail_list() -> Dictionary:
	if mock:
		_ensure_mock_mail()
		return _wrap(200, {"mail": _mock_mail.duplicate(true)})
	return await _api("GET", "/v1/mail", {})


## POST /v1/mail/claim {mail_id} — grants ride the save blob server-side;
## the mock grants straight into GameState.
func mail_claim(mail_id: String) -> Dictionary:
	if mock:
		_ensure_mock_mail()
		for m_v in _mock_mail:
			var m: Dictionary = m_v
			if String(m["id"]) != mail_id:
				continue
			if bool(m["read"]):
				return _error(409, "already_claimed", "Mail already claimed.")
			m["read"] = true
			var granted: Dictionary = m["granted"]
			if int(granted.get("gold", 0)) > 0:
				GameState.add_gold(int(granted["gold"]))
			_save_netstate()
			return _wrap(200, {"ok": true, "granted": {
				"gold": int(granted.get("gold", 0)),
				"items": (granted.get("items", []) as Array).duplicate(),
			}})
		return _error(404, "not_found", "No such mail.")
	var res: Dictionary = await _api("POST", "/v1/mail/claim", {"mail_id": mail_id})
	if bool(res["ok"]):
		var granted: Dictionary = res["data"].get("granted", {})
		if int(granted.get("gold", 0)) > 0:
			GameState.add_gold(int(granted["gold"]))
	return res


func _my_friend_code() -> String:
	return _derived_code(GameState.player_name if GameState.player_name != "" else "Delver")


## Stable Crockford-style code from any name (mock world's identity).
func _derived_code(seed_text: String) -> String:
	var h := hash(seed_text)
	var out := "GRIM-"
	for i in 4:
		out += _CODE_ALPHABET[(h >> (i * 5)) & 31]
	out += "-"
	for i in 2:
		out += _CODE_ALPHABET[(h >> (20 + i * 5)) & 31]
	return out


func _is_friend_code(s: String) -> bool:
	var re := RegEx.new()
	re.compile("^GRIM-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{2}$")
	return re.search(s.to_upper()) != null


func _friend_summary(bot_name: String) -> Dictionary:
	for d in GameContent.MOCK_DELVERS:
		if String(d["name"]) == bot_name:
			return {
				"uid": "bot-" + bot_name.to_lower(),
				"name": bot_name,
				"lv": int(d["lv"]),
				"guild": _bot_guild(bot_name),
				"power": int(d["lv"]) * 2800,
			}
	return {"uid": "bot-" + bot_name.to_lower(), "name": bot_name, "lv": 1, "guild": "", "power": 0}


## Deterministic bot guild assignment (some are guildless).
func _bot_guild(bot_name: String) -> String:
	var tags := _MOCK_GUILDS.keys()
	var idx := hash(bot_name) % (tags.size() + 1)
	return "" if idx == tags.size() else String(tags[idx])


func _guild_view(tag: String) -> Dictionary:
	var members: Array = []
	for d in GameContent.MOCK_DELVERS:
		var bot_name := String(d["name"])
		if _bot_guild(bot_name) == tag:
			members.append(_friend_summary(bot_name))
	members.append({
		"uid": _uid if _uid != "" else "me",
		"name": GameState.player_name if GameState.player_name != "" else "Delver",
		"lv": GameState.player_level,
		"guild": tag,
		"power": int(PlayerStats.compute()["total_power"]),
	})
	members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["power"]) > int(b["power"]))
	return {"id": tag.to_lower(), "tag": tag, "name": String(_MOCK_GUILDS[tag]), "members": members}


## Seed the mock mailbox once: one claimable season reward + one read notice.
func _ensure_mock_mail() -> void:
	if _mock_mail_seeded:
		return
	_mock_mail_seeded = true
	if not _mock_mail.is_empty():
		return
	var now := GameState.now_utc()
	_mock_mail = [
		{
			"id": "mail-s2-reward",
			"type": "season_reward",
			"season": 2,
			"tier": "Silver III",
			"granted": {"label": "Season 2 · Silver III", "gold": 25000, "items": ["Emberglass Charm"]},
			"read": false,
			"created_at": now - 86400 * 3,
		},
		{
			"id": "mail-welcome",
			"type": "notice",
			"season": 3,
			"tier": "",
			"granted": {"label": "Welcome to the Hollow", "gold": 0, "items": []},
			"read": true,
			"created_at": now - 86400 * 9,
		},
	]
	_save_netstate()


# =========================================================================
# Assets (/v1/assets/manifest) — the thin remote-sprite catalog. Bytes are
# fetched straight from the CDN by AssetManager, NOT through here. No auth
# (boot-path, like /v1/config). Mock returns the same schema the server's
# DEFAULT_CATALOG produces, with bundle urls pointing at res:// core folders
# so the whole pipeline runs offline.
# =========================================================================

## GET /v1/assets/manifest?since= — {catalog_version, cdn_base, bundles[]}.
func assets_manifest(since: int = 0) -> Dictionary:
	if mock:
		var cat := _mock_asset_catalog()
		# Equality gate, matching the server (catalog_version is an opaque
		# content token, not monotonic).
		if since == int(cat["catalog_version"]):
			return _wrap(200, {"catalog_version": cat["catalog_version"], "cdn_base": "",
				"bundles": [], "unchanged": true})
		return _wrap(200, cat)
	return await _api("GET", "/v1/assets/manifest?since=%d" % since, {}, false)


## Mirror of the server's DEFAULT_CATALOG (src/types/assets.ts). Core bundles
## are baked into the build (res://assets/core/<id>/); standard/lazy stream in
## live mode. In mock, every bundle resolves from res:// if its folder exists,
## else AssetManager falls back to the labeled placeholder — so missing art
## never breaks the game.
func _mock_asset_catalog() -> Dictionary:
	return {
		"catalog_version": 1,
		"cdn_base": "",
		"bundles": [
			{"id": "ui.core", "kind": "ui", "version": 1, "hash": "core", "bytes": 0, "url": "", "priority": "core", "deps": []},
			{"id": "hero.warrior", "kind": "hero", "version": 1, "hash": "core", "bytes": 0, "url": "", "priority": "core", "deps": []},
			{"id": "hero.mage", "kind": "hero", "version": 1, "hash": "core", "bytes": 0, "url": "", "priority": "core", "deps": []},
			{"id": "hero.hunter", "kind": "hero", "version": 1, "hash": "core", "bytes": 0, "url": "", "priority": "core", "deps": []},
			{"id": "hero.rogue", "kind": "hero", "version": 1, "hash": "core", "bytes": 0, "url": "", "priority": "core", "deps": []},
			{"id": "enemy.ghoul", "kind": "enemy", "version": 1, "hash": "core", "bytes": 0, "url": "", "priority": "core", "deps": []},
			{"id": "enemy.skeleton", "kind": "enemy", "version": 1, "hash": "core", "bytes": 0, "url": "", "priority": "core", "deps": []},
			{"id": "enemy.elite", "kind": "enemy", "version": 1, "hash": "s-elite-1", "bytes": 240000, "url": "bundles/enemy.elite.v1.pkg", "priority": "standard", "deps": []},
			{"id": "props.dungeon", "kind": "prop", "version": 1, "hash": "s-props-1", "bytes": 180000, "url": "bundles/props.dungeon.v1.pkg", "priority": "standard", "deps": []},
			{"id": "buildings.camp", "kind": "building", "version": 1, "hash": "s-bld-1", "bytes": 320000, "url": "bundles/buildings.camp.v1.pkg", "priority": "standard", "deps": []},
			{"id": "skin.warrior.ashen", "kind": "skin", "version": 1, "hash": "z-wsk-1", "bytes": 90000, "url": "bundles/skin.warrior.ashen.v1.pkg", "priority": "lazy", "deps": ["hero.warrior"]},
			{"id": "skin.mage.cinder", "kind": "skin", "version": 1, "hash": "z-msk-1", "bytes": 90000, "url": "bundles/skin.mage.cinder.v1.pkg", "priority": "lazy", "deps": ["hero.mage"]},
		],
	}


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
		var data := parsed as Dictionary
		_client_seq = int(data.get("client_seq", 0))
		var mp: Variant = data.get("mock_party", {})
		if mock and typeof(mp) == TYPE_DICTIONARY and not (mp as Dictionary).is_empty():
			_mock_my_party = mp
			GameState.set_party(_party_view(_mock_my_party, GameState.now_utc(), true))
		if mock:
			_mock_friends = data.get("mock_friends", [])
			_mock_guild = String(data.get("mock_guild", ""))
			_mock_mail = data.get("mock_mail", [])
			_mock_mail_seeded = bool(data.get("mock_mail_seeded", false))


func _save_netstate() -> void:
	var f := FileAccess.open(NETSTATE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"client_seq": _client_seq,
		"mock_party": _mock_my_party,
		"mock_friends": _mock_friends,
		"mock_guild": _mock_guild,
		"mock_mail": _mock_mail,
		"mock_mail_seeded": _mock_mail_seeded,
	}))
	f.close()


func _uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	return bytes.hex_encode()


static func _wrap(status: int, data: Dictionary) -> Dictionary:
	return {"ok": true, "status": status, "data": data}


static func _error(status: int, code: String, message: String) -> Dictionary:
	return {"ok": false, "status": status, "data": {"error": {"code": code, "message": message}}}
