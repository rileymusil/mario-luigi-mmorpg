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


func refresh(p: Dictionary, character_name: String) -> void:
	name_label.text = character_name
	level.value = p["level"]
	hp.text = "%d/%d" % [p["hp"], p["max_hp"]]
	hp.modulate = Color(1, 0.55, 0.5) if p["hp"] * 4 <= p["max_hp"] else Color.WHITE
	sp.text = "%d/%d" % [p["sp"], p["max_sp"]]
	coins.value = p["coins"]
	var good: bool = p["side"] == "good"
	side.text = "GOOD" if good else "EVIL"
	side.add_theme_color_override("font_color", Color(0.5, 0.95, 0.45) if good else Color(1, 0.42, 0.35))
	reset_size()
