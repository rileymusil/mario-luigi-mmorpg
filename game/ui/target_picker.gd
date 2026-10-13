class_name TargetPicker
extends Control
## Points at a battle target with the bobbing yellow pointer. Arrows move, Z
## picks, X backs out (returns -1). Hovering a character with the mouse
## points at it, clicking or tapping it picks it.
##     var i: int = await picker.choose([{"node": sprite, "label": "Goomba"}, ...])

signal chosen(index: int)

const CURSOR := preload("res://assets/ui/cursor.png")
const MARGIN := 4.0

var _targets: Array = []
var _hits: Array[Control] = []
var _index := 0
var _active := false
var _cancellable := true
var _time := 0.0
var _pointer: Sprite2D
var _label: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer = Sprite2D.new()
	_pointer.texture = CURSOR
	_pointer.rotation = PI / 2.0  # the menu pointer, turned to point down
	add_child(_pointer)
	_label = Label.new()
	_label.theme_type_variation = &"OutlineLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	visible = false


## targets: Array of {node: CharacterSprite, label: String}.
func choose(targets: Array, cancellable := true) -> int:
	_targets = targets
	for h in _hits:
		h.queue_free()
	_hits.clear()
	for i in targets.size():
		var node: CharacterSprite = targets[i]["node"]
		var h := node.height() * node.scale.y
		var w := maxf(24.0, h * 0.75)
		var hit := Control.new()
		hit.position = node.position - Vector2(w / 2.0, h)
		hit.size = Vector2(w, h + 4.0)
		hit.mouse_filter = Control.MOUSE_FILTER_STOP
		hit.mouse_entered.connect(_on_hover.bind(i))
		hit.gui_input.connect(_on_hit_input.bind(i))
		add_child(hit)
		_hits.append(hit)
	_index = 0
	_cancellable = cancellable
	visible = true
	_active = false
	_refresh()
	await get_tree().process_frame
	_active = true
	var result: int = await chosen
	visible = false
	_active = false
	return result


func _refresh() -> void:
	_label.text = _targets[_index]["label"]
	_label.reset_size()
	_place()


func _place() -> void:
	var node: CharacterSprite = _targets[_index]["node"]
	var top := node.position + Vector2(0, -node.height() * node.scale.y - 2.0)
	var bob := roundf(sin(_time * 7.0) * 1.5)
	_pointer.position = top + Vector2(0, -7.0 + bob)
	var view := get_viewport_rect().size
	_label.position = Vector2(
		clampf(top.x - _label.size.x / 2.0, MARGIN, view.x - MARGIN - _label.size.x),
		top.y - 14.0 - _label.size.y)


func _process(delta: float) -> void:
	if not visible or _targets.is_empty():
		return
	_time += delta
	_place()


func _unhandled_input(event: InputEvent) -> void:
	if not _active or not visible:
		return
	if event.is_action_pressed("move_right") or event.is_action_pressed("move_down"):
		_move(1)
	elif event.is_action_pressed("move_left") or event.is_action_pressed("move_up"):
		_move(-1)
	elif event.is_action_pressed("action"):
		_pick(_index)
	elif event.is_action_pressed("talk") and _cancellable:
		_pick(-1)
	else:
		return
	get_viewport().set_input_as_handled()


func _move(step: int) -> void:
	_index = (_index + step + _targets.size()) % _targets.size()
	_refresh()


func _on_hover(i: int) -> void:
	if _active and i != _index:
		_index = i
		_refresh()


func _on_hit_input(event: InputEvent, i: int) -> void:
	if not _active:
		return
	if CommandBlocks.is_tap(event):
		_index = i
		_refresh()
		_pick(i)
		get_viewport().set_input_as_handled()


func _pick(i: int) -> void:
	_active = false
	chosen.emit(i)
