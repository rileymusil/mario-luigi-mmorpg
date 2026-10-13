extends Node
## Global game state (autoloaded as "Game"): data tables, the player's save,
## and moving between the title, the world maps and battles.

const TITLE_SCENE := "res://scenes/title.tscn"
const WORLD_SCENE := "res://scenes/world.tscn"
const BATTLE_SCENE := "res://scenes/battle.tscn"
const PVP_SCENE := "res://scenes/pvp_battle.tscn"
const COOP_SCENE := "res://scenes/coop_battle.tscn"        # you started it, your partner joins
const COOP_GUEST_SCENE := "res://scenes/coop_guest.tscn"   # your partner's battle, seen from your side
const SAVE_PATH := "user://save.json"
const MAX_LEVEL := 50
const MAX_PARTY := 2

## Sprite sheets live in res://assets/characters/<id>.png: 3 rows (down,
## right, up) of `frames` cells. Built by tools/slice_sprites.py.
## Each side lists the design roster first (this is the character select
## order), then the extra Superstar Saga-style customs.
const CHARACTERS := {
	"mario": {"name": "Mario", "side": "good", "frames": 8, "hp": 20, "sp": 10, "pow": 5, "def": 2,
		"special": "fire_jump"},
	"luigi": {"name": "Luigi", "side": "good", "frames": 8, "hp": 22, "sp": 10, "pow": 4, "def": 3,
		"special": "thunderhand"},
	"peach": {"name": "Princess Peach", "side": "good", "frames": 8, "hp": 18, "sp": 14, "pow": 4, "def": 2,
		"special": "peach_heart"},
	"egadd": {"name": "Professor E. Gadd", "side": "good", "frames": 8, "hp": 18, "sp": 12, "pow": 4, "def": 2,
		"special": "poltergust_pull"},
	"vivian": {"name": "Vivian", "side": "good", "frames": 2, "hp": 19, "sp": 12, "pow": 5, "def": 2,
		"special": "shade_veil"},
	"waluigi": {"name": "Waluigi", "side": "good", "frames": 5, "hp": 21, "sp": 10, "pow": 5, "def": 2,
		"special": "wicked_whirl"},
	"rosalina": {"name": "Rosalina", "side": "good", "frames": 7, "hp": 18, "sp": 14, "pow": 4, "def": 2,
		"special": "star_spin"},
	"toadette": {"name": "Toadette", "side": "good", "frames": 10, "hp": 17, "sp": 12, "pow": 4, "def": 2,
		"special": "pickaxe_pound"},
	"bowser": {"name": "Bowser", "side": "evil", "frames": 5, "hp": 26, "sp": 10, "pow": 6, "def": 3,
		"special": "fire_breath"},
	"rookie_bowser": {"name": "Rookie Bowser", "side": "evil", "frames": 8, "hp": 24, "sp": 10, "pow": 6, "def": 3,
		"special": "rookie_rush"},
	"dimentio": {"name": "Dimentio", "side": "evil", "frames": 2, "hp": 19, "sp": 14, "pow": 5, "def": 2,
		"special": "magic_cube"},
	"grodus": {"name": "Grodus", "side": "evil", "frames": 5, "hp": 21, "sp": 14, "pow": 5, "def": 2,
		"special": "grodus_bolt"},
	"mimi": {"name": "Mimi", "side": "evil", "frames": 4, "hp": 20, "sp": 12, "pow": 5, "def": 2,
		"special": "mimic"},
	"koopa_bros": {"name": "Koopa Bros.", "side": "evil", "frames": 5, "hp": 22, "sp": 12, "pow": 5, "def": 3,
		"special": "bros_tower"},
	"bowser_jr": {"name": "Bowser Jr.", "side": "evil", "frames": 1, "hp": 22, "sp": 12, "pow": 5, "def": 2,
		"special": "goop_paint"},
	"shadow_mario": {"name": "Shadow Mario", "side": "evil", "frames": 1, "hp": 20, "sp": 12, "pow": 5, "def": 2,
		"special": "shadow_drain"},
}

## Signature moves (battle.gd _special), each a timed press.
const SPECIALS := {
	"fire_jump": {"name": "Fire Jump", "sp": 4, "info": "Jump that burns the enemy for 3 turns."},
	"thunderhand": {"name": "Thunderhand", "sp": 4, "info": "Electric punch. Great timing stuns."},
	"peach_heart": {"name": "Peach's Heart", "sp": 5, "info": "Heals the whole party. Good timing heals more."},
	"poltergust_pull": {"name": "Poltergust Pull", "sp": 5,
		"info": "Sucks HP out of an enemy. Excellent also steals its item."},
	"shade_veil": {"name": "Shade Veil", "sp": 5,
		"info": "Hide in the shadows, dodge the next attack, then hit back with fire."},
	"fire_breath": {"name": "Fire Breath", "sp": 5, "info": "Fire hits every enemy at once."},
	"rookie_rush": {"name": "Rookie Rush", "sp": 5,
		"info": "Up to 3 shell bashes; Z as each hits. Excellents in a row hit harder."},
	"magic_cube": {"name": "Magic Cube", "sp": 6,
		"info": "Traps an enemy in a box that explodes on its next turn."},
	"grodus_bolt": {"name": "Grodus Bolt", "sp": 6, "info": "Lightning hits every enemy and lowers their DEF."},
	"mimic": {"name": "Mimic", "sp": 4, "info": "Copies the last move the target used."},
	"bros_tower": {"name": "Bros. Tower", "sp": 6,
		"info": "Z as each brother lands on the stack, then the tower spins into the enemy."},
	"wicked_whirl": {"name": "Wicked Whirl", "sp": 5, "info": "Hits every enemy. Excellent stuns all."},
	"star_spin": {"name": "Star Spin", "sp": 5, "info": "Hits one enemy, heals the party a bit."},
	"pickaxe_pound": {"name": "Pickaxe Pound", "sp": 4, "info": "Heavy hit that ignores defense."},
	"goop_paint": {"name": "Goop Paint", "sp": 4, "info": "Goopy hit. Great timing stuns."},
	"shadow_drain": {"name": "Shadow Drain", "sp": 5, "info": "Steals HP from an enemy."},
}

## What partners and recruited enemies do on their own turn (battle.gd
## _partner_move). Enemies are known for theirs, which is what Mimi copies.
## kind: "tackle" (Z in the gold zone, then run in), "stomp" (jump, Z as you
## land), "throw" (Z in the gold zone, something flies at the enemy), "blast"
## (hits every enemy) or "multi" (up to `hits` hits, a press each; a miss
## stops it). Optional: bonus (added to POW), ignore_def, color (of a throw),
## and extras an Excellent adds: stun, burn (turns), def_down (DEF lost),
## heal (party HP), pierce (the next enemy is hit too).
const MOVES := {
	"mushroom_toss": {"name": "Mushroom Toss", "kind": "throw", "color": Color(0.95, 0.25, 0.2), "heal": 3,
		"info": "Throws a Mushroom. Excellent also heals the party 3 HP."},
	"pianta_slam": {"name": "Pianta Slam", "kind": "tackle", "bonus": 1, "info": "A heavy belly slam."},
	"bomb": {"name": "Bomb", "kind": "blast", "info": "Explodes and hits every enemy."},
	"smack": {"name": "Smack", "kind": "multi", "hits": 3, "info": "Up to 3 slaps, Z in the gold zone for each."},
	"bob_ombast": {"name": "Bob-ombast", "kind": "blast", "bonus": 1, "burn": 2,
		"info": "Huge blast on every enemy. Excellent sets them on fire."},
	"headbonk": {"name": "Headbonk", "kind": "stomp", "info": "Jump on the enemy. Z as you land for a 2nd hit."},
	"shell_toss": {"name": "Shell Toss", "kind": "throw", "color": Color(0.3, 0.75, 0.25), "pierce": true,
		"info": "A shell slides into an enemy. Excellent hits the next one too."},
	"gulp": {"name": "Gulp", "kind": "tackle", "ignore_def": true,
		"info": "Gulps the enemy down and spits it out. Ignores DEF."},
	"rose_toss": {"name": "Rose Toss", "kind": "throw", "color": Color(1.0, 0.45, 0.6), "def_down": 2,
		"info": "Tosses a rose. Excellent charms the enemy: DEF down."},
	"ground_pound": {"name": "Ground Pound", "kind": "stomp", "stun": true,
		"info": "Flutter up and pound. Z as you land; Excellent stuns."},
	"rolling_bump": {"name": "Rolling Bump", "kind": "tackle", "info": "Rolls into the enemy."},
	"bean_bash": {"name": "Bean Bash", "kind": "tackle", "stun": true,
		"info": "Pops out of the ground. Excellent stuns."},
	"shy_spin": {"name": "Shy Spin", "kind": "multi", "hits": 2, "info": "Up to 2 spinning hits."},
	"shell_spin": {"name": "Shell Spin", "kind": "tackle", "def_down": 1,
		"info": "Hard shell spin. Excellent lowers the enemy's DEF."},
	"bone_toss": {"name": "Bone Toss", "kind": "throw", "color": Color(0.95, 0.93, 0.85), "bonus": 1,
		"info": "Throws a bone."},
}

## Partners (good side) and recruitable enemies (evil side). `recruit` is the
## base chance that asking works; it goes up as the enemy gets weaker, and
## stronger enemies start lower. `move` is their turn in battle (MOVES),
## `line` what a partner says when you talk to them.
const PARTNERS := {
	"toad": {"name": "Toad", "frames": 8, "hp": 14, "pow": 3, "def": 1, "recruit": 0.5, "move": "mushroom_toss",
		"line": "Going out to the Outskirts? It's dangerous out there..."},
	"pianta": {"name": "Pianta", "frames": 3, "hp": 20, "pow": 4, "def": 2, "recruit": 0.35, "move": "pianta_slam",
		"line": "Whoa, a traveler! Need some muscle out there?"},
	"bombette": {"name": "Bombette", "frames": 4, "hp": 14, "pow": 4, "def": 1, "recruit": 0.45, "move": "bomb",
		"line": "Hi, I'm Bombette! I get a little explosive once I get going!"},
	"bow": {"name": "Bow", "frames": 4, "hp": 14, "pow": 3, "def": 1, "recruit": 0.4, "move": "smack",
		"line": "Hmph. I am Lady Bow. I suppose I could slap a few Goombas for you."},
	"bobbery": {"name": "Bobbery", "frames": 3, "hp": 18, "pow": 5, "def": 1, "recruit": 0.3, "move": "bob_ombast",
		"line": "Ahoy! Admiral Bobbery here. These old fuses still pack a blast!"},
	"goombella": {"name": "Goombella", "frames": 5, "hp": 14, "pow": 3, "def": 1, "recruit": 0.5, "move": "headbonk",
		"line": "Hi! I'm Goombella, archaeology student. Want some company?"},
	"koops": {"name": "Koops", "frames": 9, "hp": 15, "pow": 4, "def": 2, "recruit": 0.45, "move": "shell_toss",
		"line": "H-hi, I'm Koops. I want to be brave... Maybe you could help?"},
	"yoshi_kid": {"name": "Yoshi Kid", "frames": 9, "hp": 13, "pow": 3, "def": 1, "recruit": 0.5, "move": "gulp",
		"line": "Yo! I'm the toughest Yoshi around. You need me, right?"},
	"peasley": {"name": "Prince Peasley", "frames": 8, "hp": 18, "pow": 5, "def": 2, "recruit": 0.3,
		"move": "rose_toss", "line": "Greetings! I am Prince Peasley of the Beanbean Kingdom. Shall we ride out?"},
	"yoshi": {"name": "Yoshi", "frames": 8, "hp": 18, "pow": 4, "def": 1, "recruit": 0.4, "move": "ground_pound",
		"line": "Yoshi! Yoshi! (He looks ready for an adventure.)"},
}

const ENEMIES := {
	"goomba": {"name": "Goomba", "frames": 8, "hp": 10, "pow": 4, "def": 0, "xp": 4, "coins": 3,
		"recruit": 0.4, "move": "headbonk"},
	"beanie": {"name": "Beanie", "frames": 8, "hp": 14, "pow": 5, "def": 1, "xp": 6, "coins": 5,
		"recruit": 0.3, "move": "bean_bash"},
	"galoomba": {"name": "Galoomba", "frames": 8, "hp": 9, "pow": 3, "def": 0, "xp": 3, "coins": 2,
		"recruit": 0.45, "move": "rolling_bump"},
	"koopa": {"name": "Koopa Troopa", "frames": 5, "hp": 14, "pow": 4, "def": 2, "xp": 6, "coins": 4,
		"recruit": 0.35, "move": "shell_toss"},
	"shy_guy": {"name": "Shy Guy", "frames": 6, "hp": 12, "pow": 5, "def": 1, "xp": 5, "coins": 4,
		"recruit": 0.35, "move": "shy_spin"},
	"buzzy_beetle": {"name": "Buzzy Beetle", "frames": 8, "hp": 12, "pow": 4, "def": 4, "xp": 7, "coins": 5,
		"recruit": 0.3, "move": "shell_spin"},
	"dry_bones": {"name": "Dry Bones", "frames": 5, "hp": 16, "pow": 5, "def": 2, "xp": 10, "coins": 7,
		"recruit": 0.25, "move": "bone_toss"},
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
		"npcs": [{"id": "toad", "pos": Vector2(435, 311)}, {"id": "pianta", "pos": Vector2(560, 330)},
			{"id": "bombette", "pos": Vector2(150, 290)}, {"id": "goombella", "pos": Vector2(640, 220)},
			{"id": "bobbery", "pos": Vector2(1000, 230)}, {"id": "peasley", "pos": Vector2(1180, 215)},
			{"id": "koops", "pos": Vector2(1120, 430)}, {"id": "bow", "pos": Vector2(980, 470)}],
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
			{"type": "koopa", "pos": Vector2(700, 222)}, {"type": "shy_guy", "pos": Vector2(883, 302)},
			{"type": "buzzy_beetle", "pos": Vector2(1150, 250)}, {"type": "galoomba", "pos": Vector2(678, 545)},
			{"type": "dry_bones", "pos": Vector2(1250, 130)}, {"type": "koopa", "pos": Vector2(1240, 457)},
			{"type": "shy_guy", "pos": Vector2(1100, 600)}, {"type": "galoomba", "pos": Vector2(548, 447)},
		],
		"npcs": [{"id": "yoshi_kid", "pos": Vector2(765, 285)}, {"id": "yoshi", "pos": Vector2(1380, 180)}],
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
	_add_action("chat", [KEY_T, KEY_SLASH], [])


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
		"username": clean_username(username), "uid": new_uid(), "character": character_id, "side": c["side"], "level": 1, "xp": 0, "coins": 20,
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


## A random id that stays the same for this save, so your party partner can
## find you again on the next map.
func new_uid() -> String:
	var bytes := Crypto.new().generate_random_bytes(6)
	return bytes.hex_encode()


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


## The move (MOVES id) a party member uses on its turn, or an enemy is known for.
func move_of(kind: String, id: String) -> String:
	var src: Dictionary = PARTNERS.get(id, {}) if kind == "partner" else ENEMIES.get(id, {})
	return src.get("move", "rolling_bump")


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
	# With your partner on this map, they're pulled into the fight too.
	var scene := COOP_SCENE if Net.party_here and Net.is_online() else BATTLE_SCENE
	get_tree().call_deferred("change_scene_to_file", scene)


## Your partner started a battle and asked you in (see coop_guest.gd).
func join_coop(start: Dictionary, overworld_position: Vector2) -> void:
	player["position"] = [overworld_position.x, overworld_position.y]
	pending_battle = {"coop": start, "key": ""}
	get_tree().call_deferred("change_scene_to_file", COOP_GUEST_SCENE)


## What a foe sees of you in an online duel (sent through the server).
func pvp_stats() -> Dictionary:
	var out := {}
	for key in ["hp", "max_hp", "sp", "max_sp", "pow", "def", "level", "coins"]:
		out[key] = player[key]
	return out


## An online duel with another player. foe: {id, name, character, stats}.
func start_pvp(foe: Dictionary, first: bool, overworld_position: Vector2) -> void:
	player["position"] = [overworld_position.x, overworld_position.y]
	pending_battle = {"pvp": foe, "first": first, "key": ""}
	player["in_duel"] = true  # cleared when the duel ends; quitting mid-duel counts as a loss
	save()
	get_tree().call_deferred("change_scene_to_file", PVP_SCENE)


## Coins a player drops when they lose a duel (the winner picks them up).
func pvp_drop(coins: int) -> int:
	return coins - int(coins * 0.9)


## result: "won", "lost" or "fled".
func end_battle(result: String) -> void:
	player.erase("in_duel")
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
	if not data.has("uid"):
		data["uid"] = new_uid()
	if data.get("in_duel", false):
		# Closed the game mid-duel: that's a loss (coins dropped, back home).
		data.erase("in_duel")
		data["coins"] -= pvp_drop(data["coins"])
		data["hp"] = data["max_hp"]
		data["map"] = HOME_MAP.get(data.get("side", "good"), "castle_town")
		data["spawn"] = "start"
		data["position"] = null
	player = data
	return true


func continue_game() -> void:
	get_tree().call_deferred("change_scene_to_file", WORLD_SCENE)
