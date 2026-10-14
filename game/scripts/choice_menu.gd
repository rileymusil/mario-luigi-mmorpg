class_name ChoiceMenu
extends PanelContainer
## A small Superstar Saga style menu: a speech balloon (from the theme) with a
## yellow pointer. Up/Down to move, Z to pick, X to back out (when allowed).
## Mouse: pointing at an option moves the pointer there, a click picks it, a
## right click or a click outside the menu backs out. Touch: tap an option to
## pick it (slide off it before lifting to change your mind), tap outside the
## menu to back out.
##     var index: int = await menu.choose(["Jump", "Run"])   # -1 = cancelled
## Optional pictures beside the options (icons), and a scrolling window of
## max_rows options with arrows when there are more (mouse wheel scrolls too).
## Set theme_type_variation to "FlatPanel" to drop the balloon (e.g. inside
## the pause notebook). Clicks on controls that stop the mouse (the notebook,
## a speech balloon) don't count as "outside".

signal chosen(index: int)
## The pointer moved to another option (by keys, mouse, touch or highlight()).
signal highlighted(index: int)

const CURSOR := preload("res://assets/ui/cursor.png")
const MORE_ARROW := preload("res://assets/ui/next_arrow.png")

var _options: Array = []
var _enabled: Array = []
var _index := 0
var _cancellable := false
var _box: VBoxContainer
var _title: Label
var _info: Label
var _infos: Array = []
var _rows: Array[Control] = []
var _labels: Array[Label] = []
var _cursors: Array[TextureRect] = []
var _active := false
var _time := 0.0
var _touch_row := -1  # the option a finger went down on
## Width the help text under the options wraps at.
var info_width := 150.0
## Show at most this many options at once (0 = all); the list scrolls.
var max_rows := 0
var _first := 0       # the first option shown, when scrolling
var _arrows: Control  # "more above / below" marks, drawn over the list
var _up: TextureRect
var _down: TextureRect


func _init() -> void:
	add_to_group(&"choice_menus")
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 0)
	add_child(_box)
	_title = _make_label("TitleLabel")
	_info = _make_label("InfoLabel")
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_arrows = Control.new()
	_arrows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_arrows)
	_up = TextureRect.new()
	_up.texture = MORE_ARROW
	_up.flip_v = true
	_down = TextureRect.new()
	_down.texture = MORE_ARROW
	for a in [_up, _down]:
		# Clicking or tapping an arrow scrolls that way.
		a.mouse_filter = Control.MOUSE_FILTER_STOP
		a.visible = false
		a.gui_input.connect(_on_arrow_input.bind(-1 if a == _up else 1))
		_arrows.add_child(a)
	visible = false


func _make_label(variation := "") -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## options: Array of strings. enabled: optional Array of bools (greyed out if
## false). infos: optional Array of help lines shown under the list.
## icons: optional Array of Texture2D (or null) shown before each option.
## start: the option the pointer starts on.
func choose(options: Array, title := "", cancellable := false, enabled: Array = [], infos: Array = [],
		icons: Array = [], start := 0) -> int:
	_options = options
	_enabled = enabled if enabled.size() == options.size() else []
	_infos = infos
	_cancellable = cancellable
	_index = clampi(start, 0, maxi(options.size() - 1, 0))
	_first = 0
	_touch_row = -1
	for child in _box.get_children():
		_box.remove_child(child)
		if child != _title and child != _info:
			child.queue_free()
	_rows.clear()
	_labels.clear()
	_cursors.clear()
	_title.text = title
	if title != "":
		_box.add_child(_title)
	for i in options.size():
		# The whole row (pointer and text, full menu width) takes the mouse.
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.gui_input.connect(_on_row_input.bind(i))
		var cursor := TextureRect.new()
		cursor.texture = CURSOR
		cursor.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		cursor.custom_minimum_size = Vector2(17, 12)
		cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(cursor)
		if i < icons.size() and icons[i] != null:
			var pic := TextureRect.new()
			pic.texture = icons[i]
			pic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			pic.custom_minimum_size = Vector2(16, 16)
			pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(pic)
		var l := _make_label()
		l.text = str(options[i])
		row.add_child(l)
		if max_rows > 0 and options.size() > max_rows:
			var room := Control.new()  # keeps the text clear of the scroll arrows
			room.custom_minimum_size.x = MORE_ARROW.get_width() + 1
			room.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(room)
		_box.add_child(row)
		_rows.append(row)
		_labels.append(l)
		_cursors.append(cursor)
	if not infos.is_empty():
		_info.custom_minimum_size.x = info_width
		_box.add_child(_info)
	visible = true
	_active = false
	_refresh()
	reset_size()
	pivot_offset = size / 2.0
	scale = Vector2(0.92, 0.92)
	modulate.a = 0.5
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "modulate:a", 1.0, 0.08)
	# Wait a frame so the press that opened the menu doesn't also pick.
	await get_tree().process_frame
	_active = true
	var result: int = await chosen
	visible = false
	_active = false
	return result


## True while waiting for a choice.
func is_choosing() -> bool:
	return _active and visible


## The options of the current (or last) choose().
func options() -> Array:
	return _options


## Moves the pointer to option i, e.g. when something on screen that stands
## for that option is pointed at.
func highlight(i: int) -> void:
	if i == _index or i < 0 or i >= _options.size():
		return
	_index = i
	_refresh()
	if i < _cursors.size() and is_instance_valid(_cursors[i]):
		_cursors[i].position.x = 2.0
	highlighted.emit(i)


## Picks option i as if Z were pressed on it (not if it is greyed out).
func pick(i: int) -> void:
	if not is_choosing() or i < 0 or i >= _options.size():
		return
	highlight(i)
	_pick(i)


func _is_enabled(i: int) -> bool:
	return _enabled.is_empty() or _enabled[i]


func _refresh() -> void:
	for i in _labels.size():
		# The label and its picture (everything after the pointer) grey out.
		for part in _rows[i].get_children():
			if part != _cursors[i]:
				part.modulate = Color.WHITE if _is_enabled(i) else Color(1, 1, 1, 0.4)
		_cursors[i].self_modulate.a = 1.0 if i == _index else 0.0
	if not _infos.is_empty() and _index < _infos.size():
		_info.text = str(_infos[_index])
	_scroll()


## Shows the max_rows options around the pointer, with arrows if more are
## hidden above or below.
func _scroll() -> void:
	var count := _rows.size()
	var window := max_rows if max_rows > 0 else count
	if count <= window:
		_first = 0
	else:
		_first = clampi(_first, _index - window + 1, _index)
		_first = clampi(_first, 0, count - window)
	for i in count:
		_rows[i].visible = i >= _first and i < _first + window
	_up.visible = _first > 0
	_down.visible = _first + window < count
	_place_arrows.call_deferred()


func _place_arrows() -> void:
	if _rows.is_empty() or not is_instance_valid(_rows[0]):
		return
	var first := _rows[clampi(_first, 0, _rows.size() - 1)]
	var last_i := mini(_rows.size(), _first + (max_rows if max_rows > 0 else _rows.size())) - 1
	var last := _rows[maxi(last_i, 0)]
	var x := roundf(_arrows.size.x - MORE_ARROW.get_width() - 1.0)
	var bob := roundf(sin(_time * 6.0))
	_up.position = Vector2(x, first.position.y - 1.0 - bob)
	_down.position = Vector2(x, last.position.y + last.size.y - MORE_ARROW.get_height() + 1.0 + bob)


func _process(delta: float) -> void:
	if not visible or _cursors.is_empty():
		return
	# The pointer nudges left and right like in the save menu.
	_time += delta
	var c := _cursors[clampi(_index, 0, _cursors.size() - 1)]
	c.position.x = lerpf(c.position.x, -1.0 + sin(_time * 7.0) * 1.5, clampf(18.0 * delta, 0.0, 1.0))
	if _up.visible or _down.visible:
		_place_arrows()


func _input(event: InputEvent) -> void:
	# A right click backs out wherever the mouse is.
	if is_choosing() and _cancellable and Pointer.is_back(event):
		get_viewport().set_input_as_handled()
		_cancel()


func _unhandled_input(event: InputEvent) -> void:
	if not is_choosing():
		return
	if event.is_action_pressed("move_down"):
		highlight((_index + 1) % _options.size())
	elif event.is_action_pressed("move_up"):
		highlight((_index - 1 + _options.size()) % _options.size())
	elif _wheel(event) != 0:
		highlight(clampi(_index + _wheel(event), 0, _options.size() - 1))
	elif event.is_action_pressed("action"):
		_pick(_index)
	elif event.is_action_pressed("talk") and _cancellable:
		_cancel()
	elif Pointer.is_press(event) and _cancellable:
		# A click or tap that no option, menu or other box took: outside.
		_cancel()
	else:
		return
	get_viewport().set_input_as_handled()


## +1 / -1 for the mouse wheel turning down / up over a scrolling list.
func _wheel(event: InputEvent) -> int:
	if max_rows <= 0 or _options.size() <= max_rows or not event is InputEventMouseButton or not event.pressed:
		return 0
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		return 1
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		return -1
	return 0


func _on_arrow_input(event: InputEvent, step: int) -> void:
	if _active and Pointer.is_press(event):
		var window := max_rows if max_rows > 0 else _rows.size()
		highlight(clampi((_first if step < 0 else _first + window - 1) + step, 0, _options.size() - 1))
		accept_event()


func _on_row_input(event: InputEvent, i: int) -> void:
	if not _active:
		return
	if _wheel(event) != 0:
		highlight(clampi(_index + _wheel(event), 0, _options.size() - 1))
		accept_event()
	elif Pointer.is_hover(event):
		highlight(i)
	elif event is InputEventScreenTouch:
		# Picks on lifting the finger, if it is still on the option it went down on.
		if event.pressed:
			highlight(i)
			_touch_row = i
		elif _touch_row == i and Rect2(Vector2.ZERO, _rows[i].size).has_point(event.position):
			_touch_row = -1
			_pick(i)
	elif Pointer.is_press(event):
		highlight(i)
		_pick(i)


func _pick(i: int) -> void:
	if not _is_enabled(i):
		return
	_active = false
	if i < _cursors.size() and is_instance_valid(_cursors[i]):
		var c := _cursors[i]
		var tw := create_tween()
		tw.tween_property(c, "position:x", 3.0, 0.05)
		tw.tween_property(c, "position:x", -1.0, 0.05)
		await tw.finished
	chosen.emit(i)


func _cancel() -> void:
	_active = false
	chosen.emit(-1)
