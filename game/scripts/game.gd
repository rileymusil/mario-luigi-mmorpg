extends Node
## Global game state (autoloaded as "Game"): input setup, party stats,
## and switching between the overworld and battles.

const OVERWORLD_SCENE := "res://scenes/overworld.tscn"
const BATTLE_SCENE := "res://scenes/battle.tscn"

const ENEMIES := {
	"goomba": {"name": "Goomba", "max_hp": 12, "pow": 4, "def": 0, "coins": 5},
}

var party := {
	"mario": {"name": "Mario", "max_hp": 20, "hp": 20, "pow": 4, "def": 1, "button": "mario_action"},
	"luigi": {"name": "Luigi", "max_hp": 22, "hp": 22, "pow": 3, "def": 2, "button": "luigi_action"},
}
var coins := 0

# Overworld state kept while a battle is running.
var return_position := Vector2.ZERO
var has_return_position := false
var defeated_enemies := {}
var current_enemy_id := ""
var current_enemy_type := ""


func _ready() -> void:
	_add_action("move_left", [KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT])
	_add_action("move_right", [KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT])
	_add_action("move_up", [KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP])
	_add_action("move_down", [KEY_DOWN, KEY_S], [JOY_BUTTON_DPAD_DOWN])
	# Superstar Saga style: one button per brother.
	_add_action("mario_action", [KEY_Z, KEY_J], [JOY_BUTTON_A])
	_add_action("luigi_action", [KEY_X, KEY_K], [JOY_BUTTON_B])


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


func start_battle(enemy_id: String, enemy_type: String, overworld_position: Vector2) -> void:
	current_enemy_id = enemy_id
	current_enemy_type = enemy_type
	return_position = overworld_position
	has_return_position = true
	get_tree().call_deferred("change_scene_to_file", BATTLE_SCENE)


func end_battle(won: bool) -> void:
	if won:
		defeated_enemies[current_enemy_id] = true
		coins += ENEMIES[current_enemy_type]["coins"]
	else:
		# Prototype rule: losing heals the Bros. and sends them back to the start.
		for bro in party.values():
			bro["hp"] = bro["max_hp"]
		has_return_position = false
	get_tree().call_deferred("change_scene_to_file", OVERWORLD_SCENE)


func hud_text() -> String:
	var m: Dictionary = party["mario"]
	var l: Dictionary = party["luigi"]
	return "Mario %d/%d   Luigi %d/%d   Coins %d" % [m["hp"], m["max_hp"], l["hp"], l["max_hp"], coins]
