extends Node
## Map check bot: walks every map the way a player can (walking, jumping up
## one level, hopping ledge faces, dropping down) and reports problems:
##   - stuck spots: places you can get to but can't get out of (no exit or
##     spawn reachable from there),
##   - exits, NPCs and enemies you can't reach from where you arrive,
##   - spawn points you can't stand on.
## Run: godot --headless res://tests/map_check.tscn -- [map_id ...] [--images=DIR]
## With --images it also writes DIR/<map>.png: green = reachable, red = stuck,
## blue = walkable but never reachable.

const GRID := 4
const JUMP_MAX := 27.0  # CharacterSprite: JUMP_SPEED^2 / (2 * GRAVITY)
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]

var problems := 0


func _ready() -> void:
	var maps: Array = []
	var image_dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--images="):
			image_dir = a.trim_prefix("--images=")
		else:
			maps.append(a)
	if maps.is_empty():
		maps = Game.MAPS.keys()
	for map_id in maps:
		await _check(map_id, image_dir)
	print("map_check: %d problem(s)" % problems)
	get_tree().quit(1 if problems > 0 else 0)


func _report(map_id: String, text: String) -> void:
	problems += 1
	print("PROBLEM %s: %s" % [map_id, text])


func _check(map_id: String, image_dir: String) -> void:
	Game.new_player("mario", "Bot")
	Game.player["map"] = map_id
	var info: Dictionary = Game.MAPS[map_id]
	var w: Node = load(Game.WORLD_SCENE).instantiate()
	get_tree().root.add_child.call_deferred(w)
	await get_tree().process_frame
	await get_tree().process_frame
	if w.dungeon:
		# The Teehee Ruins: walk them with every puzzle solved (rocks smashed,
		# gates open, locks gone); check_scripts checks the puzzles themselves.
		for piece in w.dungeon.pieces:
			Game.puzzle_state[map_id][piece["def"]["id"]] = true
		w.rebuild_collision()
	var size: Vector2i = Vector2i(w.map_size)
	var cols := size.x / GRID
	var rows := size.y / GRID
	var probe := CharacterSprite.new()

	var stand := {}  # Vector2i cell -> true
	for cy in rows:
		for cx in cols:
			if w.can_stand(Vector2(cx * GRID, cy * GRID)):
				stand[Vector2i(cx, cy)] = true

	# Moves from each cell (walk, jump up a level, ledge hops, drops).
	var edges := {}
	for c in stand:
		var a := Vector2(c * GRID)
		var level: int = w.level_at(a)
		var out: Array = []
		for d in DIRS:
			var n: Vector2i = c + d
			if stand.has(n) and w.can_step(Vector2(n * GRID), level, JUMP_MAX, true):
				out.append(n)
		for dy in [-GRID, GRID]:
			probe.position = a
			probe.jump_height = JUMP_MAX
			if w._ledge_hop(probe, Vector2(0, dy), true):
				var n := _snap(stand, probe.position)
				if n != Vector2i(-1, -1):
					out.append(n)
		edges[c] = out

	# Where you arrive: spawn points.
	var starts: Array = []
	for s in info["spawns"]:
		var p: Vector2 = info["spawns"][s]
		var c := _snap(stand, w.nearest_walkable(p))
		if not w.can_stand(p) and w.nearest_walkable(p).distance_to(p) > 12.0:
			_report(map_id, "spawn '%s' %s is not on walkable ground" % [s, p])
		if c != Vector2i(-1, -1):
			starts.append(c)
	var reach := _flood(starts, edges)

	# Ways out: cells inside an exit, plus spawn cells (you can always leave
	# the way you came in only if that is an exit too, so spawns don't count).
	var goals: Array = []
	for e in info["exits"]:
		var r: Rect2 = e["rect"].grow(3.0)
		var hit := false
		for c in stand:
			if r.has_point(Vector2(c * GRID)):
				goals.append(c)
				hit = hit or reach.has(c)
		if not hit:
			_report(map_id, "exit to %s at %s can't be reached" % [e["to"], e["rect"].position])
	var back := {}
	for c in edges:
		for n in edges[c]:
			if not back.has(n):
				back[n] = []
			back[n].append(c)
	var can_leave := _flood(goals, back)

	var stuck := {}
	for c in reach:
		if not can_leave.has(c):
			stuck[c] = true
	for cluster in _clusters(stuck):
		if cluster.size() >= 3:
			var box := Rect2(Vector2(cluster[0] * GRID), Vector2.ZERO)
			for c in cluster:
				box = box.expand(Vector2(c * GRID))
			_report(map_id, "stuck spot (can get in, can't get out) around %s, %d cells" % [box.get_center().round(), cluster.size()])

	for n in info["npcs"]:
		if not _near(reach, n["pos"], n.get("reach", w.TALK_DISTANCE) - 4.0):
			_report(map_id, "NPC %s at %s can't be reached to talk to" % [n["id"], n["pos"]])
		for p in n.get("path", []):
			if not stand.has(_snap(stand, p)) or _snap(stand, p) == Vector2i(-1, -1):
				_report(map_id, "NPC %s path point %s is off walkable ground" % [n["id"], p])
	for e in info["enemies"]:
		if not _near(reach, e["pos"], 16.0):
			_report(map_id, "enemy %s at %s can't be reached" % [e["type"], e["pos"]])

	print("map_check %s: %d walkable cells, %d reachable, %d stuck" % [map_id, stand.size(), reach.size(), stuck.size()])
	if image_dir != "":
		var img: Image = (w.get_node("Map").texture as Texture2D).get_image()
		img.convert(Image.FORMAT_RGBA8)
		for c in stand:
			var col := Color(0.2, 0.4, 1.0)
			if stuck.has(c):
				col = Color(1.0, 0.1, 0.1)
			elif reach.has(c):
				col = Color(0.2, 1.0, 0.3)
			for y in GRID:
				for x in GRID:
					var px: int = c.x * GRID + x
					var py: int = c.y * GRID + y
					if px < size.x and py < size.y:
						img.set_pixel(px, py, img.get_pixel(px, py).lerp(col, 0.45))
		DirAccess.make_dir_recursive_absolute(image_dir)
		img.save_png(image_dir.path_join(map_id + ".png"))
	probe.free()
	w.queue_free()
	await get_tree().process_frame


func _snap(stand: Dictionary, p: Vector2) -> Vector2i:
	var base := Vector2i((p / GRID).round())
	for r in 3:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if stand.has(base + Vector2i(dx, dy)):
					return base + Vector2i(dx, dy)
	return Vector2i(-1, -1)


func _flood(starts: Array, graph: Dictionary) -> Dictionary:
	var seen := {}
	var queue: Array = starts.duplicate()
	for s in starts:
		seen[s] = true
	while not queue.is_empty():
		var c = queue.pop_back()
		for n in graph.get(c, []):
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen


func _clusters(cells: Dictionary) -> Array:
	var left := cells.duplicate()
	var out: Array = []
	while not left.is_empty():
		var first = left.keys()[0]
		var group: Array = [first]
		left.erase(first)
		var i := 0
		while i < group.size():
			for d in DIRS:
				var n: Vector2i = group[i] + d
				if left.has(n):
					left.erase(n)
					group.append(n)
			i += 1
		out.append(group)
	return out


func _near(reach: Dictionary, p: Vector2, dist: float) -> bool:
	var r := int(ceil(dist / GRID))
	var base := Vector2i((p / GRID).round())
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := base + Vector2i(dx, dy)
			if reach.has(c) and Vector2(c * GRID).distance_to(p) <= dist:
				return true
	return false
