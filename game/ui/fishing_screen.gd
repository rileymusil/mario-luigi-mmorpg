class_name FishingScreen
extends Control
## One cast of the fishing minigame (the fisher Toad on the Outskirts Pier):
## the float bobs until a fish bites ("!"), then press Z (or tap) to reel in.
## Too early or too late and it gets away.
##     var reel := await fishing_screen.cast()   # seconds to react, or -1

signal _done(reel: float)

const BITE_WINDOW := 0.9   # seconds you have to reel in once it bites
const WAIT_MIN := 1.5
const WAIT_MAX := 4.5

var _panel: PanelContainer
var _water: Control
var _hint: Label
var _bite: Label
var _state := ""           # "wait", "bite" or ""
var _time := 0.0
var _bite_at := 0.0
var _float_pos := Vector2.ZERO


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(&"touch_blockers")
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"NavyPanel"
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_panel.add_child(box)
	_water = Control.new()
	_water.custom_minimum_size = Vector2(160, 70)
	_water.draw.connect(_draw_water)
	box.add_child(_water)
	_bite = Label.new()
	_bite.theme_type_variation = &"LightLabel"
	_bite.text = "!"
	_bite.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	_bite.visible = false
	_bite.scale = Vector2(2, 2)
	_water.add_child(_bite)
	_hint = Label.new()
	_hint.theme_type_variation = &"LightLabel"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_hint)


## Plays one cast and returns how fast you reeled in after the bite, or -1.
func cast() -> float:
	visible = true
	_state = "wait"
	_time = 0.0
	_bite_at = randf_range(WAIT_MIN, WAIT_MAX)
	_bite.visible = false
	_hint.text = "Wait for a bite... then press Z!"
	_center.call_deferred()
	var reel: float = await _done
	_state = ""
	await get_tree().create_timer(0.6).timeout
	visible = false
	return reel


func _process(delta: float) -> void:
	if _state == "":
		return
	_time += delta
	if _state == "wait" and _time >= _bite_at:
		_state = "bite"
		_bite.visible = true
		_hint.text = "A bite! Reel it in!"
	elif _state == "bite" and _time - _bite_at > BITE_WINDOW:
		_finish(-1.0, "Too slow...")
	_water.queue_redraw()


func _draw_water() -> void:
	var size := _water.size
	_water.draw_rect(Rect2(Vector2.ZERO, size), Color(0.25, 0.55, 0.85))
	for i in 4:  # ripples
		var y := 12.0 + i * 16.0
		var x := fmod(_time * 12.0 + i * 37.0, size.x + 20.0) - 10.0
		_water.draw_line(Vector2(x, y), Vector2(x + 14, y), Color(0.6, 0.85, 1, 0.7), 1.0)
	var bob := sin(_time * 3.0) * 1.5
	if _state == "bite":
		bob = 4.0 + sin(_time * 30.0) * 2.0  # pulled under
	_float_pos = Vector2(size.x * 0.6, size.y * 0.55 + bob)
	_water.draw_line(Vector2(size.x * 0.1, 0), _float_pos, Color(0.95, 0.95, 0.95, 0.8), 1.0)
	_water.draw_circle(_float_pos, 4.0, Color(0.95, 0.2, 0.2))
	_water.draw_circle(_float_pos + Vector2(0, -2), 2.0, Color(1, 1, 1))
	_bite.position = _float_pos + Vector2(-5, -40)


func _finish(reel: float, text: String) -> void:
	if _state == "":
		return
	_state = ""
	_bite.visible = false
	_hint.text = text
	_done.emit(reel)


func _press() -> void:
	if _state == "wait":
		_finish(-1.0, "Too soon! It swam off.")
	elif _state == "bite":
		_finish(_time - _bite_at, "Got it!")


func _center() -> void:
	_panel.reset_size()
	_panel.position = ((get_viewport_rect().size - _panel.size) / 2.0).round()


func _gui_input(event: InputEvent) -> void:
	if Pointer.is_press(event):
		_press()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if _state != "" and event.is_action_pressed("action"):
		_press()
		get_viewport().set_input_as_handled()
