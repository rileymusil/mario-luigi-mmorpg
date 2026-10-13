class_name TouchButton
extends Control
## An on-screen button for touch screens. While a finger (or the mouse) is on
## it, it holds `action` down exactly as its key would; several buttons can be
## held at once with several fingers. Draws `texture` centred (scaled by
## `art_scale`) and nudges it down while held; children (a label in a panel)
## draw on top. `radius` > 0 gives it a round touch area of that size.

## Sent when it goes down, for buttons that do something besides an action.
signal pressed_down

const NONE := -100
const MOUSE := -1  # finger indexes from the screen are 0 and up

var action := &""
var texture: Texture2D
var art_scale := 1.0
var radius := 0.0
var held := false

var _finger := NONE


func _init(p_action: StringName = &"", p_texture: Texture2D = null, p_scale := 1.0, p_radius := 0.0) -> void:
	action = p_action
	texture = p_texture
	art_scale = p_scale
	radius = p_radius
	mouse_filter = Control.MOUSE_FILTER_STOP
	if radius > 0.0:
		size = Vector2.ONE * radius * 2.0
	elif texture:
		size = texture.get_size() * art_scale


func _has_point(point: Vector2) -> bool:
	if radius > 0.0:
		return point.distance_to(size / 2.0) <= radius
	return Rect2(Vector2.ZERO, size).has_point(point)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.index)
		elif event.index == _finger:
			release()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.pressed:
			_press(MOUSE)
		elif _finger == MOUSE:
			release()
		accept_event()


func _press(finger: int) -> void:
	# A second press without a release (a lost touch end) lets go first, so
	# the action still counts as "just pressed".
	release()
	_finger = finger
	held = true
	if action != &"":
		Pointer.send_action(action, true)
	pressed_down.emit()
	queue_redraw()


## Lets go (also used when the button hides while held).
func release() -> void:
	if not held:
		return
	held = false
	_finger = NONE
	if action != &"":
		Pointer.send_action(action, false)
	queue_redraw()


func _draw() -> void:
	if texture == null:
		return
	var s := texture.get_size() * art_scale
	var at := ((size - s) / 2.0).round() + (Vector2(0, 1) if held else Vector2.ZERO)
	draw_texture_rect(texture, Rect2(at, s), false, Color(0.78, 0.78, 0.78) if held else Color.WHITE)
