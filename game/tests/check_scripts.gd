extends Node
## CI check: loads every script and scene in the project (with the autoloads
## running) so a parse or compile error fails the build instead of shipping.
## Then walks a fresh Mario around Castle Town for a moment so errors that
## only show up while playing print too. CI fails on exit code 1 or any
## "SCRIPT ERROR" in the output.
## Run: godot --headless res://tests/check_scripts.tscn

const CoopBattle := preload("res://scripts/coop_battle.gd")

func _ready() -> void:
	var bad: Array = []
	for path in _files("res://"):
		var res = load(path)
		if res == null or (res is GDScript and not res.can_instantiate()):
			bad.append(path)
	if bad.is_empty():
		print("check_scripts: all scripts and scenes load")
	else:
		printerr("check_scripts: failed to load: ", ", ".join(bad))
		get_tree().quit(1)
		return
	var quest_errors := _check_quests()
	if not quest_errors.is_empty():
		printerr("check_scripts: quests: ", "; ".join(quest_errors))
		get_tree().quit(1)
		return
	print("check_scripts: both questlines play through")
	var daily_errors := _check_dailies()
	if not daily_errors.is_empty():
		printerr("check_scripts: dailies: ", "; ".join(daily_errors))
		get_tree().quit(1)
		return
	print("check_scripts: every daily quest can be done")
	var ach_errors := _check_achievements()
	if not ach_errors.is_empty():
		printerr("check_scripts: achievements: ", "; ".join(ach_errors))
		get_tree().quit(1)
		return
	print("check_scripts: every achievement can be earned")
	var extra_errors := _check_login() + _check_late_game() + _check_minigames() + _check_partner_levels()
	if not extra_errors.is_empty():
		printerr("check_scripts: ", "; ".join(extra_errors))
		get_tree().quit(1)
		return
	print("check_scripts: daily login bonus, late-game areas, minigames and partner levels are sound")
	var pvp_errors := await _check_pvp()
	if not pvp_errors.is_empty():
		printerr("check_scripts: pvp: ", "; ".join(pvp_errors))
		get_tree().quit(1)
		return
	print("check_scripts: a 2 against 2 online battle plays to the end")
	# Play a little: load the overworld with a new save and hold right.
	# A town (walking NPCs) and a field (wandering enemies).
	for map_id in ["castle_town", "outskirts"]:
		Game.new_player("mario", "CI")
		Game.player["map"] = map_id
		var world: Node = load(Game.WORLD_SCENE).instantiate()
		get_tree().root.add_child.call_deferred(world)
		Input.action_press("move_right")
		await get_tree().create_timer(3.0).timeout
		Input.action_release("move_right")
		world.queue_free()
		await get_tree().process_frame
		print("check_scripts: overworld ran on ", map_id)
	var ruins_errors := await _check_ruins()
	if not ruins_errors.is_empty():
		printerr("check_scripts: ruins: ", "; ".join(ruins_errors))
		get_tree().quit(1)
		return
	print("check_scripts: both floors of the Teehee Ruins can be solved")
	var battle_errors := await _check_battle_fun()
	if not battle_errors.is_empty():
		printerr("check_scripts: battle: ", "; ".join(battle_errors))
		get_tree().quit(1)
		return
	print("check_scripts: enemy attacks can be dodged, combos and ranks add up")
	get_tree().quit(0)


## Enemy attack kinds (battle.gd _foe_attack): each one can be dodged by
## jumping as it hits, and dodges build the combo; standing still gets hit and
## ends it. Then the combo's damage bonus and the rank thresholds.
func _check_battle_fun() -> Array:
	var errors: Array = []
	Game.new_player("mario", "CI")
	Game.pending_battle = {"enemies": ["shadow_guy"], "key": "test"}
	var battle: Node = load(Game.BATTLE_SCENE).instantiate()
	get_tree().root.add_child(battle)
	battle.blocks.process_mode = Node.PROCESS_MODE_DISABLED  # nobody picks a command
	await get_tree().create_timer(0.3).timeout
	var f: Dictionary = battle.foes[0]
	var me: Dictionary = battle.allies[0]
	f["pow"] = 1
	var presser := {"on": true, "last": -1}
	var press := func():
		while presser["on"]:
			await get_tree().process_frame
			var at: int = battle.hit_at
			if at > 0 and at != presser["last"] and Time.get_ticks_msec() >= at - 130:
				presser["last"] = at
				var ev := InputEventAction.new()
				ev.action = &"action"
				ev.pressed = true
				Input.parse_input_event(ev)
				await get_tree().process_frame
				await get_tree().process_frame
				var up := InputEventAction.new()
				up.action = &"action"
				up.pressed = false
				Input.parse_input_event(up)
	press.call()
	var expected := 0
	for kind in ["charge", "feint", "double", "throw"]:
		var hp: int = Game.player["hp"]
		await battle.call("_foe_" + kind, f, me)
		expected += 2 if kind == "double" else 1
		if Game.player["hp"] != hp:
			errors.append("a well-timed jump didn't dodge the %s" % kind)
		await get_tree().create_timer(0.3).timeout
	if battle.combo != expected:
		errors.append("combo is %d after %d dodges" % [battle.combo, expected])
	presser["on"] = false
	await get_tree().create_timer(0.1).timeout
	await battle._foe_charge(f, me)
	if battle.hurt <= 0 or battle.combo != 0:
		errors.append("standing still didn't take the hit and end the combo")
	battle.combo = 3
	battle.lucky_chance = 0.0
	f["def"] = 0
	f["hp"] = 999
	f["max_hp"] = 999
	var dealt: int = battle._damage(f, 10)
	if dealt != 13:
		errors.append("a x3 combo hit for %d, not 13" % dealt)
	for c in [[0.0, 0, "S"], [0.1, 1, "A"], [0.3, 3, "B"], [0.9, 0, "C"]]:
		if battle.grade_for(c[0], c[1]) != c[2]:
			errors.append("rank for %s should be %s" % [c, c[2]])
	Engine.time_scale = 1.0
	battle.queue_free()
	await get_tree().process_frame
	return errors


## The Teehee Ruins (Dungeon): every piece stands on walkable ground, the
## way on is shut until the puzzle is worked, and working it in order (the
## one way that solves it) opens the way to the stairs and the prize.
func _check_ruins() -> Array:
	var errors: Array = []
	Game.new_player("mario", "CI")
	# shut: [spot, pieces left standing]: with everything else cleared away,
	# the spot still can't be reached (no way round a rock, gate or lock).
	var plans := {
		"teehee_ruins_1": {"from": Vector2(159, 462), "to": Vector2(240, 126),
			"steps": ["r3", "s1", "b1", "l1"],
			"shut": [[Vector2(254, 215), ["r1", "r2", "r3", "r4", "r5"]], [Vector2(175, 212), ["g1", "g2"]],
				[Vector2(240, 126), ["l1"]]]},
		"teehee_ruins_2": {"from": Vector2(255, 462), "to": Vector2(255, 166),
			"steps": ["sa", "sc", "r1", "b1", "l1"],
			"shut": [[Vector2(127, 186), ["r1", "r2"]], [Vector2(255, 166), ["g1"]], [Vector2(255, 166), ["g2"]],
				[Vector2(255, 166), ["g3"]], [Vector2(255, 166), ["l1"]]]},
	}
	for map_id in plans:
		Game.player["map"] = map_id
		Game.player["spawn"] = "south"
		Game.player["position"] = null
		var world: Node = load(Game.WORLD_SCENE).instantiate()
		get_tree().root.add_child(world)
		await get_tree().process_frame
		var plan: Dictionary = plans[map_id]
		for p in world.dungeon.pieces:
			var at: Vector2 = p["def"]["pos"] - Vector2(0, 2)
			if world.mask.get_pixel(int(at.x), int(at.y)).r < 0.5:
				errors.append("%s: %s stands off the floor" % [map_id, p["def"]["id"]])
		for shut in plan["shut"]:
			for p in world.dungeon.pieces:
				if p["def"]["kind"] in ["rock", "gate", "lock"]:
					Game.puzzle_state[map_id][p["def"]["id"]] = not p["def"]["id"] in shut[1]
			world.rebuild_collision()
			if _reachable(world, plan["from"], shut[0]):
				errors.append("%s: %s can be reached past %s" % [map_id, shut[0], shut[1]])
		Game.puzzle_state.clear()
		world.queue_free()
		await get_tree().process_frame
		world = load(Game.WORLD_SCENE).instantiate()
		get_tree().root.add_child(world)
		await get_tree().process_frame
		if _reachable(world, plan["from"], plan["to"]):
			errors.append("%s: the way on is open before the puzzle" % map_id)
		for id in plan["steps"]:
			var piece: Dictionary = world.dungeon.piece(id)
			var seen := _reach_set(world, plan["from"])
			var foot := Rect2(world.dungeon.foot(piece))
			if not seen.keys().any(func(c): return foot.grow(Dungeon.REACH - 4.0).has_point(Vector2(c * 3))):
				errors.append("%s: can't get next to %s" % [map_id, id])
			var line: String = world.dungeon.work(piece)
			if line.begins_with("A stone face"):
				errors.append("%s: no key for the lock" % map_id)
		if not _reachable(world, plan["from"], plan["to"]):
			errors.append("%s: still shut after the puzzle" % map_id)
		if map_id == "teehee_ruins_2":
			if not world.dungeon.work(world.dungeon.piece("prize")).begins_with("You cleared"):
				errors.append("the prize doesn't pay out")
			if not world.dungeon.work(world.dungeon.piece("prize")).contains("empty"):
				errors.append("the prize pays twice in a day")
		world.queue_free()
		await get_tree().process_frame
	return errors


## Can someone walk from a to b (a 3px grid of can_stand)?
func _reachable(world: Node, a: Vector2, b: Vector2) -> bool:
	var goal := Vector2i(b / 3.0)
	return _reach_set(world, a).keys().any(func(c): return (c - goal).length() <= 2.0)


## Every cell of the 3px grid you can walk to from a.
func _reach_set(world: Node, a: Vector2) -> Dictionary:
	a = world.nearest_walkable(a)
	var seen := {}
	var todo: Array = [Vector2i(a / 3.0)]
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		if seen.has(c):
			continue
		seen[c] = true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not seen.has(n) and world.can_stand(Vector2(n * 3)):
				todo.append(n)
	return seen


## An online battle, offline: you and a made-up teammate (evil, with
## partners) against two made-up good players, everyone picking and pressing
## by themselves, sped up. It has to get to a winner without script errors.
func _check_pvp() -> Array:
	Game.new_player("bowser", "CI")
	Game.player["party"].append(Game.make_member("enemy", "goomba"))
	Game.pending_battle = {"key": "", "pvp": {"bots": true, "auto": true, "no_exit": true, "host": "me", "players": [
		{"id": "me", "name": "CI", "side": "evil", "character": "bowser"},
		{"id": "b1", "name": "Mate", "side": "evil", "character": "koopa_bros"},
		{"id": "g1", "name": "Hero", "side": "good", "character": "mario"},
		{"id": "g2", "name": "Pal", "side": "good", "character": "luigi"}]}}
	var battle: Node = load(Game.PVP_SCENE).instantiate()
	var result := [""]
	battle.finished.connect(func(r): result[0] = r)
	Engine.time_scale = 6.0
	get_tree().root.add_child.call_deferred(battle)
	var waited := 0.0
	while result[0] == "" and waited < 120.0:
		await get_tree().create_timer(1.0, true, false, true).timeout
		waited += 1.0
	Engine.time_scale = 1.0
	var n: int = battle.actors.size()
	battle.queue_free()
	await get_tree().process_frame
	var errors := []
	if n != 8:
		errors.append("expected 8 fighters (2 players a side, each with a partner), got %d" % n)
	if result[0] == "":
		errors.append("the battle never ended")
	return errors


func _files(dir: String) -> Array:
	var out: Array = []
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			out += _files(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") or f.ends_with(".tscn"):
			out.append(dir.path_join(f))
	return out


## Plays each side's questline through Quests (no world): every step can be
## taken, done and claimed, givers and talk targets stand on some map, and
## rewards are real items.
func _check_quests() -> Array:
	var errors: Array = []
	var talk_ids := {}
	for map_id in Game.MAPS:
		for n in Game.MAPS[map_id]["npcs"]:
			talk_ids[n.get("talk", n["id"])] = true
	for side in Quests.LINES:
		var l: Dictionary = Quests.LINES[side]
		if not talk_ids.has(l["giver"]):
			errors.append("%s giver %s isn't on any map" % [side, l["giver"]])
		Game.new_player("mario" if side == "good" else "bowser", "CI")
		var steps: Array = l["steps"]
		if Quests.talk_event(l["giver"]).get("kind") != "offer":
			errors.append("%s: giver doesn't offer the first step" % side)
		Quests.accept()
		for i in steps.size():
			var step: Dictionary = steps[i]
			for id in step.get("reward", {}).get("items", {}):
				if Game.goods(id).is_empty():
					errors.append("%s step %d rewards unknown item %s" % [side, i, id])
			match step["goal"]:
				"defeat":
					Quests.on_defeat(["goomba"], "nowhere")  # wrong map: doesn't count
					for k in step["count"]:
						Quests.on_defeat(["goomba"], step.get("map", "outskirts"))
				"team":
					Game.add_member(Game.make_member("partner", "toad") if side == "good" else Game.make_member("enemy", "goomba"))
				"talk":
					if not talk_ids.has(step["talk"]):
						errors.append("%s step %d: %s isn't on any map" % [side, i, step["talk"]])
					if Quests.talk_event(step["talk"]).get("kind") != "talk":
						errors.append("%s step %d: talking to %s does nothing" % [side, i, step["talk"]])
					Quests.talked()
				"boss":
					Game.mark_boss_beaten(Game.BOSSES.keys()[0])
				"level":
					Game.gain_xp(99999)
			if not Quests.state().get("done", false):
				errors.append("%s step %d (%s) didn't finish" % [side, i, step["goal"]])
				break
			var coins: int = Game.player["coins"]
			if Quests.talk_event(l["giver"]).get("kind") != "reward" or Quests.claim().is_empty():
				errors.append("%s step %d: no reward" % [side, i])
				break
			if Game.player["coins"] <= coins:
				errors.append("%s step %d: reward gave no coins" % [side, i])
		if not Quests.state().get("finished", false):
			errors.append("%s line didn't finish" % side)
		if not Quests.talk_event(l["giver"]).is_empty():
			errors.append("%s giver still talks about the quest after it's done" % side)
		Game.quest_notes.clear()
	return errors


## Every daily task of every giver: the giver stands on its map, the task's
## enemy lives on its map, and taking, doing and claiming it pays out.
func _check_dailies() -> Array:
	var errors: Array = []
	for giver in Quests.DAILY:
		var d: Dictionary = Quests.DAILY[giver]
		if not Game.MAPS[d["map"]]["npcs"].any(func(n): return n.get("talk", n["id"]) == giver):
			errors.append("%s isn't on %s" % [giver, d["map"]])
		for i in d["tasks"].size():
			var task: Dictionary = d["tasks"][i]
			Game.new_player("mario", "CI")
			var s := Quests.daily_state(giver)
			s["task"] = i
			if Quests.daily_event(giver).get("kind") != "daily_offer":
				errors.append("%s task %d isn't offered" % [giver, i])
			Quests.daily_accept(giver)
			var had: int = Game.item_count(task.get("item", "mushroom"))
			match task["goal"]:
				"defeat":
					var map: String = task.get("map", "outskirts")
					var enemy: String = task.get("enemy", "goomba")
					if task.has("enemy") and not Game.MAPS[map]["enemies"].any(func(e): return e["type"] == enemy):
						errors.append("%s task %d: no %s on %s" % [giver, i, enemy, map])
					for k in task["count"]:
						Quests.on_defeat([enemy], map)
				"bring":
					if Game.goods(task["item"]).is_empty():
						errors.append("%s task %d: unknown item %s" % [giver, i, task["item"]])
					Game.add_item(task["item"], task["count"])
			var coins: int = Game.player["coins"]
			if Quests.daily_event(giver).get("kind") != "daily_reward" or Quests.daily_claim(giver).is_empty() \
					or Game.player["coins"] <= coins:
				errors.append("%s task %d: no reward" % [giver, i])
			elif task["goal"] == "bring" and Game.item_count(task["item"]) != had:
				errors.append("%s task %d: items not handed over" % [giver, i])
			if Quests.daily_event(giver).get("kind") != "daily_wait":
				errors.append("%s task %d: offered again the same day" % [giver, i])
	Game.quest_notes.clear()
	return errors


## A new save has none; one that has done everything earns them all, once,
## and every reward is a real item.
func _check_login() -> Array:
	var errors: Array = []
	Game.new_player("mario", "CI")
	var coins := int(Game.player["coins"])
	if Game.daily_login() == "" or int(Game.player["coins"]) != coins + Game.LOGIN_COINS:
		errors.append("first login of the day pays nothing")
	if Game.daily_login() != "":
		errors.append("login bonus paid twice in a day")
	# Six days in a row before today: today is day 7 and gives the badge.
	var yesterday := Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) - 86400)
	Game.player["login"] = {"day": yesterday, "streak": 6}
	var note := Game.daily_login()
	if Game.item_count("loyal_badge") != 1 or not "Loyal Badge" in note:
		errors.append("a 7-day streak doesn't give the Loyal Badge")
	Game.player["login"] = {"day": "2000-01-01", "streak": 30, "badge": true}
	Game.daily_login()
	if int(Game.player["login"]["streak"]) != 1:
		errors.append("a missed day doesn't reset the streak")
	return errors


func _check_partner_levels() -> Array:
	var errors: Array = []
	for id in Game.PARTNERS:
		if not Game.MOVES.has(Game.second_move_of("partner", id)):
			errors.append("%s's second move is missing" % id)
		if not Game.MOVES.has(Game.third_move_of("partner", id)):
			errors.append("%s's third move is missing" % id)
	Game.new_player("mario", "CI")
	var toad := Game.make_member("partner", "toad")
	Game.player["party"] = [toad]
	if Game.member_moves(toad).size() != 1:
		errors.append("a new partner already knows two moves")
	var xp := 0
	for lv in range(1, Game.MOVE2_LEVEL):
		xp += Game.xp_to_next(lv)
	var lines := Game.party_gain_xp(xp)
	if Game.member_level(toad) != Game.MOVE2_LEVEL or Game.member_moves(toad) != ["mushroom_toss", "super_toss"]:
		errors.append("a level %d partner doesn't know its second move" % Game.MOVE2_LEVEL)
	if not "Toad learned Super Toss!" in lines:
		errors.append("learning the second move isn't announced")
	var more := 0
	for lv in range(Game.MOVE2_LEVEL, Game.MOVE3_LEVEL):
		more += Game.xp_to_next(lv)
	lines = Game.party_gain_xp(more)
	if Game.member_moves(toad) != ["mushroom_toss", "super_toss", "ultra_toss"] or not "Toad learned Ultra Toss!" in lines:
		errors.append("a level %d partner doesn't learn its third move" % Game.MOVE3_LEVEL)
	if int(toad["pow"]) != int(Game.PARTNERS["toad"]["pow"]) + Game.MOVE3_LEVEL - 1:
		errors.append("partner POW doesn't grow with its levels")
	# A partner from an older save (it grew +1 POW with each of your levels).
	var old := {"kind": "enemy", "id": "goomba", "name": "Goomba", "hp": 9, "max_hp": 9,
		"pow": int(Game.ENEMIES["goomba"]["pow"]) + 6, "def": 0}
	if Game.member_level(old) != 7 or Game.member_moves(old) != [Game.move_of("enemy", "goomba"), "power_bash"]:
		errors.append("an older save's partner gets the wrong level")
	if CoopBattle.team_damage(5, 6, ["Excellent", "Good"]) != 17:
		errors.append("Team Attack damage is off")
	return errors


func _check_minigames() -> Array:
	var errors: Array = []
	Game.new_player("mario", "CI")
	var coins := int(Game.player["coins"])
	if Minigames.cast(-1.0)["fish"] != "" or int(Game.player["coins"]) != coins:
		errors.append("a missed bite still catches something")
	var golden := Minigames.cast(0.1, 0.999)
	if golden["fish"] != "Golden Cheep" or Game.item_count("ultra_mushroom") != 1:
		errors.append("a great reel can't land the Golden Cheep (got %s)" % golden["fish"])
	for i in 100:
		if Minigames.cast(0.8, i / 100.0)["fish"] in ["Big Cheep", "Golden Cheep"]:
			errors.append("a slow reel caught a rare fish")
			break
	if Minigames.casts_left() != 0:
		errors.append("casts aren't counted against the day")
	for f in Minigames.FISH:
		if f.has("item") and Game.goods(f["item"]).is_empty():
			errors.append("fish prize %s isn't an item" % f["item"])
	var supers := Game.item_count("super_mushroom")
	Minigames.rope_prize(25)
	Minigames.rope_prize(25)
	if Game.item_count("super_mushroom") != supers + 1 or int(Game.player["rope_best"]) != 25:
		errors.append("jump rope tier prizes aren't once a day")
	return errors


## The late-game enemies: sprites, drops, and on the maps meant for them.
func _check_late_game() -> Array:
	var errors: Array = []
	for map_id in ["twilight_meadow", "shadow_woods"]:
		if not Game.MAPS.has(map_id) or Game.MAPS[map_id]["enemies"].is_empty():
			errors.append("%s has no enemies" % map_id)
	for id in Game.ENEMIES:
		if not ResourceLoader.exists("res://assets/characters/%s.png" % id):
			errors.append("no sprite for %s" % id)
	for id in Game.DROPS:
		if Game.goods(Game.DROPS[id][0]).is_empty():
			errors.append("%s drops unknown item %s" % [id, Game.DROPS[id][0]])
	return errors


func _check_achievements() -> Array:
	var errors: Array = []
	Game.new_player("mario", "CI")
	if Achievements.check() != 0:
		errors.append("a new save already earns some")
	var p: Dictionary = Game.player
	p["wins"] = 999
	p["level"] = 50
	p["recruited"] = 20
	p["pvp_wins"] = 20
	var coins := int(p["coins"])
	Game.collect_bounty("Bowsy", 40)
	if int(p["coins"]) != coins + 40 or Achievements.progress("bounty_1")[0] != 1:
		errors.append("collecting a bounty doesn't pay or count")
	p["fish_caught"] = 20
	p["rope_best"] = 50
	p["dailies_done"] = 10
	p["trades"] = 1
	p["quests"] = {"good": {"step": 4, "count": 0, "done": false, "finished": true}}
	p["visited"] = Achievements.explore_maps()
	p["bosses"] = {}
	for id in Game.BOSSES:
		p["bosses"][id] = 1
	for a in Achievements.LIST:
		for id in a["reward"].get("items", {}):
			if Game.goods(id).is_empty():
				errors.append("%s rewards unknown item %s" % [a["id"], id])
	var got := Achievements.check()
	if got != Achievements.LIST.size():
		errors.append("only %d of %d earned" % [got, Achievements.LIST.size()])
	if Achievements.check() != 0:
		errors.append("earned twice")
	Game.quest_notes.clear()
	return errors
