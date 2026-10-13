class_name CommandBlocks
extends Control
## Superstar Saga style command blocks floating over whoever's turn it is.
## Left/Right (or Up/Down) to move, Z to pick. The mouse picks too: hovering a
## block highlights it, clicking or tapping it confirms.
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
var _index := 0
var _active := false
var _time := 0.0
var _row_y := 0.0
var _label: Label


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
		block.mouse_filter = Control.MOUSE_FILTER_STOP
		block.mouse_entered.connect(_on_hover.bind(i))
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
	_index = 0
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
		elif _is_enabled(i):
			b.modulate = Color(0.78, 0.78, 0.78)
		else:
			b.modulate = Color(0.55, 0.55, 0.6)
	var c: Dictionary = _commands[_index]
	_label.text = c["label"]
	_label.modulate = Color.WHITE if _is_enabled(_index) else Color(0.75, 0.75, 0.75)
	_label.reset_size()
	var sel := _blocks[_index]
	var view := get_viewport_rect().size
	_label.position = Vector2(
		clampf(sel.position.x + sel.size.x / 2.0 - _label.size.x / 2.0, MARGIN, view.x - MARGIN - _label.size.x),
		_row_y - RAISE - _label.size.y - 1.0)
	highlighted.emit(c.get("info", ""))


func _process(delta: float) -> void:
	if not visible or _blocks.is_empty():
		return
	_time += delta
	for i in _blocks.size():
		var lift := RAISE + roundf(sin(_time * 6.0) * 1.0) if i == _index else 0.0
		_blocks[i].position.y = _row_y - lift


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
	_index = (_index + step + _commands.size()) % _commands.size()
	_refresh()


func _on_hover(i: int) -> void:
	if _active and i != _index:
		_index = i
		_refresh()


func _on_block_input(event: InputEvent, i: int) -> void:
	if not _active:
		return
	if is_tap(event):
		if i != _index:
			_index = i
			_refresh()
		_pick(i)
		get_viewport().set_input_as_handled()


## A left click, or a tap (also when touch isn't turned into mouse clicks).
static func is_tap(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	return event is InputEventScreenTouch and event.pressed


func _pick(i: int) -> void:
	if not _is_enabled(i):
		return
	_active = false
	chosen.emit(i)
