class_name Hud
extends PanelContainer
## Top-of-screen status bar: name, level, HP, SP, coins and side, on the navy
## bar from the equipment menu with the save menu's gold digits.

@onready var name_label: Label = $Row/Name
@onready var level: GoldNumber = $Row/Level
@onready var hp: Label = $Row/HP
@onready var sp: Label = $Row/SP
@onready var coins: GoldNumber = $Row/Coins
@onready var side: Label = $Row/Side


var _prev_hp := -1
## Portrait phones: no character name, so the bar fits a 256 px wide screen.
var compact := false
var _prev_coins := -1


func refresh(p: Dictionary, character_name: String) -> void:
	name_label.text = character_name
	name_label.visible = not compact
	$Row/Gap.visible = not compact
	level.value = p["level"]
	var new_hp: int = p["hp"]
	hp.text = "%d/%d" % [new_hp, p["max_hp"]]
	hp.modulate = Color(1, 0.55, 0.5) if new_hp * 4 <= p["max_hp"] else Color.WHITE
	if _prev_hp != -1 and new_hp < _prev_hp:
		hp.pivot_offset = hp.size / 2.0
		var tw := create_tween()
		tw.tween_property(hp, "scale", Vector2(1.25, 1.25), 0.06)
		tw.tween_property(hp, "scale", Vector2.ONE, 0.08)
	_prev_hp = new_hp

	sp.text = "%d/%d" % [p["sp"], p["max_sp"]]
	var new_coins: int = p["coins"]
	coins.value = new_coins
	if _prev_coins != -1 and new_coins != _prev_coins:
		coins.pivot_offset = coins.size / 2.0
		var tw := create_tween()
		tw.tween_property(coins, "scale", Vector2(1.2, 1.2), 0.06)
		tw.tween_property(coins, "scale", Vector2.ONE, 0.08)
	_prev_coins = new_coins

	var good: bool = p["side"] == "good"
	side.text = "GOOD" if good else "EVIL"
	side.add_theme_color_override("font_color", Color(0.5, 0.95, 0.45) if good else Color(1, 0.42, 0.35))
	reset_size()
