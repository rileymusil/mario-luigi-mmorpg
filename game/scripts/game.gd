extends Node
## Global game state (autoloaded as "Game"): data tables, the player's save,
## and moving between the title, the world maps and battles.

const TITLE_SCENE := "res://scenes/title.tscn"
const WORLD_SCENE := "res://scenes/world.tscn"
const BATTLE_SCENE := "res://scenes/battle.tscn"
const PVP_SCENE := "res://scenes/pvp_battle.tscn"
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

## Townsfolk you can talk to (sheets cut by tools/slice_sprites.py, same
## layout as everyone else). What they say lives in res://data/dialogue.json.
const NPCS := {
	"bean_elder": {"name": "Beanish Elder", "frames": 1},
	"bean_villager": {"name": "Beanish", "frames": 1},
	"bean_kid": {"name": "Beanish Kid", "frames": 1},
	"bean_girl": {"name": "Beanette", "frames": 1},
	"bean_guard": {"name": "Beanbean Guard", "frames": 8},
	"shopkeeper": {"name": "Shopkeeper", "frames": 5},
	"toad_blue": {"name": "Toad", "frames": 8},
	"toadsworth": {"name": "Toadsworth", "frames": 8},
	"dr_toad": {"name": "Dr. Toad", "frames": 8},
	"lady_lima": {"name": "Lady Lima", "frames": 5},
	"queen_bean": {"name": "Queen Bean", "frames": 1},
	"koopa_troop": {"name": "Koopa Troop", "frames": 8},
	"koopa_troop_red": {"name": "Koopa Troop", "frames": 8},
	"border_bro": {"name": "Border Bro", "frames": 4},
	"hoohoo_villager": {"name": "Hoohoo Villager", "frames": 5},
	"hoohoo_villager_b": {"name": "Hoohoo Villager", "frames": 5},
}

## What shops sell: `key` is the counter in the save that goes up.
const ITEMS := {
	"mushroom": {"name": "Mushroom", "key": "mushrooms", "info": "Restores 10 HP."},
}

## Maps: art and walk mask in res://assets/maps/ (built by tools/make_maps.py).
## exits: walking into `rect` moves you to `to` at that map's `spawn` point.
## A `door` exit (a building's door) only opens while you push up into it.
## npcs: {id, pos, talk (dialogue id, defaults to id), face ("down", "left",
## "right" or "up"), fixed (stand exactly at pos, e.g. behind a counter),
## reach (talking distance, for counters)}.
const MAPS := {
	"castle_town": {
		"name": "Beanbean Castle Town", "safe": true,
		"spawns": {"start": Vector2(320, 560), "east_gate": Vector2(1350, 409), "west_gate": Vector2(70, 409),
			"palace": Vector2(340, 135), "house_nw": Vector2(100, 272), "shop_badge": Vector2(500, 310),
			"house_sw": Vector2(147, 562), "house_s": Vector2(579, 547), "cafe": Vector2(902, 540),
			"house_ne_w": Vector2(1016, 205), "house_ne_e": Vector2(1146, 205), "shop_mushroom": Vector2(1096, 392),
			"house_se": Vector2(1303, 562)},
		"exits": [
			{"rect": Rect2(1430, 380, 22, 60), "to": "outskirts", "spawn": "south_path"},
			{"rect": Rect2(0, 380, 22, 60), "to": "outskirts", "spawn": "south_path"},
			{"rect": Rect2(320, 116, 40, 12), "to": "castle_hall", "spawn": "entrance", "door": true},
			{"rect": Rect2(84, 258, 32, 12), "to": "house_nw", "spawn": "door", "door": true},
			{"rect": Rect2(484, 296, 32, 12), "to": "shop_badge", "spawn": "door", "door": true},
			{"rect": Rect2(131, 548, 32, 12), "to": "house_sw", "spawn": "door", "door": true},
			{"rect": Rect2(563, 533, 32, 12), "to": "house_s", "spawn": "door", "door": true},
			{"rect": Rect2(886, 525, 32, 12), "to": "starbeans_cafe", "spawn": "door", "door": true},
			{"rect": Rect2(1000, 190, 33, 12), "to": "house_ne", "spawn": "door_w", "door": true},
			{"rect": Rect2(1130, 190, 33, 12), "to": "house_ne", "spawn": "door_e", "door": true},
			{"rect": Rect2(1080, 378, 32, 12), "to": "shop_mushroom", "spawn": "door", "door": true},
			{"rect": Rect2(1287, 548, 33, 12), "to": "house_se", "spawn": "door", "door": true},
		],
		"enemies": [],
		"npcs": [
			{"id": "toad", "pos": Vector2(435, 311)}, {"id": "pianta", "pos": Vector2(560, 330)},
			{"id": "bean_guard", "pos": Vector2(300, 150), "talk": "palace_guard"},
			{"id": "bean_guard", "pos": Vector2(382, 150), "talk": "palace_guard"},
			{"id": "bean_villager", "pos": Vector2(90, 420), "talk": "town_gate", "face": "right"},
			{"id": "bean_kid", "pos": Vector2(640, 450), "talk": "town_kid"},
			{"id": "bean_girl", "pos": Vector2(1180, 400), "talk": "town_girl", "face": "left"},
			{"id": "toadsworth", "pos": Vector2(1330, 420), "talk": "toadsworth", "face": "left"},
			{"id": "bean_villager", "pos": Vector2(250, 300), "talk": "town_gossip"},
		],
	},
	"outskirts": {
		"name": "Beanbean Outskirts", "safe": false,
		"spawns": {"south_path": Vector2(800, 615), "east_bridge": Vector2(1420, 65), "east_path": Vector2(1425, 405)},
		"exits": [
			{"rect": Rect2(760, 630, 90, 7), "to": "castle_town", "spawn": "east_gate"},
			{"rect": Rect2(1455, 30, 10, 70), "to": "bowser_castle", "spawn": "bridge"},
			{"rect": Rect2(1452, 380, 13, 50), "to": "stardust_fields", "spawn": "west_low"},
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
		"npcs": [],
	},
	"bowser_castle": {
		"name": "Bowser's Castle", "safe": true,
		"spawns": {"start": Vector2(205, 250), "bridge": Vector2(205, 580)},
		"exits": [{"rect": Rect2(170, 605, 70, 10), "to": "outskirts", "spawn": "east_bridge"}],
		"enemies": [],
		"npcs": [
			{"id": "koopa_troop", "pos": Vector2(140, 240), "talk": "koopa_guard", "face": "right"},
			{"id": "koopa_troop", "pos": Vector2(270, 240), "talk": "koopa_guard", "face": "left"},
			{"id": "koopa_troop_red", "pos": Vector2(125, 330), "talk": "koopa_shop", "face": "right"},
			{"id": "border_bro", "pos": Vector2(285, 330), "talk": "bowser_gatekeeper", "face": "left"},
		],
	},
	# Castle Town buildings. Each door mat leads back out to its door.
	"house_nw": {
		"name": "Elder's House", "safe": true,
		"spawns": {"door": Vector2(106, 216)},
		"exits": [{"rect": Rect2(92, 232, 28, 14), "to": "castle_town", "spawn": "house_nw"}],
		"enemies": [],
		"npcs": [{"id": "bean_elder", "pos": Vector2(60, 160), "talk": "elder_rest"}],
	},
	"house_sw": {
		"name": "Beanish House", "safe": true,
		"spawns": {"door": Vector2(106, 216)},
		"exits": [{"rect": Rect2(92, 232, 28, 14), "to": "castle_town", "spawn": "house_sw"}],
		"enemies": [],
		"npcs": [{"id": "bean_villager", "pos": Vector2(140, 170), "talk": "house_bean"}],
	},
	"house_s": {
		"name": "Toad Lodge", "safe": true,
		"spawns": {"door": Vector2(106, 216)},
		"exits": [{"rect": Rect2(92, 232, 28, 14), "to": "castle_town", "spawn": "house_s"}],
		"enemies": [],
		"npcs": [{"id": "toad_blue", "pos": Vector2(70, 170), "talk": "lodge_toad"}],
	},
	"house_se": {
		"name": "Dr. Toad's Clinic", "safe": true,
		"spawns": {"door": Vector2(106, 220)},
		"exits": [{"rect": Rect2(92, 236, 28, 14), "to": "castle_town", "spawn": "house_se"}],
		"enemies": [],
		"npcs": [{"id": "dr_toad", "pos": Vector2(106, 165), "talk": "dr_toad"}],
	},
	"house_ne": {
		"name": "Beanbean Town Hall", "safe": true,
		"spawns": {"door_w": Vector2(106, 212), "door_e": Vector2(314, 212)},
		"exits": [
			{"rect": Rect2(92, 228, 28, 14), "to": "castle_town", "spawn": "house_ne_w"},
			{"rect": Rect2(300, 228, 28, 14), "to": "castle_town", "spawn": "house_ne_e"},
		],
		"enemies": [],
		"npcs": [
			{"id": "bean_elder", "pos": Vector2(200, 165), "talk": "mayor"},
			{"id": "bean_kid", "pos": Vector2(300, 180), "talk": "town_hall_kid", "face": "left"},
		],
	},
	"shop_mushroom": {
		"name": "Mushroom Shop", "safe": true,
		"spawns": {"door": Vector2(56, 222)},
		"exits": [{"rect": Rect2(40, 238, 32, 14), "to": "castle_town", "spawn": "shop_mushroom"}],
		"enemies": [],
		"npcs": [{"id": "shopkeeper", "pos": Vector2(130, 96), "talk": "mushroom_shop", "fixed": true, "reach": 56.0}],
	},
	"shop_badge": {
		"name": "Badge Shop", "safe": true,
		"spawns": {"door": Vector2(57, 222)},
		"exits": [{"rect": Rect2(41, 238, 32, 14), "to": "castle_town", "spawn": "shop_badge"}],
		"enemies": [],
		"npcs": [{"id": "shopkeeper", "pos": Vector2(130, 96), "talk": "badge_shop", "fixed": true, "reach": 56.0}],
	},
	"starbeans_cafe": {
		"name": "Starbeans Cafe", "safe": true,
		"spawns": {"door": Vector2(248, 228)},
		"exits": [{"rect": Rect2(226, 250, 44, 14), "to": "castle_town", "spawn": "cafe"}],
		"enemies": [],
		"npcs": [
			{"id": "bean_villager", "pos": Vector2(300, 160), "talk": "cafe_barista", "face": "left"},
			{"id": "bean_girl", "pos": Vector2(130, 185), "talk": "cafe_customer", "face": "right"},
		],
	},
	"castle_hall": {
		"name": "Beanbean Castle", "safe": true,
		"spawns": {"entrance": Vector2(224, 286), "arch": Vector2(224, 125)},
		"exits": [
			{"rect": Rect2(192, 300, 65, 13), "to": "castle_town", "spawn": "palace"},
			{"rect": Rect2(198, 92, 52, 16), "to": "throne_room", "spawn": "south", "door": true},
		],
		"enemies": [],
		"npcs": [
			{"id": "bean_guard", "pos": Vector2(175, 135), "talk": "castle_guard"},
			{"id": "bean_guard", "pos": Vector2(275, 135), "talk": "castle_guard"},
			{"id": "lady_lima", "pos": Vector2(330, 240), "talk": "lady_lima", "face": "left"},
		],
	},
	"throne_room": {
		"name": "Throne Room", "safe": true,
		"spawns": {"south": Vector2(107, 435)},
		"exits": [{"rect": Rect2(82, 455, 50, 13), "to": "castle_hall", "spawn": "arch"}],
		"enemies": [],
		"npcs": [
			{"id": "queen_bean", "pos": Vector2(107, 225), "talk": "queen_bean"},
			{"id": "bean_guard", "pos": Vector2(60, 300), "talk": "throne_guard", "face": "right"},
		],
	},
	# Beyond the Outskirts: Stardust Fields (wild) and Hoohoo Village (a town).
	"stardust_fields": {
		"name": "Stardust Fields", "safe": false,
		"spawns": {"west_low": Vector2(40, 590), "west_high": Vector2(30, 418), "north": Vector2(205, 30),
			"east": Vector2(495, 134)},
		"exits": [
			{"rect": Rect2(0, 568, 12, 36), "to": "outskirts", "spawn": "east_path"},
			{"rect": Rect2(0, 400, 12, 36), "to": "outskirts", "spawn": "east_path"},
			{"rect": Rect2(180, 0, 50, 10), "to": "hoohoo_village", "spawn": "south"},
			{"rect": Rect2(515, 118, 15, 32), "to": "hoohoo_village", "spawn": "west"},
		],
		"enemies": [
			{"type": "goomba", "pos": Vector2(60, 200)}, {"type": "koopa", "pos": Vector2(200, 232)},
			{"type": "shy_guy", "pos": Vector2(344, 160)}, {"type": "buzzy_beetle", "pos": Vector2(420, 300)},
			{"type": "dry_bones", "pos": Vector2(300, 380)}, {"type": "galoomba", "pos": Vector2(103, 373)},
			{"type": "beanie", "pos": Vector2(377, 123)}, {"type": "shy_guy", "pos": Vector2(230, 400)},
			{"type": "buzzy_beetle", "pos": Vector2(440, 200)}, {"type": "koopa", "pos": Vector2(140, 520)},
		],
		"npcs": [
			{"id": "border_bro", "pos": Vector2(160, 58), "talk": "border_bro"},
			{"id": "hoohoo_villager_b", "pos": Vector2(90, 600), "talk": "stardust_traveler", "face": "left"},
		],
	},
	"hoohoo_village": {
		"name": "Hoohoo Village", "safe": true,
		"spawns": {"west": Vector2(20, 112), "south": Vector2(527, 415), "hut_w": Vector2(233, 148),
			"hut_e": Vector2(456, 148)},
		"exits": [
			{"rect": Rect2(0, 92, 10, 40), "to": "stardust_fields", "spawn": "east"},
			{"rect": Rect2(508, 428, 40, 16), "to": "stardust_fields", "spawn": "north"},
			{"rect": Rect2(219, 134, 28, 12), "to": "hoohoo_hut_w", "spawn": "door", "door": true},
			{"rect": Rect2(442, 134, 28, 12), "to": "hoohoo_hut_e", "spawn": "door", "door": true},
		],
		"enemies": [],
		"npcs": [
			{"id": "hoohoo_villager", "pos": Vector2(90, 115), "talk": "hoohoo_greeter"},
			{"id": "hoohoo_villager_b", "pos": Vector2(345, 110), "talk": "hoohoo_deck"},
			{"id": "hoohoo_villager_b", "pos": Vector2(685, 215), "talk": "hoohoo_mountain", "face": "left"},
			{"id": "hoohoo_villager", "pos": Vector2(300, 400), "talk": "hoohoo_cave", "face": "left"},
		],
	},
	"hoohoo_hut_w": {
		"name": "Hoohoo Hut", "safe": true,
		"spawns": {"door": Vector2(161, 212)},
		"exits": [{"rect": Rect2(146, 228, 31, 14), "to": "hoohoo_village", "spawn": "hut_w"}],
		"enemies": [],
		"npcs": [{"id": "hoohoo_villager", "pos": Vector2(100, 180), "talk": "hut_rest"}],
	},
	"hoohoo_hut_e": {
		"name": "Hoohoo Hut", "safe": true,
		"spawns": {"door": Vector2(42, 212)},
		"exits": [{"rect": Rect2(26, 228, 32, 14), "to": "hoohoo_village", "spawn": "hut_e"}],
		"enemies": [],
		"npcs": [{"id": "hoohoo_villager_b", "pos": Vector2(100, 180), "talk": "hut_lore"}],
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
