class_name Pointer
## Helpers that treat a mouse click and a tap on a touch screen the same way.
##
## Godot also turns the first finger on the screen into emulated mouse events
## (project setting input_devices/pointing/emulate_mouse_from_touch). Those
## are skipped here, so one tap counts once: as its InputEventScreenTouch.


## A left click or a finger touching down.
static func is_press(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return event.pressed
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
		and event.device != InputEvent.DEVICE_ID_EMULATION


## A right click: "back" in menus.
static func is_back(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT \
		and event.device != InputEvent.DEVICE_ID_EMULATION


## The real mouse moving (not a finger, and not the still "motion" Godot sends
## when something new appears under a mouse that hasn't moved).
static func is_hover(event: InputEvent) -> bool:
	return event is InputEventMouseMotion and event.relative != Vector2.ZERO


## Presses or releases an input action as if its key went down or up, so
## both Input.is_action_just_pressed() and _unhandled_input() see it.
static func send_action(action: StringName, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


## Presses and lets go of an action straight away (a tap on it).
static func tap_action(action: StringName) -> void:
	send_action(action, true)
	send_action(action, false)
