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
const BOSS_REACH := 40.0     # bosses are big: you can talk to them from further off
const BOSS_FOOT := Vector2(16, 10)  # the smallest solid block under a boss (see _paint_boss_feet)
const FOOT_HALF_WIDTH := 5.0  # everyone's feet are 10px wide
const FOOT_DEPTH := 3.0
const LEVEL_PX := 16.0      # how high one level of the height layer is
const CLIMB_SLACK := 3.0    # a jump this much lower than a ledge still makes it
const MAX_LEDGE := 80       # tallest ledge face you can drop down (px)
const FOLLOWER_CLIMB := 22.0  # how high a follower jumps before hopping up after the leader
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
var score_box: PanelContainer  # this week's good vs evil score, in towns
var save_prompt: TextPrompt  # password box for saving online (made when first needed)
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
@onready var items_screen: ItemsScreen = $HUD/ItemsScreen
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
	_spawn_bosses()  # before anyone else: they stand on solid feet (see rebuild_collision)
	_fit_camera()
	get_tree().root.size_changed.connect(_on_viewport_resized)

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

	if map_info["safe"]:
		_show_weekly_score()
	dialog.visible = false
	if arriving:
		_show_area_name()
	else:
		area_name.modulate.a = 0.0
	Game.save()


var _backdrop: ColorRect


## Keeps the camera inside the map. A room smaller than the screen is shown
## centred on dark backdrop.
func _fit_camera() -> void:
	var vp := get_viewport_rect().size
	var pad := ((vp - map_size) / 2.0).max(Vector2.ZERO).ceil()
	camera.limit_left = -int(pad.x)
	camera.limit_top = -int(pad.y)
	camera.limit_right = int(map_size.x + pad.x)
	camera.limit_bottom = int(map_size.y + pad.y)
	if pad != Vector2.ZERO:
		if _backdrop == null:
			_backdrop = ColorRect.new()
			_backdrop.color = Color(0.02, 0.02, 0.04)
			_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_backdrop.z_index = -2
			add_child(_backdrop)
		_backdrop.position = -pad - Vector2(100, 100)
		_backdrop.size = map_size + pad * 2.0 + Vector2(200, 200)
		_backdrop.visible = true
	elif _backdrop:
		_backdrop.visible = false


func _spawn_character(id: String) -> CharacterSprite:
	var c := CharacterSprite.new()
	c.character_id = id
	actors.add_child(c)
	return c


func _in_party(id: String) -> bool:
	for m in Game.player["party"] + Game.bench():
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
	_paint_boss_feet()


## Bosses don't step aside: a small block of ground under each one is solid
## (BOSS_FOOT, wider for wide bosses), so you bump into them instead of
## walking through. Talking reaches further than that (BOSS_REACH).
func _paint_boss_feet() -> void:
	for n in npcs:
		if not n.has("boss"):
			continue
		var node: CharacterSprite = n["node"]
		var w := clampf(node.width() * 0.4, BOSS_FOOT.x, 34.0)
		var r := Rect2i(Vector2i(node.position - Vector2(w, BOSS_FOOT.y) / 2.0), Vector2i(int(w), int(BOSS_FOOT.y)))
		solid.fill_rect(r.intersection(Rect2i(Vector2i.ZERO, solid.get_size())), Color.BLACK)


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
# A ledge face (the drawn side of raised ground, never walkable itself) can
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
	var vp := get_viewport_rect().size
	var target_cam := player.position + lead
	if map_size.x < vp.x:
		target_cam.x = map_size.x / 2.0
	if map_size.y < vp.y:
		target_cam.y = map_size.y / 2.0
	camera.position = target_cam

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
			if not _exit_open(exit):
				_sealed(exit, input)
				return
			busy = true
			Game.go_to_map(exit["to"], exit["spawn"])
			return


## Boss Tower stairs (an exit with "needs": boss ids) open once you have
## beaten every one of them.
func _exit_open(exit: Dictionary) -> bool:
	return exit.get("needs", []).all(func(id): return Game.boss_wins(id) > 0)


## Walked into stairs that are still sealed: step back and say who's left.
func _sealed(exit: Dictionary, input: Vector2) -> void:
	var left: Array = exit["needs"].filter(func(id): return Game.boss_wins(id) == 0)
	var names := ", ".join(left.map(func(id): return Game.BOSSES[id]["name"]))
	var away := -input.normalized() if input.length() > 0.1 else Vector2.DOWN
	for i in 6:
		player.position = nearest_walkable(player.position + away * 6.0)
		if not exit["rect"].grow(4.0).has_point(player.position):
			break
	await say("The stairs are sealed by a strange power. Beat everyone on this floor first! (Still here: %s)" % names)


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
			if t.w < 0.0 and f.jump_height < minf(-t.w, FOLLOWER_CLIMB):
				# The leader hopped up a ledge here: jump too, and wait at the
				# bottom until high enough to follow.
				if not f.is_airborne():
					f.jump()
				serial = maxi(s - 1, _trail_start)
				break
			if t.w != 0.0:
				f.set_air(f.jump_height + t.w)
			if t.z > 0.0:
				f.jump()
		f.set_meta("trail", serial)
		var target := Vector2(_trail[serial - _trail_start].x, _trail[serial - _trail_start].y)
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


## Bosses standing on this map (Game.BOSSES), unless one is in your party.
## Talking to one starts its fight (see _boss_talk).
func _spawn_bosses() -> void:
	for id in Game.BOSSES:
		var b: Dictionary = Game.BOSSES[id]
		if b["map"] != map_id or _in_party(id):
			continue
		var node := _spawn_character(id)
		node.position = nearest_walkable(b["pos"])
		node.facing = FACINGS.get(b.get("face", "down"), Vector2.DOWN)
		npcs.append({"node": node, "id": id, "talk": "", "boss": id, "reach": BOSS_REACH, "face": node.facing})
	rebuild_collision()


## A boss: its lines, then "Fight!" or "Not now". Beaten bosses offer a
## rematch.
func _boss_talk(n: Dictionary) -> void:
	var id: String = n["boss"]
	var b: Dictionary = Game.BOSSES[id]
	var node: CharacterSprite = n["node"]
	busy = true
	node.facing = (player.position - node.position).normalized()
	var lines: Array = b["rematch"] if Game.boss_wins(id) > 0 else b["intro"]
	for i in lines.size() - 1:
		await say(DialogueData.fill(lines[i]), b["name"], node)
	var question: String = DialogueData.fill(lines.back())
	if Game.player["level"] < int(b.get("level", 1)):
		question += " (Suggested level: %d)" % int(b["level"])
	dialog.open(question, b["name"], node)
	_place_menu.call_deferred()
	var options := ["Rematch!" if Game.boss_wins(id) > 0 else "Fight!", "Not now"]
	var i := await menu.choose(options, "", true)
	dialog.close()
	if i == 0:
		Game.start_boss(id, player.position + Vector2(0, 16))
		return  # stays busy until the battle takes over
	node.facing = n["face"]
	await get_tree().process_frame
	await get_tree().process_frame
	busy = false


## Talks to an NPC using its lines in res://data/dialogue.json (see
## dialogue_data.gd): pages, then an optional choice that can recruit, open a
## shop or heal.
func _talk_to(n: Dictionary) -> void:
	if n.has("boss"):
		await _boss_talk(n)
		return
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
			await _shop(branch, speaker, node)
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
		await say("Your party is full, and so is your home base. Send someone home or swap them out first.")
		return false
	if randf() < info["recruit"]:
		var to := Game.add_member(Game.make_member("partner", n["id"]))
		npcs.erase(n)
		if to == "party":
			followers.append(node)
		else:
			node.queue_free()
		Game.save()
		await say("%s joined your party!" % info["name"] if to == "party" else
			"%s joined! Your party is full, so %s will wait for you at %s." % [info["name"], info["name"], Game.home_name()])
		return true
	await say("Hmm... I'm not sure yet. Ask me again?", speaker, node)
	return false


## A shop counter: Buy from the branch's "shop" list and Sell what you carry,
## until Done. Each stock entry: {item, count (a bundle, default 1), price
## (default: the item's price times the branch's "markup", default 1),
## thanks (said after buying)}. Shops buy anything back at half price.
func _shop(branch: Dictionary, speaker: String, node: Node2D) -> void:
	var stock: Array = branch.get("shop", []).filter(func(s): return not Game.goods(s.get("item", "")).is_empty())
	var markup := float(branch.get("markup", 1.0))
	menu.max_rows = 5
	menu.info_width = 190.0
	var question := "What can I do for you?"
	while true:
		dialog.open("%s You have %d coins." % [question, Game.player["coins"]], speaker)
		_place_menu.call_deferred()
		var c := await menu.choose(["Buy", "Sell", "Done"], "", true)
		dialog.close()
		if c == 0:
			await _shop_buy(stock, markup, speaker)
		elif c == 1:
			await _shop_sell(speaker, node)
		else:
			break
		question = "Anything else?"
	menu.max_rows = 0
	menu.info_width = 150.0


func _stock_price(s: Dictionary, markup: float) -> int:
	if s.has("price"):
		return int(s["price"])
	return int(ceil(Game.goods(s["item"])["price"] * int(s.get("count", 1)) * markup))


func _shop_buy(stock: Array, markup: float, speaker: String) -> void:
	var p: Dictionary = Game.player
	var at := 0
	var line := "What would you like?"
	while true:
		var labels := []
		var enabled := []
		var infos := []
		var icons := []
		for s in stock:
			var item: Dictionary = Game.goods(s["item"])
			var count := int(s.get("count", 1))
			var price := _stock_price(s, markup)
			labels.append("%s%s  %d" % [item["name"], " x%d" % count if count > 1 else "", price])
			enabled.append(p["coins"] >= price and Game.item_count(s["item"]) + count <= Game.max_count(s["item"]))
			var have := Game.item_count(s["item"])
			if Game.GEAR.has(s["item"]) and Game.equipped(item["slot"]) == s["item"]:
				have += 1
			infos.append("%s (You have %d.)" % [item["info"], have])
			icons.append(ItemsScreen.icon_of(s["item"]))
		labels.append("Done")
		enabled.append(true)
		infos.append("")
		icons.append(null)
		dialog.open("%s You have %d coins." % [line, p["coins"]], speaker)  # no tail through the list
		_place_menu.call_deferred()
		var i := await menu.choose(labels, "", true, enabled, infos, icons, at)
		dialog.close()
		if i < 0 or i >= stock.size():
			return
		at = i
		var s: Dictionary = stock[i]
		p["coins"] -= _stock_price(s, markup)
		Game.add_item(s["item"], int(s.get("count", 1)))
		Game.save()
		line = DialogueData.fill(s.get("thanks", "Thank you!" if not Game.GEAR.has(s["item"])
			else "Thank you! Put it on from Gear in the menu."))


func _shop_sell(speaker: String, node: Node2D) -> void:
	var p: Dictionary = Game.player
	var at := 0
	var line := "What are you selling? I pay half price."
	while true:
		var ids := Game.sellable()
		if ids.is_empty():
			await say("You don't have anything to sell.", speaker, node)
			return
		var labels := []
		var infos := []
		var icons := []
		for id in ids:
			labels.append("%s x%d  %d" % [Game.goods(id)["name"], Game.item_count(id), Game.sell_price(id)])
			infos.append("Sell one for %d coins." % Game.sell_price(id))
			icons.append(ItemsScreen.icon_of(id))
		labels.append("Done")
		infos.append("")
		icons.append(null)
		dialog.open("%s You have %d coins." % [line, p["coins"]], speaker)  # no tail through the list
		_place_menu.call_deferred()
		var i := await menu.choose(labels, "", true, [], infos, icons, mini(at, ids.size() - 1))
		dialog.close()
		if i < 0 or i >= ids.size():
			return
		at = i
		Game.add_item(ids[i], -1)
		p["coins"] += Game.sell_price(ids[i])
		Game.save()
		line = "Sold %s for %d coins!" % [Game.with_article(Game.goods(ids[i])["name"]), Game.sell_price(ids[i])]


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
		var options := ["Items", "Gear", "Party", "Go %s" % other, "Save", "Quit", "Close"]
		var i := await pause_screen.menu.choose(options, "", true)
		if i == 1:
			pause_screen.close()
			await _gear_menu()
			continue
		if i > 1:
			i -= 1  # the options below Gear keep their old numbers
		match i:
			0:
				pause_screen.close()
				await _items_menu()
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
				await _save_online()
			4:
				Game.save()
				Cloud.upload()
				Net.leave()
				get_tree().change_scene_to_file(Game.TITLE_SCENE)
				return
		break
	pause_screen.close()
	await get_tree().process_frame
	busy = false


## After saving: online too if this save is linked, else offers to link it
## (a password for your username, so you can log in on any device).
func _save_online() -> void:
	if Cloud.linked():
		var ok: bool = await Cloud.upload()
		await say("Game saved. It's online too: log in as %s on any device." % Cloud.account_name() if ok
			else "Game saved in this browser. Couldn't reach the server, so it goes online later.")
		return
	dialog.open("Game saved in this browser. Save online too, so you can log in and play on any device?")
	var c := await pause_screen.menu.choose(["Save online", "Not now"], "", true)
	dialog.close()
	if c != 0:
		return
	if save_prompt == null:
		save_prompt = TextPrompt.new()
		$HUD.add_child(save_prompt)
	save_prompt.position = ((get_viewport_rect().size - Vector2(160, 40)) / 2.0).round()
	while true:
		var password := await save_prompt.ask("Pick a password", "", 64,
			"For logging in as %s." % Game.username(), true)
		if password == "":
			return
		if password.length() < 4:
			await say(Cloud.error_text("password"))
			continue
		var again := await save_prompt.ask("Type it again", "", 64, "Enter: OK   Esc: cancel", true)
		if again == "":
			return
		if again != password:
			await say("Those didn't match. Try again.")
			continue
		var err: String = await Cloud.register(password)
		if err == "taken":
			# Online names are one per player: pick another and try again.
			var u := Game.clean_username(await save_prompt.ask("Pick another username",
				Game.username(), 16, "Someone already saved online as %s." % Game.username()))
			if u == "":
				return
			Game.player["username"] = u
			Game.save()
			err = await Cloud.register(password)
		if err != "":
			await say(Cloud.error_text(err))
			return
		await say("Saved online! Log in as %s with your password on any device." % Cloud.account_name())
		return


## The Items page: pick an item, then who uses it (if it could be more than
## one of you). Battle-only items are listed but greyed out.
func _items_menu() -> void:
	var at := 0
	while true:
		var ids := Game.owned_items()
		if ids.is_empty():
			await say("You aren't carrying any items. The shops in town sell them.")
			break
		var usable := ids.map(func(id): return not Game.ITEMS[id].get("battle", false))
		items_screen.set_footer(("A: Use   B: Back" if TouchControls.active else "Z: Use   X: Back")
			+ "     Coins: %d" % Game.player["coins"])
		var i := await items_screen.choose_item(ids, usable, at)
		if i < 0:
			break
		at = i
		await _use_item(ids[i])
	items_screen.close()


## The Gear page: everything you carry or wear; picking one puts it on (or
## takes it off, if you're wearing it).
func _gear_menu() -> void:
	var at := 0
	while true:
		var ids := Game.owned_gear()
		if ids.is_empty():
			await say("You don't have any pants or badges. The Badge Shop in Castle Town sells them.")
			break
		var worn := ids.map(func(id): return Game.equipped(Game.GEAR[id]["slot"]) == id)
		var labels := []
		for k in ids.size():
			labels.append("On" if worn[k] else "x%d" % Game.item_count(ids[k]))
		var bonus := Game.gear_bonus_text()
		items_screen.set_tab("GEAR")
		# Your gear's total once you wear some (there's no room for both).
		items_screen.set_footer("Wearing: " + bonus if bonus != ""
			else ("A: Wear  B: Back" if TouchControls.active else "Z: Wear  X: Back"))
		var i := await items_screen.choose_item(ids, [], at, labels)
		if i < 0:
			break
		at = i
		var g: Dictionary = Game.GEAR[ids[i]]
		if worn[i]:
			Game.unequip(g["slot"])
		else:
			Game.equip(ids[i])
		Game.save()
		_update_hud()
	items_screen.close()
	items_screen.set_tab("ITEMS")


## Uses an item outside battle (HP and SP items).
func _use_item(id: String) -> void:
	var item: Dictionary = Game.ITEMS[id]
	var p: Dictionary = Game.player
	var you := Game.character_name()
	if item.has("sp"):
		if p["sp"] >= p["max_sp"]:
			await say("Your SP is already full.")
			return
		var before: int = p["sp"]
		p["sp"] = mini(p["max_sp"], p["sp"] + int(item["sp"]))
		Game.add_item(id, -1)
		Game.save()
		await say("%s had %s. +%d SP" % [you, Game.with_article(item["name"]), p["sp"] - before])
		return
	if not item.has("hp"):
		return
	# You and your partners: whoever isn't at full HP can have it.
	var who: Array = [p]
	who.append_array(p["party"])
	var names: Array = [you]
	for m in p["party"]:
		names.append(m["name"])
	var t := 0
	if who.size() > 1:
		var labels := []
		var enabled := []
		for k in who.size():
			labels.append("%s %d/%d" % [names[k], who[k]["hp"], who[k]["max_hp"]])
			enabled.append(who[k]["hp"] < who[k]["max_hp"])
		t = await items_screen.choose_target(labels, enabled)
		if t < 0:
			return
	var m: Dictionary = who[t]
	if m["hp"] >= m["max_hp"]:
		await say("Your HP is already full." if t == 0 else "%s's HP is already full." % names[t])
		return
	var before: int = m["hp"]
	m["hp"] = mini(m["max_hp"], m["hp"] + int(item["hp"]))
	Game.add_item(id, -1)
	Game.save()
	await say("%s ate %s. +%d HP" % [names[t], Game.with_article(item["name"]), m["hp"] - before])


## The Party page: send someone home, or (at your home base) take someone
## who is waiting there along.
func _party_menu() -> void:
	var at_home: bool = map_id == Game.HOME_MAP[Game.player["side"]]
	while true:
		var party: Array = Game.player["party"]
		var waiting: Array = Game.bench_for_side()
		party_screen.open(Game.player, Game.character_name())
		if party.is_empty() and (waiting.is_empty() or not at_home):
			await say(("Nobody is with you yet. Good players can ask partners in town; evil players can ask enemies in battle."
				if waiting.is_empty() else "%d waiting for you at %s. Go there to take them along." % [waiting.size(), Game.home_name()]))
			break
		var names: Array = []
		for m in party:
			names.append(m["name"])
		if at_home and not waiting.is_empty():
			names.append("Waiting here (%d)" % waiting.size())
		var title := "Send home?" if waiting.is_empty() or at_home else "%d wait at home" % waiting.size()
		var i := await party_screen.menu.choose(names, title, true)
		if i < 0:
			break
		if i >= party.size():
			await _bench_menu(waiting)
			continue
		var c := await party_screen.menu.choose(["Send home", "Keep"], party[i]["name"], true)
		if c == 0:
			var who: String = party[i]["name"]
			Game.send_home(i)
			var f: CharacterSprite = followers[i]
			followers.remove_at(i)
			f.queue_free()
			Game.save()
			if not at_home:
				await say("%s heads back to %s to wait for you." % [who, Game.home_name()])
	party_screen.close()


## At your home base: pick someone waiting there to join you.
func _bench_menu(waiting: Array) -> void:
	var bench: Array = Game.bench()
	var names: Array = waiting.map(func(j): return "%s  HP %d" % [bench[j]["name"], bench[j]["max_hp"]])
	var k := await party_screen.menu.choose(names, "Take along?", true)
	if k < 0:
		return
	var m: Dictionary = bench[waiting[k]]
	match Game.take_from_bench(waiting[k]):
		"full":
			await say("Your party is full. Send someone home first, then take %s along." % m["name"])
		"boss":
			await say("%s won't share a party with another boss!" % m["name"])
		_:
			var f := _spawn_character(m["id"])
			f.position = player.position
			followers.append(f)
			Game.save()
			await say("%s joined your party!" % m["name"])


## Towns show this week's good vs evil count of PvP wins (top right).
func _show_weekly_score() -> void:
	var score: Dictionary = await Cloud.weekly_score()
	if score.is_empty() or not is_inside_tree():
		return
	score_box = PanelContainer.new()
	score_box.theme_type_variation = &"NavyPanel"
	score_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.theme_type_variation = &"LightLabel"
	var days := ceili((float(score["ends_at"]) / 1000.0 - Time.get_unix_time_from_system()) / 86400.0)
	l.text = "Good %d : %d Evil" % [int(score["good"]), int(score["evil"])]
	l.tooltip_text = "This week's PvP wins for each side. A new week starts in %d day%s." % [days, "" if days == 1 else "s"]
	score_box.add_child(l)
	$HUD.add_child(score_box)
	$HUD.move_child(score_box, 0)  # under menus and dialogue
	_update_hud()


func _show_area_name() -> void:
	area_name.show_name(map_info["name"])


func _on_viewport_resized() -> void:
	_fit_camera()
	_update_hud()


func _update_hud() -> void:
	var safe := Game.get_safe_rect()
	var vp := get_viewport_rect().size
	var p: Dictionary = Game.player
	status.refresh(p, Game.character_name())
	status.position = Vector2(safe.position.x + 4.0, safe.position.y + 3.0)

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
	hint_box.position.x = roundf(safe.position.x + (safe.size.x - hint_box.size.x) / 2.0)
	hint_box.position.y = safe.end.y - hint_box.size.y - 2.0

	area_name.position.x = roundf(safe.position.x + (safe.size.x - area_name.size.x) / 2.0)
	area_name.position.y = safe.position.y + 30.0

	if score_box != null:
		score_box.reset_size()
		score_box.position = Vector2(safe.end.x - score_box.size.x - 4.0, safe.position.y + 3.0)
		if score_box.position.x < status.position.x + status.size.x + 2.0:
			# No room beside the status bar: just under its right end.
			score_box.position = Vector2(status.position.x + status.size.x - score_box.size.x,
				status.position.y + status.size.y + 1.0).round()

	# Keep overworld menu anchored to top-right safe edge
	menu.position = Vector2(safe.end.x - menu.size.x - 4.0, safe.position.y + 24.0)

	# A "!" bubble pops up over whoever you can talk to.
	talk_bubble.visible = npc != null
	if npc != null:
		var node: CharacterSprite = npc["node"]
		var head := node.get_global_transform_with_canvas().origin - Vector2(0, node.height() + 6)
		var bob := roundf(absf(sin(Time.get_ticks_msec() / 160.0)) * 2.0)
		talk_bubble.position = (head - Vector2(talk_bubble.size.x / 2.0, talk_bubble.size.y + bob)).round()

