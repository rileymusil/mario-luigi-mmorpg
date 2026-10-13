class_name PauseScreen
extends Control
## The pause menu, laid out like the Superstar Saga save notebook: options on
## the left page, the player on the right page, the place name on the strip.

@onready var menu: ChoiceMenu = $Book/Menu
@onready var portrait: CharacterSprite = $Book/Portrait
@onready var name_label: Label = $Book/Name
@onready var level: GoldNumber = $Book/Stats/Level
@onready var coins: GoldNumber = $Book/Stats/Coins
@onready var hp: Label = $Book/Stats/HP
@onready var sp: Label = $Book/Stats/SP
@onready var place: Label = $Book/Place


func _ready() -> void:
	visible = false


func open(p: Dictionary, character_name: String, place_name: String) -> void:
	portrait.character_id = p["character"]
	portrait.facing = Vector2.DOWN
	name_label.text = character_name
	level.value = p["level"]
	coins.value = p["coins"]
	hp.text = "%d/%d" % [p["hp"], p["max_hp"]]
	sp.text = "%d/%d" % [p["sp"], p["max_sp"]]
	place.text = place_name
	visible = true


func close() -> void:
	visible = false
