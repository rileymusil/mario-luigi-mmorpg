extends Node
## Manual check of online battles against a local server (not run in CI):
##   cd server && npx wrangler dev --port 8787
##   then one Godot per player, e.g. for 2 against 2:
##   godot --headless res://tests/pvp_net_check.tscn -- --server=ws://127.0.0.1:8787 --role=e1
##   (roles e1, e2: evil, e1 attacks; g1, g2: good; --players=2 for 1 against 1)
## Everyone picks and presses by themselves. Each prints how its battle
## ended; --shots=<dir> saves screenshots along the way (needs a display).
## --offline plays against made-up players instead (no server); with
## --manual too, you pick and press yourself.

const UIDS := {"e1": "a1a1a1a1a1a1", "e2": "a2a2a2a2a2a2", "g1": "b1b1b1b1b1b1", "g2": "b2b2b2b2b2b2"}
const LOOKS := {"e1": "bowser", "e2": "koopa_bros", "g1": "mario", "g2": "luigi"}
const BUDDIES := {"e1": ["enemy", "goomba"], "e2": ["enemy", "koopa"], "g1": ["partner", "toad"], "g2": ["partner", "pianta"]}

var role := "e1"
var count := 4
var shots := ""
var battle: Node = null
var offline := false
var manual := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
		elif arg.begins_with("--players="):
			count = int(arg.trim_prefix("--players="))
		elif arg.begins_with("--shots="):
			shots = arg.trim_prefix("--shots=")
		elif arg == "--offline":
			offline = true
		elif arg == "--manual":
			manual = true
	Game.new_player(LOOKS[role], role.to_upper())
	Game.player["uid"] = UIDS[role]
	Game.player["map"] = "outskirts"
	Game.player["coins"] = 100
	Game.player["party"].append(Game.make_member(BUDDIES[role][0], BUDDIES[role][1]))
	if offline:
		var list := []
		for r in ["e1", "e2", "g1", "g2"].slice(0, count) if count == 4 else ["e1", "g1"]:
			list.append({"id": "me" if r == role else r, "name": r.to_upper(), "side": "evil" if r.begins_with("e") else "good",
				"character": LOOKS[r]})
		_on_start({"host": "me", "players": list, "bots": true})
		return
	Net.in_world = true
	Net.challenged.connect(func(_foe): Net.answer_challenge(true))
	Net.invited.connect(func(from_id, _who): Net.answer_invite(from_id, true))
	Net.duel_started.connect(_on_start)
	Net.join_zone("outskirts", Game.player["character"], role.to_upper(), Vector2(100, 100))
	print(role, ": joining")
	await _until(func(): return Net.is_online(), 10.0)
	if count == 4 and role in ["e1", "g1"]:
		var mate: String = UIDS["e2" if role == "e1" else "g2"]
		await _until(func(): return Net.players.has(mate), 20.0)
		Net.send_invite(mate)
		await _until(func(): return Net.party_id == mate, 10.0)
		print(role, ": teamed up")
	if role == "e1":
		await _until(func(): return Net.players.has(UIDS["g1"]), 20.0)
		await get_tree().create_timer(3.0).timeout  # everyone teamed up
		Net.challenge(UIDS["g1"])
		print(role, ": attacks g1")
	await get_tree().create_timer(240.0).timeout
	print(role, ": timed out")
	get_tree().quit(1)


func _on_start(info: Dictionary) -> void:
	print(role, ": battle with ", info["players"].size(), " players")
	Net.in_world = false
	Game.pending_battle = {"key": "", "pvp": info.merged({"auto": not manual, "no_exit": true})}
	battle = load(Game.PVP_SCENE).instantiate()
	battle.finished.connect(_on_finished)
	get_tree().root.add_child.call_deferred(battle)
	if shots != "":
		for k in 40:
			await get_tree().create_timer(2.5).timeout
			if not is_instance_valid(battle):
				return
			get_viewport().get_texture().get_image().save_png("%s/%s_%02d.png" % [shots, role, k])


func _on_finished(result: String) -> void:
	print(role, ": battle over: ", result, " coins ", Game.player["coins"], " items ", Game.player["items"])
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0)


func _until(check: Callable, timeout: float) -> void:
	var waited := 0.0
	while not check.call() and waited < timeout:
		await get_tree().process_frame
		waited += get_process_delta_time()
