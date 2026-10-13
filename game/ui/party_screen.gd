class_name PartyScreen
extends Control
## The party menu: one equipment-menu stat card per party member (red for you,
## green for partners), with a menu beside them to send someone home.

const CARD_RED := preload("res://assets/ui/card_red.png")
const CARD_GREEN := preload("res://assets/ui/card_green.png")
const ICONS := {
	"lv": preload("res://assets/ui/lv.png"), "heart": preload("res://assets/ui/icon_heart.png"),
	"bean": preload("res://assets/ui/icon_bean.png"), "pow": preload("res://assets/ui/icon_pow.png"),
	"def": preload("res://assets/ui/icon_def.png"),
}
const CARD_X := 20.0
const CARD_GAP := 52.0

@onready var menu: ChoiceMenu = $Menu
@onready var cards: Control = $Cards
@onready var pointer: TextureRect = $Pointer

var _member_cards: Array[Control] = []
var _time := 0.0


func _ready() -> void:
	visible = false


func open(p: Dictionary, character_name: String) -> void:
	for c in cards.get_children():
		c.queue_free()
	_member_cards.clear()
	var y := 8.0
	_add_card(Vector2(CARD_X, y), CARD_RED, character_name, "You", p["character"],
		[["lv", p["level"]], ["heart", "%d/%d" % [p["hp"], p["max_hp"]]], ["bean", "%d/%d" % [p["sp"], p["max_sp"]]]],
		[["pow", p["pow"]], ["def", p["def"]]])
	for m in p["party"]:
		y += CARD_GAP
		var card := _add_card(Vector2(CARD_X, y), CARD_GREEN, m["name"], "Partner" if m["kind"] == "partner" else "Recruit",
			m["id"], [["heart", "%d/%d" % [m["hp"], m["max_hp"]]]], [["pow", m["pow"]], ["def", m["def"]]])
		_member_cards.append(card)
	visible = true


func close() -> void:
	visible = false


func _add_card(pos: Vector2, art: Texture2D, title: String, kind: String, id: String, row1: Array, row2: Array) -> Control:
	var card := TextureRect.new()
	card.texture = art
	card.position = pos
	cards.add_child(card)
	var name_label := Label.new()
	name_label.theme_type_variation = &"LightLabel"
	name_label.text = title
	name_label.position = Vector2(22, -1)
	card.add_child(name_label)
	var kind_label := Label.new()
	kind_label.theme_type_variation = &"LightLabel"
	kind_label.text = kind
	kind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kind_label.position = Vector2(130, -1)
	kind_label.size = Vector2(90, 12)
	card.add_child(kind_label)
	var sprite := CharacterSprite.new()
	sprite.character_id = id
	sprite.position = Vector2(34, 44)
	card.add_child(sprite)
	sprite.scale = Vector2.ONE * minf(1.0, 33.0 / sprite.height())
	card.add_child(_stat_row(row1, Vector2(62, 12)))
	card.add_child(_stat_row(row2, Vector2(62, 28)))
	return card


func _stat_row(stats: Array, pos: Vector2) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.position = pos
	row.add_theme_constant_override("separation", 3)
	for s in stats:
		var icon := TextureRect.new()
		icon.texture = ICONS[s[0]]
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		row.add_child(icon)
		if s[0] == "lv":
			var digits := GoldNumber.new()
			digits.value = s[1]
			row.add_child(digits)
		else:
			var l := Label.new()
			l.text = str(s[1])
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(l)
		var gap := Control.new()
		gap.custom_minimum_size.x = 8
		row.add_child(gap)
	return row


func _process(delta: float) -> void:
	_time += delta
	pointer.visible = visible and menu.visible and not _member_cards.is_empty()
	if pointer.visible:
		var card := _member_cards[clampi(menu._index, 0, _member_cards.size() - 1)]
		pointer.position = card.position + Vector2(-17.0 + roundf(sin(_time * 7.0) * 1.5), 18)
