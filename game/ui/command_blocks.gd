class_name CommandBlocks
extends Control
## Superstar Saga style command blocks floating over whoever's turn it is.
## Left/Right (or Up/Down) to move, Z to pick. The mouse picks too: pointing
## at a block highlights it, clicking it confirms. On a touch screen, tap a
## block (slide off it before lifting to change your mind), or press A.
##     var i: int = await blocks.choose(commands, character_node)
## commands: Array of {label, icon, enabled, info}; icon is a name from
## res://assets/battle/icon_<name>.png. Emits `highlighted` with the info line
## of the block under the pointer so the battle can show it.

signal chosen(index: int)
signal highlighted(info: String)

const BLOCK_YELLOW := preload("res://assets/battle/block_yellow.png")
const BLOCK_BLUE := preload("res://assets/battle/block_blue.png")
const ICON_X := preload("res://assets/battle/icon_x.png")
const GAP := 3.0
const RAISE := 5.0
const MARGIN := 4.0

var _commands: Array = []
var _blocks: Array[TextureRect] = []
var _current_lifts: Array[float] = []
var _target_label_x := 0.0
var _index := 0
var _active := false
var _time := 0.0
var _row_y := 0.0
var _label: Label
var _touch_block := -1  # the block a finger went down on


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.theme_type_variation = &"OutlineLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	visible = false


## anchor: the character the blocks float over (feet at its position).
## partner: blue blocks instead of yellow.
func choose(commands: Array, anchor: CharacterSprite, partner := false) -> int:
	_commands = commands
	for b in _blocks:
		b.queue_free()
	_blocks.clear()
	_current_lifts.clear()
	var block_tex: Texture2D = BLOCK_BLUE if partner else BLOCK_YELLOW
	var size := block_tex.get_size()
	var width := commands.size() * size.x + (commands.size() - 1) * GAP
	var view := get_viewport_rect().size
	var x := clampf(anchor.position.x - width / 2.0, MARGIN, view.x - MARGIN - width)
	var head := anchor.position.y - anchor.height() * anchor.scale.y
	_row_y = maxf(head - 6.0 - size.y, 28.0 + RAISE)
	for i in commands.size():
		var block := TextureRect.new()
		block.texture = block_tex
		block.position = Vector2(x + i * (size.x + GAP), _row_y)
		block.pivot_offset = size / 2.0
		block.mouse_filter = Control.MOUSE_FILTER_STOP
		block.gui_input.connect(_on_block_input.bind(i))
		var icon := TextureRect.new()
		icon.texture = load("res://assets/battle/icon_%s.png" % commands[i]["icon"])
		icon.position = ((size - icon.texture.get_size()) / 2.0).floor()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		block.add_child(icon)
		if not commands[i].get("enabled", true):
			var x_mark := TextureRect.new()
			x_mark.texture = ICON_X
			x_mark.position = size - ICON_X.get_size() - Vector2(1, 2)
			x_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			block.add_child(x_mark)
		add_child(block)
		_blocks.append(block)
		_current_lifts.append(0.0)
	_index = 0
	_touch_block = -1
	visible = true
	_active = false
	_refresh()
	# Wait a frame so the press that ended the last action doesn't also pick.
	await get_tree().process_frame
	_active = true
	var result: int = await chosen
	visible = false
	_active = false
	return result


func _is_enabled(i: int) -> bool:
	return _commands[i].get("enabled", true)


func _refresh() -> void:
	for i in _blocks.size():
		var b := _blocks[i]
		if i == _index:
			b.modulate = Color.WHITE
			var t := create_tween()
			t.tween_property(b, "scale", Vector2(1.12, 1.12), 0.06)
			t.tween_property(b, "scale", Vector2.ONE, 0.06)
		elif _is_enabled(i):
			b.modulate = Color(0.78, 0.78, 0.78)
			b.scale = Vector2.ONE
		else:
			b.modulate = Color(0.55, 0.55, 0.6)
			b.scale = Vector2.ONE
	var c: Dictionary = _commands[_index]
	_label.text = c["label"]
	_label.modulate = Color.WHITE if _is_enabled(_index) else Color(0.75, 0.75, 0.75)
	_label.reset_size()
	var sel := _blocks[_index]
	var view := get_viewport_rect().size
	_target_label_x = clampf(sel.position.x + sel.size.x / 2.0 - _label.size.x / 2.0, MARGIN, view.x - MARGIN - _label.size.x)
	_label.position.y = _row_y - RAISE - _label.size.y - 1.0
	if _label.position.x == 0.0:
		_label.position.x = _target_label_x
	highlighted.emit(c.get("info", ""))


func _process(delta: float) -> void:
	if not visible or _blocks.is_empty():
		return
	_time += delta

	# Smoothly slide the label above the active block
	if absf(_label.position.x - _target_label_x) > 0.5:
		_label.position.x = lerpf(_label.position.x, _target_label_x, clampf(24.0 * delta, 0.0, 1.0))

	# Smoothly interpolate block heights with gentle floating wave
	for i in _blocks.size():
		var target_lift := (RAISE + sin(_time * 6.0) * 1.5) if i == _index else 0.0
		_current_lifts[i] = lerpf(_current_lifts[i], target_lift, clampf(20.0 * delta, 0.0, 1.0))
		_blocks[i].position.y = _row_y - _current_lifts[i]


func _unhandled_input(event: InputEvent) -> void:
	if not _active or not visible:
		return
	if event.is_action_pressed("move_right") or event.is_action_pressed("move_down"):
		_move(1)
	elif event.is_action_pressed("move_left") or event.is_action_pressed("move_up"):
		_move(-1)
	elif event.is_action_pressed("action"):
		_pick(_index)
	else:
		return
	get_viewport().set_input_as_handled()


func _move(step: int) -> void:
	_highlight((_index + step + _commands.size()) % _commands.size())


func _highlight(i: int) -> void:
	if i != _index:
		_index = i
		_refresh()


func _on_block_input(event: InputEvent, i: int) -> void:
	if not _active:
		return
	if Pointer.is_hover(event):
		_highlight(i)
	elif event is InputEventScreenTouch:
		# Picks on lifting the finger, if it is still on the block it went down on.
		if event.pressed:
			_highlight(i)
			_touch_block = i
		elif _touch_block == i and Rect2(Vector2.ZERO, _blocks[i].size).has_point(event.position):
			_touch_block = -1
			_pick(i)
	elif Pointer.is_press(event):
		_highlight(i)
		_pick(i)
	else:
		return
	accept_event()


func _pick(i: int) -> void:
	if not _is_enabled(i):
		return
	_active = false
	# Punch bounce animation on confirmation!
	var sel := _blocks[i]
	var tw := create_tween()
	tw.tween_property(sel, "position:y", _row_y - RAISE - 7.0, 0.07)
	tw.tween_property(sel, "position:y", _row_y - RAISE, 0.07)
	await tw.finished
	chosen.emit(i)
