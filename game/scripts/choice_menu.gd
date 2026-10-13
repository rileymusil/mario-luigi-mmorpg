class_name ChoiceMenu
extends PanelContainer
## A small Superstar Saga style menu box. Up/Down to move, Z to pick,
## X to back out (when allowed). Clicking or tapping an option also picks it.
##     var index: int = await menu.choose(["Jump", "Run"])   # -1 = cancelled

signal chosen(index: int)

const FONT_SIZE := 10

var _options: Array = []
var _enabled: Array = []
var _index := 0
var _cancellable := false
var _box: VBoxContainer
var _title: Label
var _info: Label
var _infos: Array = []
var _labels: Array[Label] = []
var _active := false


func _init() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.13, 0.35, 0.94)
	style.border_color = Color(1, 0.95, 0.75)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	add_theme_stylebox_override("panel", style)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 0)
	add_child(_box)
	_title = _make_label(Color(1, 0.85, 0.3))
	_info = _make_label(Color(0.75, 0.85, 1))
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size.x = 150
	visible = false


func _make_label(color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	l.add_theme_color_override("font_color", color)
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
	_labels.clear()
	_title.text = title
	if title != "":
		_box.add_child(_title)
	for i in options.size():
		var l := _make_label(Color.WHITE)
		l.gui_input.connect(_on_label_input.bind(i))
		_box.add_child(l)
		_labels.append(l)
	if not infos.is_empty():
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
		var l := _labels[i]
		l.text = ("> " if i == _index else "   ") + str(_options[i])
		l.modulate = Color.WHITE if _is_enabled(i) else Color(1, 1, 1, 0.4)
	if not _infos.is_empty():
		_info.text = str(_infos[_index])


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
