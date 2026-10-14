class_name ItemsScreen
extends Control
## The Items page of the pause menu, on the same Superstar Saga notebook as
## the pause screen: the items you carry down the left page (picture and how
## many), the one under the pointer on the right page (name, big picture,
## what it does), and a speech-balloon menu to pick who uses it.
## world.gd runs the menus and does what the item does.

@onready var menu: ChoiceMenu = $Book/Menu
@onready var targets: ChoiceMenu = $Book/Targets
@onready var name_label: Label = $Book/Name
@onready var icon: TextureRect = $Book/Icon
@onready var info: Label = $Book/Info
@onready var footer: Label = $Book/Place

var _ids: Array = []


func _ready() -> void:
	visible = false
	menu.max_rows = 5
	menu.custom_minimum_size.x = 64
	menu.highlighted.connect(_show)
	get_tree().root.size_changed.connect(_center_book)


## Same place as the pause notebook (pause_screen.gd): the middle of the screen.
func _center_book() -> void:
	var book: Control = $Book
	book.position = ((get_viewport_rect().size - book.size) / 2.0).round()


static func icon_of(id: String) -> Texture2D:
	return load("res://assets/items/%s.png" % id)


## Lists `ids` (Game.ITEMS or Game.GEAR ids) with their counts (or `labels`);
## greyed out where `usable` is false. Returns the picked index, or -1 when
## backed out.
func choose_item(ids: Array, usable: Array, start := 0, labels: Array = []) -> int:
	_ids = ids
	if labels.size() != ids.size():
		labels = ids.map(func(id): return "x%d" % Game.item_count(id))
	var icons := ids.map(func(id): return icon_of(id))
	_center_book()
	visible = true
	start = clampi(start, 0, maxi(ids.size() - 1, 0))
	_show(start)
	var i := await menu.choose(labels, "", true, usable, [], icons, start)
	menu.visible = i >= 0  # the list stays up while the item is used
	return i


## Who uses it: labels for each choice. -1 when backed out.
func choose_target(labels: Array, enabled: Array = []) -> int:
	return await targets.choose(labels, "Use on", true, enabled)


func set_footer(text: String) -> void:
	footer.text = text


## The page's tab: "ITEMS" or "GEAR".
func set_tab(text: String) -> void:
	$Book/Tab.text = text


func close() -> void:
	visible = false
	menu.visible = false


func _show(i: int) -> void:
	if i < 0 or i >= _ids.size():
		return
	var item: Dictionary = Game.goods(_ids[i])
	name_label.text = item["name"]
	icon.texture = icon_of(_ids[i])
	info.text = item["info"] + ("" if not item.get("battle", false) else " (In battle.)")
