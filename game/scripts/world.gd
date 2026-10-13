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
const LEVEL_PX := 16.0      # how high one level of the height layer is
const CLIMB_SLACK := 3.0    # a jump this much lower than a ledge still makes it
const MAX_LEDGE := 80       # tallest ledge face you can drop down (px)
const FACINGS := {"down": Vector2.DOWN, "up": Vector2.UP, "left": Vector2.LEFT, "right": Vector2.RIGHT}

var map_id := ""
var map_info: Dictionary
var map_size := Vector2.ZERO
var mask: Image            # the ground: white = walkable (what the map editor paints)
var solid: Image           # mask with prop footprints blocked (what collision reads)
var height: Image          # ground levels and ledge faces (see "Height" below)
var props := MapProps.new()
var editing := false       # true while the map editor is open

var player: CharacterSprite
var followers: Array[CharacterSprite] = []
var enemies: Array = []   # [{node, home, target, pause, key, type}]
var npcs: Array = []      # [{node, id}]
var busy := false         # true while a menu or dialog is open
var _grace := 1.5         # seconds after arriving before enemies can start a battle
## The leader's path, followed by the party: x, y, 1 where a jump started,
## and the jump height change where the leader hopped a ledge face.
var _trail: Array[Vector4] = []
var _trail_start := 0     # how many trail points were dropped from the front
var _hop_shift := 0.0     # set when the player hops a ledge face this frame
## Z confirms menus and X closes them, but they also jump and talk out here.
## After anything that took the keys (a menu, someone talking, a battle, a
## text box), the world ignores them until they have been let go, so the
## press that closed it doesn't also jump, talk or open the menu.
var _keys_locked := true
var _unlocked_frame := -1
const WORLD_KEYS: Array[StringName] = [&"action", &"talk", &"menu"]
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
	height = MapProps.load_height(map_id, Vector2i(map_size))
	props.load_props(map_id)
	props.build(actors, art)
	rebuild_collision()
	_fit_camera()

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
	_trail = [Vector4(player.position.x, player.position.y, 0.0, 0.0)]
	player.jumped.connect(_on_player_jumped)
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
		node.position = n["pos"] if n.get("fixed", false) else nearest_walkable(n["pos"])
		node.facing = FACINGS.get(n.get("face", "down"), Vector2.DOWN)
		npcs.append({"node": node, "id": n["id"], "talk": n.get("talk", n["id"]),
			"reach": n.get("reach", TALK_DISTANCE), "face": node.facing})

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


## Keeps the camera inside the map. A room smaller than the screen is shown
## centred on black.
func _fit_camera() -> void:
	var pad := ((get_viewport_rect().size - map_size) / 2.0).max(Vector2.ZERO).ceil()
	camera.limit_left = -int(pad.x)
	camera.limit_top = -int(pad.y)
	camera.limit_right = int(map_size.x + pad.x)
	camera.limit_bottom = int(map_size.y + pad.y)
	if pad != Vector2.ZERO:
		var backdrop := ColorRect.new()
		backdrop.color = Color.BLACK
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backdrop.position = -pad - Vector2(8, 8)
		backdrop.size = map_size + pad * 2.0 + Vector2(16, 16)
		backdrop.z_index = -2
		add_child(backdrop)


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


## Ground you can stand on: walkable in the mask, no prop footprint, and not
## a ledge face of the height layer.
func walkable(p: Vector2) -> bool:
	if p.x < 2 or p.y < 2 or p.x >= map_size.x - 2 or p.y >= map_size.y - 2:
		return false
	return solid.get_pixel(int(p.x), int(p.y)).r > 0.5 \
		and MapProps.value_level(height.get_pixel(int(p.x), int(p.y)).r8) != -1


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


# --- Height: raised ground, ledges and cliffs ----------------------------------
# The height layer (<map>_height.png, see MapProps.load_height) gives the ground
# a level. Walking onto higher ground needs a jump at least LEVEL_PX high per
# level (one level is a jump, two is a cliff); walking off it drops you down.
# A ledge face (the drawn side of raised ground, blocked in the walk mask) can
# be jumped up while walking up the screen into it, if the jump is as high as
# the face is tall, and dropped down while walking down the screen. The feet
# move across the face in one step and the jump height changes by the same
# amount, so the sprite doesn't move on screen: it looks like landing on top,
# or falling off.

## Ground level (0 = lowest) at map pixel (x, y), or -1 on a ledge face.
func height_px(x: int, y: int) -> int:
	x = clampi(x, 0, height.get_width() - 1)
	y = clampi(y, 0, height.get_height() - 1)
	return MapProps.value_level(height.get_pixel(x, y).r8)


## The level of the ground under someone's feet: the highest ground any part
## of their foot box is on.
func level_at(p: Vector2) -> int:
	var best := 0
	for dx in [-FOOT_HALF_WIDTH, 0.0, FOOT_HALF_WIDTH]:
		for dy in [0.0, -FOOT_DEPTH]:
			best = maxi(best, height_px(int(p.x + dx), int(p.y + dy)))
	return best


## Can someone on ground level `from_level`, `air` px up in a jump, step to `to`?
func can_step(to: Vector2, from_level: int, air: float, can_drop: bool) -> bool:
	if not can_stand(to):
		return false
	var level := level_at(to)
	if level > from_level:
		return air >= (level - from_level) * LEVEL_PX - CLIMB_SLACK
	return level == from_level or can_drop


## Crosses a ledge face straight up or down the screen from `node`'s feet, if
## `delta_pos` walks into one: up needs a jump as high as the face, down needs
## `can_drop`. Returns true if `node` moved.
func _ledge_hop(node: CharacterSprite, delta_pos: Vector2, can_drop: bool) -> bool:
	if absf(delta_pos.y) < absf(delta_pos.x) * 0.9:
		return false  # faces are crossed going up or down the screen
	var up := delta_pos.y < 0.0
	var start := node.position
	var x := int(start.x)
	var face := 0
	var reach := int(ceilf(absf(delta_pos.y))) + 3  # the face must start right in front
	for k in range(1, MAX_LEDGE + 8):
		var p := start + Vector2(0.0, -k if up else k)
		var lead := int(p.y - FOOT_DEPTH) if up else int(p.y)  # the row the feet push into
		if lead < 2 or lead >= map_size.y - 2:
			return false
		if height_px(x, lead) == -1:
			face += 1
			if face > MAX_LEDGE:
				return false
		elif not walkable(Vector2(x, lead)):
			return false  # a wall, water...: not a ledge
		elif face == 0:
			if k > reach:
				return false
		elif can_stand(p):
			var from_level := level_at(start)
			var to_level := level_at(p)
			if up:
				var need := maxf(face, (to_level - from_level) * LEVEL_PX) - CLIMB_SLACK
				if node.jump_height < need:
					return false
			elif not can_drop:
				return false
			var shift := p.y - start.y
			node.position = p
			node.set_air(node.jump_height + shift)
			if node == player:
				_hop_shift = shift
			return true
		elif k > face + reach + int(FOOT_DEPTH) + 6:
			return false  # walkable ground past the face, but nowhere to stand
	return false


## Moves `node` by up to `delta_pos` and returns how far it went. It slides
## along walls (straight or slanted) and round small corners, climbs onto
## higher ground or up a ledge face when it is jumping high enough, and drops
## off ledges unless `can_drop` is false (enemies stay on their own level).
func _try_move(node: CharacterSprite, delta_pos: Vector2, can_drop := true) -> Vector2:
	var start := node.position
	if delta_pos.length_squared() == 0.0:
		return Vector2.ZERO
	var level := level_at(start)
	var air := node.jump_height
	# 1. Straight on.
	if can_step(start + delta_pos, level, air, can_drop):
		node.position = start + delta_pos
		return delta_pos
	# 2. Up or down a ledge face.
	if _ledge_hop(node, delta_pos, can_drop):
		return node.position - start
	# 3. Slide along a wall: keep the part of the step that isn't blocked.
	for step in [Vector2(delta_pos.x, 0.0), Vector2(0.0, delta_pos.y)]:
		if step.length() > 0.05 and can_step(start + step, level, air, can_drop):
			node.position = start + step
			return step
	# 4. Slide along a slanted wall (diagonal edges of cliffs and water).
	for angle in [PI / 6.0, -PI / 6.0, PI / 4.0, -PI / 4.0, PI / 3.0, -PI / 3.0]:
		var step: Vector2 = delta_pos.rotated(angle) * cos(angle)
		if can_step(start + step, level, air, can_drop):
			node.position = start + step
			return step
	# 5. Round a small corner: sidestep 1-3px while walking straight on.
	var side := Vector2(-delta_pos.y, delta_pos.x).normalized()
	for nudge in [1.0, -1.0, 2.0, -2.0, 3.0, -3.0]:
		var step: Vector2 = delta_pos * 0.6 + side * nudge
		if can_step(start + step, level, air, can_drop):
			node.position = start + step
			return step
	# 6. Creep up to the wall.
	if can_step(start + delta_pos * 0.5, level, air, can_drop):
		node.position = start + delta_pos * 0.5
		return delta_pos * 0.5
	return Vector2.ZERO


# --- Every frame ---------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null:
		return
	_update_hud()
	props.update_fade(player, delta)
	online.tick(delta, busy or editing)
	if busy or editing:
		_keys_locked = true
		player.move_velocity = Vector2.ZERO
		for f in followers:
			f.move_velocity = Vector2.ZERO
		return

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var moved := _try_move(player, input * PLAYER_SPEED * delta)
	player.move_velocity = moved / maxf(delta, 0.0001)

	# Dynamic camera lead: smoothly tilts focus slightly ahead in movement direction
	var lead := player.facing * 12.0 if player.move_velocity.length() > 15.0 else Vector2.ZERO
	camera.position = player.position + lead

	_update_followers(delta)
	_update_enemies(delta)

	if not keys_ready():
		pass
	elif Input.is_action_just_pressed("action"):
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
		# Doors open when you walk up into them, not when you pass in front.
		if exit["rect"].has_point(player.position) and (not exit.get("door", false) or input.y < -0.3):
			busy = true
			Game.go_to_map(exit["to"], exit["spawn"])
			return


## False while a key that closed a menu or a talk is still held down (and on
## the frame it is let go), see _keys_locked.
func keys_ready() -> bool:
	if _keys_locked:
		for action in WORLD_KEYS:
			if Input.is_action_pressed(action) or Input.is_action_just_released(action):
				return false
		_keys_locked = false
		_unlocked_frame = Engine.get_process_frames()
	# A press and release in the same frame (a quick tap) still counts as
	# "just pressed" then: let the frame it unlocked on go by too.
	return _unlocked_frame != Engine.get_process_frames()


func _update_followers(delta: float) -> void:
	var last := _trail.back() as Vector4
	if Vector2(last.x, last.y).distance_to(player.position) > 1.0 or _hop_shift != 0.0:
		_trail.append(Vector4(player.position.x, player.position.y, 0.0, _hop_shift))
		_hop_shift = 0.0
	# Each follower walks the leader's path, FOLLOW_GAP pixels further back,
	# jumping where the leader jumped and hopping the same ledges.
	var total := 0.0
	var idx := _trail.size() - 1
	for i in followers.size():
		var f := followers[i]
		var want := FOLLOW_GAP * (i + 1)
		while idx > 0 and total < want:
			total += Vector2(_trail[idx].x, _trail[idx].y).distance_to(Vector2(_trail[idx - 1].x, _trail[idx - 1].y))
			idx -= 1
		var serial := _trail_start + idx
		var seen: int = f.get_meta("trail", serial)
		for s in range(maxi(seen + 1, _trail_start), serial + 1):
			var t := _trail[s - _trail_start]
			if t.z > 0.0:
				f.jump()
			if t.w != 0.0:
				f.set_air(f.jump_height + t.w)
		f.set_meta("trail", serial)
		var target := Vector2(_trail[idx].x, _trail[idx].y)
		var step := target - f.position
		f.position = target
		f.move_velocity = step / maxf(delta, 0.0001) if step.length() > 0.05 and step.length() < 8.0 else Vector2.ZERO
	var keep := int(FOLLOW_GAP * (followers.size() + 2))
	if _trail.size() > keep:
		var cut := _trail.size() - keep
		_trail = _trail.slice(cut)
		_trail_start += cut


## The party jumps where the leader jumped (when they get there).
func _on_player_jumped() -> void:
	var last := _trail.back() as Vector4
	if Vector2(last.x, last.y).distance_to(player.position) <= 1.0:
		last.z = 1.0
		_trail[_trail.size() - 1] = last
	else:
		_trail.append(Vector4(player.position.x, player.position.y, 1.0, 0.0))


func _update_enemies(delta: float) -> void:
	_grace -= delta
	for e in enemies:
		var node: CharacterSprite = e["node"]
		if e["pause"] > 0.0:
			e["pause"] -= delta
			node.move_velocity = Vector2.ZERO
		else:
			var to: Vector2 = e["target"] - node.position
			var moved := _try_move(node, to.limit_length(28.0 * delta), false)
			node.move_velocity = moved / maxf(delta, 0.0001)
			if to.length() < 1.0 or moved.length() < 0.01:
				e["pause"] = randf_range(0.5, 1.8)
				e["target"] = e["home"] + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 48.0
		if _grace <= 0.0 and node.position.distance_to(player.position) < TOUCH_DISTANCE \
				and level_at(node.position) == level_at(player.position):
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
	var best = null
	var best_d := INF
	for n in npcs:
		var d: float = n["node"].position.distance_to(player.position)
		if d < n["reach"] and d < best_d:
			best = n
			best_d = d
	return best


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


## Talks to an NPC using its lines in res://data/dialogue.json (see
## dialogue_data.gd): pages, then an optional choice that can recruit, open a
## shop or heal.
func _talk_to(n: Dictionary) -> void:
	var node: CharacterSprite = n["node"]
	var branch := DialogueData.pick(n["talk"], Game.player)
	var speaker := DialogueData.speaker(n["talk"], n["id"])
	var pages := DialogueData.pages(branch)
	var choices: Array = branch.get("choices", [])
	busy = true
	node.facing = (player.position - node.position).normalized()  # turn to whoever is talking
	for i in pages.size():
		if i == pages.size() - 1 and not choices.is_empty():
			break  # the last page stays up as the question
		await say(DialogueData.fill(pages[i]), speaker, node)
	var joined := false
	if not choices.is_empty():
		var question: String = DialogueData.fill(pages.back()) if not pages.is_empty() else ""
		joined = await _ask(n, branch, question, speaker)
	if not joined:
		node.facing = n["face"]
	# Two frames, so the X that closed a menu can't start this talk again.
	await get_tree().process_frame
	await get_tree().process_frame
	busy = false


## Puts the choice menu just above (or below) the speech balloon, on screen.
## Call it deferred, so the menu already has its size for the new options.
func _place_menu() -> void:
	var box: Control = dialog.box
	var x := minf(270.0, get_viewport_rect().size.x - menu.size.x - 4.0)
	var y := box.position.y - menu.size.y - 2.0 if box.position.y > 100 else box.position.y + box.size.y + 4.0
	menu.position = Vector2(x, y).round()


## Shows the question with the branch's choices and does what the pick says.
## Returns true if the NPC joined your party.
func _ask(n: Dictionary, branch: Dictionary, question: String, speaker: String) -> bool:
	var node: CharacterSprite = n["node"]
	var choices: Array = branch["choices"]
	dialog.open(question, speaker, node)
	_place_menu.call_deferred()
	var labels := choices.map(func(c): return str(c["text"]))
	var i := await menu.choose(labels, "", true)
	dialog.close()
	if i < 0:
		return false
	var choice: Dictionary = choices[i]
	for page in choice.get("say", []):
		await say(DialogueData.fill(page), speaker, node)
	match choice.get("do", ""):
		"recruit":
			return await _recruit(n, speaker)
		"shop":
			await _shop(branch.get("shop", []), speaker, node)
		"heal":
			_heal_party()
			await say(DialogueData.fill(choice.get("done", "Your HP and SP are full again!")))
	return false


func _recruit(n: Dictionary, speaker: String) -> bool:
	var node: CharacterSprite = n["node"]
	if not Game.PARTNERS.has(n["id"]):
		push_warning("%s can't join a party (not in Game.PARTNERS)" % n["id"])
		return false
	var info: Dictionary = Game.PARTNERS[n["id"]]
	if not Game.can_recruit():
		await say("Your party is full. Send someone home from the menu (Enter) first.")
		return false
	if randf() < info["recruit"]:
		Game.player["party"].append(Game.make_member("partner", n["id"]))
		npcs.erase(n)
		followers.append(node)
		Game.save()
		await say("%s joined your party!" % info["name"])
		return true
	await say("Hmm... I'm not sure yet. Ask me again?", speaker, node)
	return false


## A shop counter: buy from `stock` ([{item, count, price}]) until Done.
func _shop(stock: Array, speaker: String, node: Node2D) -> void:
	var p: Dictionary = Game.player
	while true:
		var labels := []
		var enabled := []
		var infos := []
		for s in stock:
			var item: Dictionary = Game.ITEMS[s["item"]]
			var count := int(s.get("count", 1))
			labels.append("%s%s  %d coins" % [item["name"], " x%d" % count if count > 1 else "", int(s["price"])])
			enabled.append(p["coins"] >= int(s["price"]))
			infos.append("%s You have %d." % [item["info"], p.get(item["key"], 0)])
		labels.append("Done")
		enabled.append(true)
		infos.append("You have %d coins." % p["coins"])
		dialog.open("You have %d coins. What would you like?" % p["coins"], speaker, node)
		_place_menu.call_deferred()
		var i := await menu.choose(labels, "", true, enabled, infos)
		dialog.close()
		if i < 0 or i >= stock.size():
			break
		var s: Dictionary = stock[i]
		var item: Dictionary = Game.ITEMS[s["item"]]
		p["coins"] -= int(s["price"])
		p[item["key"]] = int(p.get(item["key"], 0)) + int(s.get("count", 1))
		Game.save()
		await say(DialogueData.fill(s.get("thanks", "Thank you! Come again!")), speaker, node)


func _heal_party() -> void:
	var p: Dictionary = Game.player
	p["hp"] = p["max_hp"]
	p["sp"] = p["max_sp"]
	for member in p["party"]:
		member["hp"] = member["max_hp"]
	Game.save()


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
