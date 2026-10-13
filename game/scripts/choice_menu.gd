class_name ChoiceMenu
extends PanelContainer
## A small Superstar Saga style menu: a speech balloon (from the theme) with a
## yellow pointer. Up/Down to move, Z to pick, X to back out (when allowed).
## Clicking or tapping an option also picks it.
##     var index: int = await menu.choose(["Jump", "Run"])   # -1 = cancelled
## Set theme_type_variation to "FlatPanel" to drop the balloon (e.g. inside
## the pause notebook).

signal chosen(index: int)

const CURSOR := preload("res://assets/ui/cursor.png")

var _options: Array = []
var _enabled: Array = []
var _index := 0
var _cancellable := false
var _box: VBoxContainer
var _title: Label
var _info: Label
var _infos: Array = []
var _labels: Array[Label] = []
var _cursors: Array[TextureRect] = []
var _active := false
var _time := 0.0
## Width the help text under the options wraps at.
var info_width := 150.0


func _init() -> void:
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 0)
	add_child(_box)
	_title = _make_label("TitleLabel")
	_info = _make_label("InfoLabel")
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	visible = false


func _make_label(variation := "") -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	return l


## options: Array of strings. enabled: optional Array of bools (greyed out if
## false). infos: optional Array of help lines shown under the list.
func choose(options: Array, title := "", cancellable := false, enabled: Array = [], infos: Array = []) -> int:
	_options = options
	_enabled = enabled if enabled.size() == options.size() else []
	_infos = infos
	_cancellable = cancellable
	_index = 0
	for child in _box.get_children():
		_box.remove_child(child)
		if child != _title and child != _info:
			child.queue_free()
	_labels.clear()
	_cursors.clear()
	_title.text = title
	if title != "":
		_box.add_child(_title)
	for i in options.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var cursor := TextureRect.new()
		cursor.texture = CURSOR
		cursor.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		cursor.custom_minimum_size = Vector2(17, 12)
		row.add_child(cursor)
		var l := _make_label()
		l.text = str(options[i])
		l.gui_input.connect(_on_label_input.bind(i))
		row.add_child(l)
		_box.add_child(row)
		_labels.append(l)
		_cursors.append(cursor)
	if not infos.is_empty():
		_info.custom_minimum_size.x = info_width
		_box.add_child(_info)
	visible = true
	_active = false
	_refresh()
	reset_size()
	# Wait a frame so the press that opened the menu doesn't also pick.
	await get_tree().process_frame
	_active = true
	var result: int = await chosen
	visible = false
	_active = false
	return result


func _is_enabled(i: int) -> bool:
	return _enabled.is_empty() or _enabled[i]


func _refresh() -> void:
	for i in _labels.size():
		_labels[i].modulate = Color.WHITE if _is_enabled(i) else Color(1, 1, 1, 0.4)
		_cursors[i].self_modulate.a = 1.0 if i == _index else 0.0
	if not _infos.is_empty():
		_info.text = str(_infos[_index])


func _process(delta: float) -> void:
	if not visible or _cursors.is_empty():
		return
	# The pointer nudges left and right like in the save menu.
	_time += delta
	var c := _cursors[clampi(_index, 0, _cursors.size() - 1)]
	c.position.x = -1.0 + roundf(sin(_time * 7.0) * 1.5)


func _unhandled_input(event: InputEvent) -> void:
	if not _active or not visible:
		return
	if event.is_action_pressed("move_down"):
		_index = (_index + 1) % _options.size()
		_refresh()
	elif event.is_action_pressed("move_up"):
		_index = (_index - 1 + _options.size()) % _options.size()
		_refresh()
	elif event.is_action_pressed("action"):
		_pick(_index)
	elif event.is_action_pressed("talk") and _cancellable:
		_active = false
		chosen.emit(-1)
	else:
		return
	get_viewport().set_input_as_handled()


func _on_label_input(event: InputEvent, i: int) -> void:
	if _active and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_index = i
		_refresh()
		_pick(i)


func _pick(i: int) -> void:
	if not _is_enabled(i):
		return
	_active = false
	chosen.emit(i)
