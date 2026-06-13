extends GutTest
## Party endpoints (BackendClient mock) must honor the server contract:
## envelope shapes, one-party-per-player, the 4-member cap, leader hand-off,
## and the GameState.party mirror staying in sync.


func before_each() -> void:
	# These tests validate the offline mock contract; force it on regardless of
	# the production default (which is now live — mock=false).
	BackendClient.mock = true
	GameState.reset_to_defaults()
	BackendClient._mock_my_party = {}
	BackendClient._mock_parties = []
	BackendClient._mock_parties_seeded = false


func after_all() -> void:
	GameState.reset_to_defaults()
	# Leave no test party behind in user://netstate.json.
	BackendClient._mock_my_party = {}
	BackendClient._save_netstate()


func test_create_party_makes_me_leader() -> void:
	var res: Dictionary = await BackendClient.party_create("Ember Pact")
	assert_true(bool(res["ok"]))
	var party: Dictionary = res["data"]["party"]
	assert_eq(String(party["name"]), "Ember Pact")
	assert_eq(String(party["status"]), "open")
	assert_eq(int(party["member_count"]), 1)
	var me: Dictionary = party["members"][0]
	assert_true(bool(me["leader"]), "creator leads")
	assert_true(bool(me["online"]), "creator is online")
	assert_true(GameState.in_party(), "the mirror reflects membership")


func test_create_rejects_bad_names_and_double_party() -> void:
	var bad: Dictionary = await BackendClient.party_create("ab")
	assert_false(bool(bad["ok"]))
	assert_eq(int(bad["status"]), 422)
	assert_true(bool((await BackendClient.party_create("The Hollow Court"))["ok"]))
	var dup: Dictionary = await BackendClient.party_create("Second Banner")
	assert_false(bool(dup["ok"]))
	assert_eq(String(dup["data"]["error"]["code"]), "already_partied")


func test_list_shows_open_parties_with_presence() -> void:
	var res: Dictionary = await BackendClient.party_list()
	assert_true(bool(res["ok"]))
	var parties: Array = res["data"]["parties"]
	assert_true(parties.size() >= 4, "the mock world seeds open parties")
	var last_key := 1 << 30
	for p_v in parties:
		var p: Dictionary = p_v
		assert_eq(String(p["status"]), "open")
		assert_true(int(p["member_count"]) < 4)
		assert_true(int(p["avg_stage_key"]) <= last_key, "sorted by stage, descending")
		last_key = int(p["avg_stage_key"])
		for m_v in p["members"]:
			var m: Dictionary = m_v
			assert_true(m.has("online") and m.has("leader") and m.has("stage"))


func test_join_then_leave_round_trip() -> void:
	var listing: Dictionary = await BackendClient.party_list()
	var open_n: int = (listing["data"]["parties"] as Array).size()
	var target: Dictionary = listing["data"]["parties"][0]
	var before := int(target["member_count"])

	var joined: Dictionary = await BackendClient.party_join(String(target["id"]))
	assert_true(bool(joined["ok"]))
	assert_eq(int(joined["data"]["party"]["member_count"]), before + 1)
	assert_true(GameState.in_party())

	# My party left the open list.
	var relisted: Dictionary = await BackendClient.party_list()
	assert_eq((relisted["data"]["parties"] as Array).size(), open_n - 1)

	# Double-join is refused.
	var again: Dictionary = await BackendClient.party_join(String(target["id"]))
	assert_eq(String(again["data"]["error"]["code"]), "already_partied")

	# Leaving hands the banner back to the bots (it reopens in the finder).
	var left: Dictionary = await BackendClient.party_leave()
	assert_true(bool(left["ok"]))
	assert_false(GameState.in_party())
	var final_list: Dictionary = await BackendClient.party_list()
	assert_eq((final_list["data"]["parties"] as Array).size(), open_n)


func test_join_full_party_refused() -> void:
	var now := GameState.now_utc()
	var members: Array = []
	for i in 4:
		members.append({"uid": "bot-x%d" % i, "name": "X%d" % i, "class_id": "mage",
			"level": 40, "power": 1000, "stage": [4, 7], "last_seen_at": now, "joined_at": now})
	BackendClient._mock_parties_seeded = true
	BackendClient._mock_parties = [{"id": "mock-full", "name": "Full House",
		"leader_uid": "bot-x0", "is_public": true, "status": "full", "members": members}]
	var res: Dictionary = await BackendClient.party_join("mock-full")
	assert_false(bool(res["ok"]))
	assert_eq(String(res["data"]["error"]["code"]), "party_full")


func test_leave_when_solo_is_not_found() -> void:
	var res: Dictionary = await BackendClient.party_leave()
	assert_false(bool(res["ok"]))
	assert_eq(int(res["status"]), 404)


func test_mine_refreshes_self_presence() -> void:
	await BackendClient.party_create("Last Lantern")
	GameState.act = 6
	GameState.stage = 21
	var res: Dictionary = await BackendClient.party_mine()
	assert_true(bool(res["ok"]))
	var me: Dictionary = res["data"]["party"]["members"][0]
	assert_eq(int((me["stage"] as Array)[0]), 6, "presence carries the live act")
	assert_eq(int((me["stage"] as Array)[1]), 21, "presence carries the live stage")
	assert_eq(int(res["data"]["party"]["avg_stage_key"]), 621)


func test_mine_when_solo_returns_null_party() -> void:
	var res: Dictionary = await BackendClient.party_mine()
	assert_true(bool(res["ok"]))
	assert_null(res["data"]["party"])
