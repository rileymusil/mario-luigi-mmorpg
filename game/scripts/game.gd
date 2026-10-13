extends Node
## Global game state (autoloaded as "Game"): data tables, the player's save,
## and moving between the title, the world maps and battles.

const TITLE_SCENE := "res://scenes/title.tscn"
const WORLD_SCENE := "res://scenes/world.tscn"
const BATTLE_SCENE := "res://scenes/battle.tscn"
const SAVE_PATH := "user://save.json"
const MAX_LEVEL := 50
const MAX_PARTY := 2

## Sprite sheets live in res://assets/characters/<id>.png: 3 rows (down,
## right, up) of `frames` cells. Built by tools/slice_sprites.py.
const CHARACTERS := {
	"mario": {"name": "Mario", "side": "good", "frames": 8, "hp": 20, "sp": 10, "pow": 5, "def": 2,
		"special": "fire_jump"},
	"luigi": {"name": "Luigi", "side": "good", "frames": 8, "hp": 22, "sp": 10, "pow": 4, "def": 3,
		"special": "thunderhand"},
	"peach": {"name": "Princess Peach", "side": "good", "frames": 8, "hp": 18, "sp": 14, "pow": 4, "def": 2,
		"special": "peach_heart"},
	"waluigi": {"name": "Waluigi", "side": "good", "frames": 5, "hp": 21, "sp": 10, "pow": 5, "def": 2,
		"special": "wicked_whirl"},
	"rosalina": {"name": "Rosalina", "side": "good", "frames": 7, "hp": 18, "sp": 14, "pow": 4, "def": 2,
		"special": "star_spin"},
	"toadette": {"name": "Toadette", "side": "good", "frames": 10, "hp": 17, "sp": 12, "pow": 4, "def": 2,
		"special": "pickaxe_pound"},
	"bowser": {"name": "Bowser", "side": "evil", "frames": 5, "hp": 26, "sp": 10, "pow": 6, "def": 3,
		"special": "fire_breath"},
	"bowser_jr": {"name": "Bowser Jr.", "side": "evil", "frames": 1, "hp": 22, "sp": 12, "pow": 5, "def": 2,
		"special": "goop_paint"},
	"shadow_mario": {"name": "Shadow Mario", "side": "evil", "frames": 1, "hp": 20, "sp": 12, "pow": 5, "def": 2,
		"special": "shadow_drain"},
}

const SPECIALS := {
	"fire_jump": {"name": "Fire Jump", "sp": 4, "info": "Jump that burns the enemy for 3 turns."},
	"thunderhand": {"name": "Thunderhand", "sp": 4, "info": "Electric punch. Great timing stuns."},
	"peach_heart": {"name": "Peach's Heart", "sp": 5, "info": "Heals the whole party."},
	"fire_breath": {"name": "Fire Breath", "sp": 5, "info": "Burns every enemy at once."},
	"wicked_whirl": {"name": "Wicked Whirl", "sp": 5, "info": "Hits every enemy. Excellent stuns all."},
	"star_spin": {"name": "Star Spin", "sp": 5, "info": "Hits one enemy, heals the party a bit."},
	"pickaxe_pound": {"name": "Pickaxe Pound", "sp": 4, "info": "Heavy hit that ignores defense."},
	"goop_paint": {"name": "Goop Paint", "sp": 4, "info": "Goopy hit. Great timing stuns."},
	"shadow_drain": {"name": "Shadow Drain", "sp": 5, "info": "Steals HP from an enemy."},
}

## Partners (good side) and recruitable enemies (evil side). `recruit` is the
## base chance that asking works; it goes up as the enemy gets weaker.
const PARTNERS := {
	"toad": {"name": "Toad", "frames": 8, "hp": 14, "pow": 3, "def": 1, "recruit": 0.5},
	"pianta": {"name": "Pianta", "frames": 3, "hp": 20, "pow": 4, "def": 2, "recruit": 0.35},
}

const ENEMIES := {
	"goomba": {"name": "Goomba", "frames": 8, "hp": 10, "pow": 4, "def": 0, "xp": 4, "coins": 3,
		"recruit": 0.4},
	"beanie": {"name": "Beanie", "frames": 8, "hp": 14, "pow": 5, "def": 1, "xp": 6, "coins": 5,
		"recruit": 0.3},
	"galoomba": {"name": "Galoomba", "frames": 8, "hp": 9, "pow": 3, "def": 0, "xp": 3, "coins": 2,
		"recruit": 0.45},
	"koopa": {"name": "Koopa Troopa", "frames": 5, "hp": 14, "pow": 4, "def": 2, "xp": 6, "coins": 4,
		"recruit": 0.35},
	"shy_guy": {"name": "Shy Guy", "frames": 6, "hp": 12, "pow": 5, "def": 1, "xp": 5, "coins": 4,
		"recruit": 0.35},
	"buzzy_beetle": {"name": "Buzzy Beetle", "frames": 8, "hp": 12, "pow": 4, "def": 4, "xp": 7, "coins": 5,
		"recruit": 0.3},
	"dry_bones": {"name": "Dry Bones", "frames": 5, "hp": 16, "pow": 5, "def": 2, "xp": 10, "coins": 7,
		"recruit": 0.25},
}

## Maps: art and walk mask in res://assets/maps/ (built by tools/make_maps.py).
## exits: walking into `rect` moves you to `to` at that map's `spawn` point.
const MAPS := {
	"castle_town": {
		"name": "Beanbean Castle Town", "safe": true,
		"spawns": {"start": Vector2(320, 560), "east_gate": Vector2(1350, 409), "west_gate": Vector2(70, 409)},
		"exits": [
			{"rect": Rect2(1430, 380, 22, 60), "to": "outskirts", "spawn": "south_path"},
			{"rect": Rect2(0, 380, 22, 60), "to": "outskirts", "spawn": "south_path"},
		],
		"enemies": [],
		"npcs": [{"id": "toad", "pos": Vector2(435, 311)}, {"id": "pianta", "pos": Vector2(560, 330)}],
	},
	"outskirts": {
		"name": "Beanbean Outskirts", "safe": false,
		"spawns": {"south_path": Vector2(800, 615), "east_bridge": Vector2(1420, 65)},
		"exits": [
			{"rect": Rect2(760, 630, 90, 7), "to": "castle_town", "spawn": "east_gate"},
			{"rect": Rect2(1455, 30, 10, 70), "to": "bowser_castle", "spawn": "bridge"},
		],
		"enemies": [
			{"type": "goomba", "pos": Vector2(628, 178)}, {"type": "goomba", "pos": Vector2(607, 345)},
			{"type": "beanie", "pos": Vector2(1046, 178)}, {"type": "goomba", "pos": Vector2(816, 492)},
			{"type": "beanie", "pos": Vector2(1004, 544)}, {"type": "beanie", "pos": Vector2(1318, 345)},
			{"type": "koopa", "pos": Vector2(700, 222)}, {"type": "shy_guy", "pos": Vector2(883, 300)},
			{"type": "buzzy_beetle", "pos": Vector2(1150, 250)}, {"type": "galoomba", "pos": Vector2(678, 545)},
			{"type": "dry_bones", "pos": Vector2(1250, 130)}, {"type": "koopa", "pos": Vector2(1228, 457)},
			{"type": "shy_guy", "pos": Vector2(1100, 600)}, {"type": "galoomba", "pos": Vector2(548, 447)},
		],
		"npcs": [],
	},
	"bowser_castle": {
		"name": "Bowser's Castle", "safe": true,
		"spawns": {"start": Vector2(205, 250), "bridge": Vector2(205, 580)},
		"exits": [{"rect": Rect2(170, 605, 70, 10), "to": "outskirts", "spawn": "east_bridge"}],
		"enemies": [],
		"npcs": [],
	},
}

const HOME_MAP := {"good": "castle_town", "evil": "bowser_castle"}

var player := {}          # the saved player, see new_player()
var pending_battle := {}  # set by the world right before a battle starts
var defeated := {}        # "map:index" -> time it was beaten (enemies respawn)
const RESPAWN_SECONDS := 45.0


func _ready() -> void:
	_add_action("move_left", [KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT])
	_add_action("move_right", [KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT])
	_add_action("move_up", [KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP])
	_add_action("move_down", [KEY_DOWN, KEY_S], [JOY_BUTTON_DPAD_DOWN])
	_add_action("action", [KEY_Z, KEY_J, KEY_SPACE], [JOY_BUTTON_A])  # jump, confirm, timed hits
	_add_action("talk", [KEY_X, KEY_K], [JOY_BUTTON_B])  # talk / ask, cancel in menus
	_add_action("menu", [KEY_ENTER, KEY_ESCAPE], [JOY_BUTTON_START])


func _add_action(action: String, keys: Array, buttons: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
	for button in buttons:
		var jev := InputEventJoypadButton.new()
		jev.button_index = button
		InputMap.action_add_event(action, jev)


# --- Player ---------------------------------------------------------------

func new_player(character_id: String, username := "") -> void:
	var c: Dictionary = CHARACTERS[character_id]
	player = {
		"username": clean_username(username), "character": character_id, "side": c["side"], "level": 1, "xp": 0, "coins": 20,
		"max_hp": c["hp"], "hp": c["hp"], "max_sp": c["sp"], "sp": c["sp"], "pow": c["pow"], "def": c["def"],
		"mushrooms": 3, "party": [], "map": HOME_MAP[c["side"]], "spawn": "start", "position": null,
		"wins": 0,
	}
	save()


func character_name() -> String:
	return CHARACTERS[player["character"]]["name"]


## The name other players see over your head. Falls back to the character's
## name for saves made before usernames existed.
func username() -> String:
	var u: String = player.get("username", "")
	return u if u != "" else character_name()


## Same rule as the server: letters, numbers, spaces and _ . ' - , max 16.
func clean_username(text: String) -> String:
	var re := RegEx.create_from_string("[^\\p{L}\\p{N} _.'-]")
	return re.sub(text, "", true).strip_edges().left(16)


func xp_to_next(level: int) -> int:
	return int(round(8.0 * pow(level, 1.5)))


## Adds XP; returns how many levels were gained.
func gain_xp(amount: int) -> int:
	var gained := 0
	player["xp"] += amount
	while player["level"] < MAX_LEVEL and player["xp"] >= xp_to_next(player["level"]):
		player["xp"] -= xp_to_next(player["level"])
		player["level"] += 1
		player["max_hp"] += 3
		player["max_sp"] += 2
		player["pow"] += 1
		if player["level"] % 2 == 0:
			player["def"] += 1
		player["hp"] = player["max_hp"]
		player["sp"] = player["max_sp"]
		for member in player["party"]:
			member["max_hp"] += 2
			member["hp"] = member["max_hp"]
			member["pow"] += 1
		gained += 1
	return gained


## Builds a party member from a partner or enemy id.
func make_member(kind: String, id: String) -> Dictionary:
	var src: Dictionary = PARTNERS[id] if kind == "partner" else ENEMIES[id]
	return {"kind": kind, "id": id, "name": src["name"], "max_hp": src["hp"], "hp": src["hp"],
		"pow": src["pow"], "def": src["def"]}


func can_recruit() -> bool:
	return player["party"].size() < MAX_PARTY


func switch_side() -> void:
	# Prototype rule: switching sides swaps to the other side's first character
	# and sends you to that side's home. Levels, coins and items are kept.
	var other := "evil" if player["side"] == "good" else "good"
	for id in CHARACTERS:
		if CHARACTERS[id]["side"] == other:
			player["character"] = id
			break
	player["side"] = other
	player["party"] = []
	go_to_map(HOME_MAP[other], "start")


# --- Moving between scenes ---------------------------------------------------

func go_to_map(map_id: String, spawn: String) -> void:
	player["map"] = map_id
	player["spawn"] = spawn
	player["position"] = null
	save()
	get_tree().call_deferred("change_scene_to_file", WORLD_SCENE)


func start_battle(enemies: Array, defeated_key: String, overworld_position: Vector2) -> void:
	player["position"] = [overworld_position.x, overworld_position.y]
	pending_battle = {"enemies": enemies, "key": defeated_key}
	get_tree().call_deferred("change_scene_to_file", BATTLE_SCENE)


## result: "won", "lost" or "fled".
func end_battle(result: String) -> void:
	if result == "won":
		defeated[pending_battle["key"]] = Time.get_ticks_msec() / 1000.0
	if result == "lost":
		# Back to your home town with a few coins lost; items and levels stay.
		player["coins"] = int(player["coins"] * 0.9)
		player["hp"] = player["max_hp"]
		player["sp"] = player["max_sp"]
		for member in player["party"]:
			member["hp"] = member["max_hp"]
		pending_battle = {}
		go_to_map(HOME_MAP[player["side"]], "start")
		return
	pending_battle = {}
	save()
	get_tree().call_deferred("change_scene_to_file", WORLD_SCENE)


func is_defeated(key: String) -> bool:
	if not defeated.has(key):
		return false
	if Time.get_ticks_msec() / 1000.0 - defeated[key] > RESPAWN_SECONDS:
		defeated.erase(key)
		return false
	return true


# --- Saving (browser storage on the web build) -------------------------------

func save() -> void:
	if player.is_empty():
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(player))


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_save() -> bool:
	if not has_save():
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY or not CHARACTERS.has(data.get("character", "")):
		return false
	# JSON numbers come back as floats; keep whole-number stats as ints.
	for key in ["level", "xp", "coins", "max_hp", "hp", "max_sp", "sp", "pow", "def", "mushrooms", "wins"]:
		data[key] = int(data.get(key, 0))
	for member in data["party"]:
		for key in ["max_hp", "hp", "pow", "def"]:
			member[key] = int(member[key])
	player = data
	return true


func continue_game() -> void:
	get_tree().call_deferred("change_scene_to_file", WORLD_SCENE)
