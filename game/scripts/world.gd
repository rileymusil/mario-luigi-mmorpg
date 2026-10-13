extends Node2D
## A world map: draws the map art, keeps everyone on walkable ground (the
## map's _mask.png), spawns enemies and NPCs, and handles exits, talking and
## the pause menu. Which map to load comes from Game.player["map"].

const PLAYER_SPEED := 80.0
const FOLLOW_GAP := 18.0
const TOUCH_DISTANCE := 14.0
const TALK_DISTANCE := 26.0

var map_id := ""
var map_info: Dictionary
var map_size := Vector2.ZERO
var mask: Image

var player: CharacterSprite
var followers: Array[CharacterSprite] = []
var enemies: Array = []   # [{node, home, target, pause, key, type}]
var npcs: Array = []      # [{node, id}]
var busy := false         # true while a menu or dialog is open
var _grace := 1.5         # seconds after arriving before enemies can start a battle
var _trail: Array[Vector2] = []
var others := {}          # online players in this map: id -> {node, target, velocity}

@onready var actors: Node2D = $Actors
@onready var camera: Camera2D = $Camera2D
@onready var status: Label = $HUD/Status
@onready var hint: Label = $HUD/Hint
@onready var area_name: Label = $HUD/AreaName
@onready var dialog: Label = $HUD/Dialog
@onready var menu: ChoiceMenu = $HUD/Menu


func _ready() -> void:
	if Game.player.is_empty() and not Game.load_save():
		get_tree().call_deferred("change_scene_to_file", Game.TITLE_SCENE)
		return
	map_id = Game.player["map"]
	map_info = Game.MAPS[map_id]
	var art: Texture2D = load("res://assets/maps/%s.png" % map_id)
	$Map.texture = art
	map_size = art.get_size()
	mask = (load("res://assets/maps/%s_mask.png" % map_id) as Texture2D).get_image()
	camera.limit_right = int(map_size.x)
	camera.limit_bottom = int(map_size.y)

	player = _spawn_character(Game.player["character"])
	var pos: Vector2
	var arriving: bool = Game.player["position"] == null
	if not arriving:
		pos = Vector2(Game.player["position"][0], Game.player["position"][1])
	else:
		pos = map_info["spawns"].get(Game.player["spawn"], map_info["spawns"].values()[0])
	player.position = nearest_walkable(pos)
	for member in Game.player["party"]:
		var f := _spawn_character(member["id"])
		f.position = player.position
		followers.append(f)
	_trail = [player.position]
	camera.position = player.position
	camera.reset_smoothing()

	for i in map_info["enemies"].size():
		var e: Dictionary = map_info["enemies"][i]
		var key := "%s:%d" % [map_id, i]
		if Game.is_defeated(key):
			continue
		var node := _spawn_character(e["type"])
		node.position = nearest_walkable(e["pos"])
		enemies.append({"node": node, "home": node.position, "target": node.position, "pause": randf(), "key": key, "type": e["type"]})
	for n in map_info["npcs"]:
		if _in_party(n["id"]):
			continue
		var node := _spawn_character(n["id"])
		node.position = nearest_walkable(n["pos"])
		npcs.append({"node": node, "id": n["id"]})

	_join_online()

	dialog.visible = false
	if arriving:
		_show_area_name()
	else:
		area_name.modulate.a = 0.0
	Game.save()


# --- Other players online -----------------------------------------------------

func _join_online() -> void:
	Net.player_joined.connect(_on_player_joined)
	Net.player_moved.connect(_on_player_moved)
	Net.player_jumped.connect(_on_player_jumped)
	Net.player_left.connect(_on_player_left)
	Net.zone_reset.connect(_clear_others)
	# Coming back from a battle keeps the connection, so draw who is already here.
	for p in Net.players.values():
		_on_player_joined(p)
	Net.join_zone(map_id, Game.player["character"], Game.character_name(), player.position)


func _on_player_joined(p: Dictionary) -> void:
	if others.has(p["id"]) or not Game.CHARACTERS.has(p["character"]):
		return
	var node := _spawn_character(p["character"])
	node.position = Vector2(p["x"], p["y"])
	var tag := Label.new()
	tag.text = p["name"]
	tag.add_theme_font_size_override("font_size", 8)
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_constant_override("outline_size", 3)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.size = Vector2(80, 10)
	tag.position = Vector2(-40, -node.height() - 12)
	node.add_child(tag)
	others[p["id"]] = {"node": node, "target": node.position, "velocity": Vector2.ZERO}


func _on_player_moved(id: String, pos: Vector2, velocity: Vector2) -> void:
	if others.has(id):
		others[id]["target"] = pos
		others[id]["velocity"] = velocity


func _on_player_jumped(id: String) -> void:
	if others.has(id):
		others[id]["node"].jump()


func _on_player_left(id: String) -> void:
	if others.has(id):
		others[id]["node"].queue_free()
		others.erase(id)


func _clear_others() -> void:
	for o in others.values():
		o["node"].queue_free()
	others.clear()


## Updates arrive a few times a second; glide toward the latest one.
func _update_others(delta: float) -> void:
	for o in others.values():
		var node: CharacterSprite = o["node"]
		var to: Vector2 = o["target"] - node.position
		if to.length() > 96.0:
			node.position = o["target"]
		else:
			node.position += to.limit_length(maxf(PLAYER_SPEED * 1.2, to.length() * 6.0) * delta)
		# Walk animation follows their reported velocity, so it doesn't stutter
		# between updates; a last glide after they stop still animates.
		var velocity: Vector2 = o["velocity"]
		if velocity.length() < 1.0 and to.length() > 1.0:
			velocity = to.normalized() * PLAYER_SPEED
		node.move_velocity = velocity


func _spawn_character(id: String) -> CharacterSprite:
	var c := CharacterSprite.new()
	c.character_id = id
	actors.add_child(c)
	return c


func _in_party(id: String) -> bool:
	for m in Game.player["party"]:
		if m["id"] == id:
			return true
	return false


# --- Walkability ---------------------------------------------------------------

func walkable(p: Vector2) -> bool:
	if p.x < 2 or p.y < 2 or p.x >= map_size.x - 2 or p.y >= map_size.y - 2:
		return false
	return mask.get_pixel(int(p.x), int(p.y)).r > 0.5


## A body is about 10px wide at the feet.
func can_stand(p: Vector2) -> bool:
	return walkable(p) and walkable(p + Vector2(-5, 0)) and walkable(p + Vector2(5, 0))


func nearest_walkable(p: Vector2) -> Vector2:
	if can_stand(p):
		return p
	for r in range(4, 200, 4):
		for i in 16:
			var q := p + Vector2.from_angle(TAU * i / 16.0) * r
			if can_stand(q):
				return q
	return p


func _try_move(node: Node2D, delta_pos: Vector2) -> Vector2:
	var start := node.position
	for step in [delta_pos, Vector2(delta_pos.x, 0), Vector2(0, delta_pos.y)]:
		if step.length() > 0.0 and can_stand(start + step):
			node.position = start + step
			break
	return node.position - start


# --- Every frame ---------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null:
		return
	_update_hud()
	_update_others(delta)
	Net.update_position(player.position, Vector2.ZERO if busy else player.move_velocity)
	if busy:
		player.move_velocity = Vector2.ZERO
		for f in followers:
			f.move_velocity = Vector2.ZERO
		return

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var moved := _try_move(player, input * PLAYER_SPEED * delta)
	player.move_velocity = moved / maxf(delta, 0.0001)
	camera.position = player.position
	_update_followers(delta)
	_update_enemies(delta)

	if Input.is_action_just_pressed("action"):
		if not player.is_airborne():
			Net.send_jump()
		player.jump()
	elif Input.is_action_just_pressed("talk"):
		var npc = _nearest_npc()
		if npc != null:
			_talk_to(npc)
	elif Input.is_action_just_pressed("menu"):
		_pause_menu()

	for exit in map_info["exits"]:
		if exit["rect"].has_point(player.position):
			busy = true
			Game.go_to_map(exit["to"], exit["spawn"])
			return


func _update_followers(delta: float) -> void:
	if _trail.back().distance_to(player.position) > 1.0:
		_trail.append(player.position)
	# Each follower walks the leader's path, FOLLOW_GAP pixels further back.
	var total := 0.0
	var idx := _trail.size() - 1
	for f in followers:
		var want := FOLLOW_GAP * (followers.find(f) + 1)
		while idx > 0 and total < want:
			total += _trail[idx].distance_to(_trail[idx - 1])
			idx -= 1
		var target := _trail[idx]
		var step := target - f.position
		f.position = target
		f.move_velocity = step / maxf(delta, 0.0001) if step.length() > 0.05 else Vector2.ZERO
	var keep := int(FOLLOW_GAP * (followers.size() + 2))
	if _trail.size() > keep:
		_trail = _trail.slice(_trail.size() - keep)


func _update_enemies(delta: float) -> void:
	_grace -= delta
	for e in enemies:
		var node: CharacterSprite = e["node"]
		if e["pause"] > 0.0:
			e["pause"] -= delta
			node.move_velocity = Vector2.ZERO
		else:
			var to: Vector2 = e["target"] - node.position
			var moved := _try_move(node, to.limit_length(28.0 * delta))
			node.move_velocity = moved / maxf(delta, 0.0001)
			if to.length() < 1.0 or moved.length() < 0.01:
				e["pause"] = randf_range(0.5, 1.8)
				e["target"] = e["home"] + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 48.0
		if _grace <= 0.0 and node.position.distance_to(player.position) < TOUCH_DISTANCE:
			_start_battle(e)
			return


func _start_battle(e: Dictionary) -> void:
	busy = true
	var types: Array = [e["type"]]
	# Sometimes a second enemy from this area joins in.
	if randf() < 0.4:
		types.append(map_info["enemies"].pick_random()["type"])
	Game.start_battle(types, e["key"], player.position + (player.position - e["node"].position).normalized() * 20.0)
	Game.pending_battle["first_strike"] = player.is_airborne()


# --- Talking and menus ---------------------------------------------------------

func _nearest_npc():
	for n in npcs:
		if n["node"].position.distance_to(player.position) < TALK_DISTANCE:
			return n
	return null


func say(text: String) -> void:
	busy = true
	dialog.text = text
	dialog.visible = true
	await get_tree().process_frame
	while not (Input.is_action_just_pressed("action") or Input.is_action_just_pressed("talk")):
		await get_tree().process_frame
	dialog.visible = false
	await get_tree().process_frame
	busy = false


func _talk_to(n: Dictionary) -> void:
	var info: Dictionary = Game.PARTNERS[n["id"]]
	if Game.player["side"] == "evil":
		await say("%s: Eek! You're one of Bowser's bunch! Stay back!" % info["name"])
		return
	busy = true
	dialog.text = "%s: Going out to the Outskirts? It's dangerous out there..." % info["name"]
	dialog.visible = true
	var i := await menu.choose(["Ask to join", "Never mind"], "", true)
	dialog.visible = false
	busy = false
	if i != 0:
		return
	if not Game.can_recruit():
		await say("Your party is full. Send someone home from the menu (Enter) first.")
		return
	if randf() < info["recruit"]:
		Game.player["party"].append(Game.make_member("partner", n["id"]))
		var node: CharacterSprite = n["node"]
		npcs.erase(n)
		followers.append(node)
		Game.save()
		await say("%s joined your party!" % info["name"])
	else:
		await say("%s: Hmm... I'm not sure yet. Ask me again?" % info["name"])


func _pause_menu() -> void:
	busy = true
	var p: Dictionary = Game.player
	var other := "Evil" if p["side"] == "good" else "Good"
	var options := ["Use Mushroom (%d)" % p["mushrooms"], "Party", "Switch to %s side" % other, "Save", "Quit to title", "Close"]
	var i := await menu.choose(options, "Menu", true)
	match i:
		0:
			if p["mushrooms"] > 0 and p["hp"] < p["max_hp"]:
				p["mushrooms"] -= 1
				p["hp"] = mini(p["max_hp"], p["hp"] + 10)
				await say("You ate a Mushroom. +10 HP")
		1:
			await _party_menu()
		2:
			var c := await menu.choose(["Yes, switch", "No"], "Switch sides? Your party goes home.", true)
			if c == 0:
				Game.switch_side()
				return
		3:
			Game.save()
			await say("Game saved in this browser.")
		4:
			Game.save()
			Net.leave()
			get_tree().change_scene_to_file(Game.TITLE_SCENE)
			return
	busy = false


func _party_menu() -> void:
	var party: Array = Game.player["party"]
	if party.is_empty():
		await say("Nobody is with you yet. Good players can ask partners in town; evil players can ask enemies in battle.")
		return
	var names: Array = []
	for m in party:
		names.append("%s  HP %d/%d" % [m["name"], m["hp"], m["max_hp"]])
	var i := await menu.choose(names, "Send someone home?", true)
	if i < 0:
		return
	var c := await menu.choose(["Send home", "Keep"], "", true)
	if c == 0:
		party.remove_at(i)
		var f: CharacterSprite = followers[i]
		followers.remove_at(i)
		f.queue_free()
		Game.save()


func _show_area_name() -> void:
	area_name.text = map_info["name"]
	area_name.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(1.5)
	t.tween_property(area_name, "modulate:a", 0.0, 0.6)


func _update_hud() -> void:
	var p: Dictionary = Game.player
	status.text = "%s Lv%d   HP %d/%d   SP %d/%d   Coins %d" % [Game.character_name(), p["level"], p["hp"], p["max_hp"], p["sp"], p["max_sp"], p["coins"]]
	if busy:
		hint.text = ""
	elif _nearest_npc() != null:
		hint.text = "X: Talk"
	else:
		hint.text = "Arrows: move   Z: jump   X: talk   Enter: menu" + ("" if map_info["safe"] else "   Jump on enemies for a first strike!")
