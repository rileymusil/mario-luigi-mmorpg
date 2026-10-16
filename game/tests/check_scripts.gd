extends Node
## CI check: loads every script and scene in the project (with the autoloads
## running) so a parse or compile error fails the build instead of shipping.
## Then walks a fresh Mario around Castle Town for a moment so errors that
## only show up while playing print too. CI fails on exit code 1 or any
## "SCRIPT ERROR" in the output.
## Run: godot --headless res://tests/check_scripts.tscn

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
	get_tree().quit(0)


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
