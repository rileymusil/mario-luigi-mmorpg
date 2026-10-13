class_name TouchStick
extends Control
## On-screen joystick for touch screens. Dragging the knob holds the move_*
## actions eight ways, like the Game Boy Advance D-pad, so walking (and
## Up / Down in menus) works exactly as with the arrow keys.

const BASE := preload("res://assets/ui/touch_stick_base.png")
const KNOB := preload("res://assets/ui/touch_stick_knob.png")
const DIRECTIONS := {
	&"move_left": Vector2.LEFT, &"move_right": Vector2.RIGHT,
	&"move_up": Vector2.UP, &"move_down": Vector2.DOWN,
}
## How far along a direction (0 to 1 of the knob's reach) the knob must go to
## hold it, and how far back before it lets go (so it doesn't flicker).
const HOLD_AT := 0.4
const LET_GO_AT := 0.28

## How far the knob travels from the middle, and the touch area's radius.
var reach := 20.0
var touch_radius := 46.0

var _finger := TouchButton.NONE
var _knob := Vector2.ZERO
var _target_knob := Vector2.ZERO
var _held := {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2.ONE * touch_radius * 2.0


func _process(delta: float) -> void:
	# Smooth elastic spring return when released or moving
	if _knob.distance_squared_to(_target_knob) > 0.04:
		_knob = _knob.lerp(_target_knob, clampf(26.0 * delta, 0.0, 1.0))
		queue_redraw()


func _has_point(point: Vector2) -> bool:
	return point.distance_to(size / 2.0) <= touch_radius


func is_held() -> bool:
	return _finger != TouchButton.NONE


## Which move_* actions it is holding right now.
func held_actions() -> Array:
	return _held.keys().filter(func(a): return _held[a])


func _gui_input(event: InputEvent) -> void:
	var real_mouse: bool = event is InputEventMouse and event.device != InputEvent.DEVICE_ID_EMULATION
	if event is InputEventScreenTouch:
		if event.pressed:
			_finger = event.index
			_aim(event.position)
		elif event.index == _finger:
			release()
	elif event is InputEventScreenDrag:
		if event.index == _finger:
			_aim(event.position)
	elif real_mouse and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_finger = TouchButton.MOUSE
			_aim(event.position)
		elif _finger == TouchButton.MOUSE:
			release()
	elif real_mouse and event is InputEventMouseMotion and _finger == TouchButton.MOUSE:
		_aim(event.position)
	else:
		return
	accept_event()


func _aim(local: Vector2) -> void:
	_target_knob = (local - size / 2.0).limit_length(reach)
	var v := _target_knob / reach
	for action in DIRECTIONS:
		var amount: float = v.dot(DIRECTIONS[action])
		_hold(action, amount > (LET_GO_AT if _held.get(action, false) else HOLD_AT))
	queue_redraw()


func _hold(action: StringName, on: bool) -> void:
	if on == _held.get(action, false):
		return
	_held[action] = on
	Pointer.send_action(action, on)


## Lets go of everything and smoothly returns the knob.
func release() -> void:
	_finger = TouchButton.NONE
	_target_knob = Vector2.ZERO
	for action in _held.keys():
		_hold(action, false)
	queue_redraw()


func _draw() -> void:
	var middle := size / 2.0
	# Subtle translucent halo when finger touches the stick
	if is_held():
		draw_circle(middle, touch_radius * 0.9, Color(1, 1, 1, 0.08))
		draw_arc(middle, reach + 6.0, 0, TAU, 32, Color(1, 0.85, 0.3, 0.35), 1.5)
	draw_texture(BASE, (middle - BASE.get_size() / 2.0).round())
	draw_texture(KNOB, (middle + _knob - KNOB.get_size() / 2.0).round())
