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
	# Play a little: load the overworld with a new save and hold right.
	Game.new_player("mario", "CI")
	Game.player["map"] = "castle_town"
	var world: Node = load(Game.WORLD_SCENE).instantiate()
	get_tree().root.add_child.call_deferred(world)
	Input.action_press("move_right")
	await get_tree().create_timer(2.0).timeout
	Input.action_release("move_right")
	print("check_scripts: overworld ran")
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
