extends Node2D
## A world map: draws the map art and its props (trees and buildings you can
## walk behind, see map_props.gd), keeps everyone on walkable ground (the
## map's _mask.png minus prop footprints), spawns enemies and NPCs, and handles
## exits, talking and the pause menu. Which map to load comes from
## Game.player["map"]. Debug builds have a map editor on F2 (map_editor.gd).

const PLAYER_SPEED := 80.0
const FOLLOW_GAP := 18.0
const TOUCH_DISTANCE := 14.0
const TALK_DISTANCE := 26.0
const FOOT_HALF_WIDTH := 5.0  # everyone's feet are 10px wide
const FOOT_DEPTH := 3.0

var map_id := ""
var map_info: Dictionary
var map_size := Vector2.ZERO
var mask: Image            # the ground: white = walkable (what the map editor paints)
var solid: Image           # mask with prop footprints blocked (what collision reads)
var props := MapProps.new()
var editing := false       # true while the map editor is open

var player: CharacterSprite
var followers: Array[CharacterSprite] = []
var enemies: Array = []   # [{node, home, target, pause, key, type}]
var npcs: Array = []      # [{node, id}]
var busy := false         # true while a menu or dialog is open
var _grace := 1.5         # seconds after arriving before enemies can start a battle
var _trail: Array[Vector2] = []
var online: OnlinePlayers # other players on this map, see online_players.gd

@onready var actors: Node2D = $Actors
@onready var camera: Camera2D = $Camera2D
@onready var status: Hud = $HUD/Hud
@onready var hint: Label = $HUD/HintBox/Hint
@onready var area_name: AreaBanner = $HUD/AreaName
@onready var dialog: DialogueBox = $HUD/Dialogue
@onready var menu: ChoiceMenu = $HUD/Menu
@onready var pause_screen: PauseScreen = $HUD/PauseScreen
@onready var party_screen: PartyScreen = $HUD/PartyScreen
@onready var talk_bubble: TextureRect = $HUD/TalkBubble


func _ready() -> void:
	if Game.player.is_empty() and not Game.load_save():
		get_tree().call_deferred("change_scene_to_file", Game.TITLE_SCENE)
		return
	map_id = Game.player["map"]
	map_info = Game.MAPS[map_id]
	var art: Texture2D = load("res://assets/maps/%s.png" % map_id)
	$Map.texture = art
	map_size = art.get_size()
	mask = MapProps.load_mask(map_id)
	props.load_props(map_id)
	props.build(actors, art)
	rebuild_collision()
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

	online = OnlinePlayers.new()
	add_child(online)
	# Their game may use an older mask; show them on our walkable ground.
	online.snap = nearest_walkable
	online.setup(self, _spawn_character, player, map_id)
	if MapEditor.available():
		add_child(MapEditor.new())

	dialog.visible = false
	if arriving:
		_show_area_name()
	else:
		area_name.modulate.a = 0.0
	Game.save()


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

## Rebuilds what collision reads after the mask or the props change.
func rebuild_collision() -> void:
	solid = mask.duplicate()
	if solid.get_format() != Image.FORMAT_L8:
		solid.convert(Image.FORMAT_L8)
	props.paint_feet(solid)


func walkable(p: Vector2) -> bool:
	if p.x < 2 or p.y < 2 or p.x >= map_size.x - 2 or p.y >= map_size.y - 2:
		return false
	return solid.get_pixel(int(p.x), int(p.y)).r > 0.5


## Feet are a 10x3px box at the bottom of every character (player, followers,
## enemies, other players all use the same one).
func can_stand(p: Vector2) -> bool:
	for dx in [-FOOT_HALF_WIDTH, 0.0, FOOT_HALF_WIDTH]:
		for dy in [0.0, -FOOT_DEPTH]:
			if not walkable(p + Vector2(dx, dy)):
				return false
	return true


func nearest_walkable(p: Vector2) -> Vector2:
	if can_stand(p):
		return p
	for r in range(2, 240, 2):
		var steps := clampi(r * 2, 12, 64)
		for i in steps:
			var q := p + Vector2.from_angle(TAU * i / steps) * r
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
	props.update_fade(player, delta)
	online.tick(delta, busy or editing)
	if busy or editing:
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


## Clicking or tapping someone with the "!" bubble over them talks to them,
## the same as pressing X.
func _unhandled_input(event: InputEvent) -> void:
	if not talk_bubble.visible or not Pointer.is_press(event):
		return
	var npc: Variant = _nearest_npc()
	if npc == null:
		return
	var node: CharacterSprite = npc["node"]
	var feet := node.get_global_transform_with_canvas().origin
	var body := Rect2(feet - Vector2(14, node.height() + 4), Vector2(28, node.height() + 8))
	if talk_bubble.get_global_rect().grow(6).has_point(event.position) or body.has_point(event.position):
		get_viewport().set_input_as_handled()
		Pointer.tap_action(&"talk")


## Shows a speech balloon until Z or X. speaker/anchor: who is talking (name
## tab and balloon tail), if anyone.
func say(text: String, speaker := "", anchor: Node2D = null) -> void:
	var was_busy := busy
	busy = true
	await dialog.say(text, speaker, anchor)
	await get_tree().process_frame
	busy = was_busy


func _talk_to(n: Dictionary) -> void:
	var info: Dictionary = Game.PARTNERS[n["id"]]
	var node: CharacterSprite = n["node"]
	if Game.player["side"] == "evil":
		await say("Eek! You're one of Bowser's bunch! Stay back!", info["name"], node)
		return
	busy = true
	dialog.open("Going out to the Outskirts? It's dangerous out there...", info["name"], node)
	menu.position = Vector2(270, dialog.box.position.y - 52 if dialog.box.position.y > 100 else dialog.box.position.y + dialog.box.size.y + 4)
	var i := await menu.choose(["Ask to join", "Never mind"], "", true)
	dialog.close()
	if i != 0:
		await get_tree().process_frame
		busy = false
		return
	if not Game.can_recruit():
		await say("Your party is full. Send someone home from the menu (Enter) first.")
		busy = false
		return
	if randf() < info["recruit"]:
		Game.player["party"].append(Game.make_member("partner", n["id"]))
		npcs.erase(n)
		followers.append(node)
		Game.save()
		await say("%s joined your party!" % info["name"])
	else:
		await say("Hmm... I'm not sure yet. Ask me again?", info["name"], node)
	busy = false


func _pause_menu() -> void:
	busy = true
	var p: Dictionary = Game.player
	var other := "Evil" if p["side"] == "good" else "Good"
	while true:
		pause_screen.open(p, Game.character_name(), map_info["name"])
		var options := ["Mushroom x%d" % p["mushrooms"], "Party", "Go %s" % other, "Save", "Quit", "Close"]
		var i := await pause_screen.menu.choose(options, "", true)
		match i:
			0:
				if p["mushrooms"] <= 0:
					await say("You don't have any Mushrooms.")
				elif p["hp"] >= p["max_hp"]:
					await say("Your HP is already full.")
				else:
					p["mushrooms"] -= 1
					p["hp"] = mini(p["max_hp"], p["hp"] + 10)
					await say("You ate a Mushroom. +10 HP")
				continue
			1:
				pause_screen.close()
				await _party_menu()
				continue
			2:
				dialog.open("Switch to the %s side? Your party goes home." % other.to_lower())
				var c := await pause_screen.menu.choose(["Yes, switch", "No"], "", true)
				dialog.close()
				if c == 0:
					pause_screen.close()
					Game.switch_side()
					return
				continue
			3:
				Game.save()
				await say("Game saved in this browser.")
			4:
				Game.save()
				Net.leave()
				get_tree().change_scene_to_file(Game.TITLE_SCENE)
				return
		break
	pause_screen.close()
	await get_tree().process_frame
	busy = false


func _party_menu() -> void:
	var party: Array = Game.player["party"]
	party_screen.open(Game.player, Game.character_name())
	if party.is_empty():
		await say("Nobody is with you yet. Good players can ask partners in town; evil players can ask enemies in battle.")
		party_screen.close()
		return
	var names: Array = []
	for m in party:
		names.append(m["name"])
	var i := await party_screen.menu.choose(names, "Send home?", true)
	if i >= 0:
		var c := await party_screen.menu.choose(["Send home", "Keep"], party[i]["name"], true)
		if c == 0:
			party.remove_at(i)
			var f: CharacterSprite = followers[i]
			followers.remove_at(i)
			f.queue_free()
			Game.save()
	party_screen.close()


func _show_area_name() -> void:
	area_name.show_name(map_info["name"])


func _update_hud() -> void:
	var p: Dictionary = Game.player
	status.refresh(p, Game.character_name())
	var npc: Variant = null if busy else _nearest_npc()
	if busy:
		hint.text = ""
	elif npc != null:
		hint.text = "B or tap: Talk" if TouchControls.active else "X: Talk"
	else:
		hint.text = ("A: Jump   B: Talk" if TouchControls.active else "Z: Jump   X: Talk   Enter: Menu") \
			+ ("" if map_info["safe"] else "   Jump on foes first!")
	var hint_box: Control = hint.get_parent()
	hint_box.visible = hint.text != ""
	hint_box.reset_size()
	hint_box.position.x = roundf((get_viewport_rect().size.x - hint_box.size.x) / 2.0)
	# A "!" bubble pops up over whoever you can talk to.
	talk_bubble.visible = npc != null
	if npc != null:
		var node: CharacterSprite = npc["node"]
		var head := node.get_global_transform_with_canvas().origin - Vector2(0, node.height() + 6)
		var bob := roundf(absf(sin(Time.get_ticks_msec() / 160.0)) * 2.0)
		talk_bubble.position = (head - Vector2(talk_bubble.size.x / 2.0, talk_bubble.size.y + bob)).round()
