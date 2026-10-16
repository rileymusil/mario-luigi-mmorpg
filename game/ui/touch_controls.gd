extends CanvasLayer
## On-screen controls for phones and tablets (autoload "TouchControls").
##
## A joystick on the left holds the move_* actions; A (action: jump, confirm,
## timed hits) and B (talk, back) sit on the right, styled like the
## Superstar Saga field icons; a MENU button opens the pause menu. They press
## the same input actions as the keyboard, so the game reads them with
## Input.is_action_* and _unhandled_input like any key.
##
## They show on touch screens (from the start, or after the first touch) and
## hide when a key or gamepad button is pressed. Which ones show depends on
## the scene: none on the title (tap the menus there), A and B in battle, all
## of them while walking around. Everything hides while a speech balloon or a
## text box is open (nodes in the "touch_blockers" group): tap anywhere to
## read on, tap an option to pick it.

signal active_changed(active: bool)

const A_ICON := preload("res://assets/ui/touch_a.png")
const B_ICON := preload("res://assets/ui/touch_b.png")
const ICON_SCALE := 1.5
const LAYER := 90  # above every scene's HUD and the map editor (50)

## True when playing by touch (the controls are on screen).
var active := false

var stick: TouchStick
var a_button: TouchButton
var b_button: TouchButton
var menu_button: TouchButton
var fullscreen_button: TouchButton

var _root: Control
var _can_fullscreen := false


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "Controls"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.modulate.a = 0.85
	add_child(_root)

	stick = TouchStick.new()
	a_button = TouchButton.new(&"action", A_ICON, ICON_SCALE, 24.0)
	b_button = TouchButton.new(&"talk", B_ICON, ICON_SCALE, 22.0)
	menu_button = _panel_button(&"menu", _label("MENU"))
	# Browsers only allow full screen from a tap; iPhones don't allow it at all
	# (Share > Add to Home Screen plays full screen there instead).
	_can_fullscreen = OS.has_feature("web") and not OS.has_feature("web_ios")
	fullscreen_button = _panel_button(&"", _fullscreen_icon())
	fullscreen_button.pressed_down.connect(_toggle_fullscreen)
	for c in [stick, a_button, b_button, menu_button, fullscreen_button]:
		c.visible = false
		_root.add_child(c)

	get_tree().root.size_changed.connect(_on_size_changed)

	_set_active(DisplayServer.is_touchscreen_available() or OS.has_feature("web_android") or OS.has_feature("web_ios"))


func _on_size_changed() -> void:
	var scene := get_tree().current_scene
	_layout(scene != null and scene.is_in_group(&"battles"))


func _panel_button(action: StringName, content: Control) -> TouchButton:
	var b := TouchButton.new(action)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"NavyPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(content)
	b.add_child(panel)
	return b


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"LightLabel"
	return l


func _fullscreen_icon() -> Control:
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(9, 12)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Four corner brackets.
	var bits := [Rect2(0, 2, 3, 1), Rect2(0, 2, 1, 3), Rect2(6, 2, 3, 1), Rect2(8, 2, 1, 3),
		Rect2(0, 10, 3, 1), Rect2(0, 8, 1, 3), Rect2(6, 10, 3, 1), Rect2(8, 8, 1, 3)]
	icon.draw.connect(func():
		for r in bits:
			icon.draw_rect(r, Color(0.97, 0.97, 0.97)))
	return icon


# --- Touch mode on and off ----------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_set_active(true)
	elif (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventJoypadButton and event.pressed):
		_set_active(false)


func _set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	if not on:
		release_all()
	active_changed.emit(on)


## Lets go of every held button and the joystick.
func release_all() -> void:
	for c in [stick, a_button, b_button, menu_button, fullscreen_button]:
		c.release()


func _notification(what: int) -> void:
	# Leaving the page or app drops every held key, so let go of ours too.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if stick:
			release_all()


# --- Every frame: which controls show, and where --------------------------------

func _process(delta: float) -> void:
	_root.visible = true
	var scene := get_tree().current_scene
	var path := scene.scene_file_path if scene else ""
	var blocked: bool = _any_visible(&"touch_blockers") or (scene != null and scene.get("editing") == true)
	var playing: bool = active and not blocked and path != Game.TITLE_SCENE
	var roaming: bool = playing and path == Game.WORLD_SCENE and not _any_visible(&"choice_menus")
	_show(a_button, playing)
	_show(b_button, playing)
	_show(stick, roaming)
	_show(menu_button, roaming)
	_show(fullscreen_button, _can_fullscreen and active and not blocked and (roaming or path == Game.TITLE_SCENE))
	_layout(scene != null and scene.is_in_group(&"battles"))  # battle.tscn and scenes built on it


func _show(c: Control, on: bool) -> void:
	if c.visible == on:
		return
	c.visible = on
	if not on:
		c.release()


func _any_visible(group: StringName) -> bool:
	for n in get_tree().get_nodes_in_group(group):
		if n is CanvasItem and n.is_visible_in_tree():
			return true
	return false


func _layout(battle := false) -> void:
	var safe := Game.get_safe_rect()
	stick.position = (Vector2(safe.position.x + 44, safe.end.y - 56) - stick.size / 2.0).round()
	if battle:
		if Game.is_portrait():
			# On portrait in battle, place within easy reach of right thumb
			a_button.position = (Vector2(safe.end.x - 30, safe.end.y - 72) - a_button.size / 2.0).round()
			b_button.position = (Vector2(safe.end.x - 70, safe.end.y - 46) - b_button.size / 2.0).round()
		else:
			# Battles (and duels): A over B on the right edge, under the foe list,
			# respecting safe area so notches don't cover them.
			a_button.position = (Vector2(safe.end.x - 24, safe.position.y + 96) - a_button.size / 2.0).round()
			b_button.position = (Vector2(safe.end.x - 24, safe.position.y + 146) - b_button.size / 2.0).round()
	else:
		# Clear of the bottom bars (hint, chat), respecting safe area margins.
		a_button.position = (Vector2(safe.end.x - 30, safe.end.y - 72) - a_button.size / 2.0).round()
		b_button.position = (Vector2(safe.end.x - 70, safe.end.y - 46) - b_button.size / 2.0).round()
	# MENU and full screen line up from the top-right corner; a hidden one
	# leaves no gap (the title shows full screen alone, in the corner).
	var x := safe.end.x - 4.0
	for b in [menu_button, fullscreen_button]:
		if not b.visible:
			continue
		var panel: Control = b.get_child(0)
		b.size = panel.get_combined_minimum_size()
		panel.size = b.size
		x -= b.size.x
		# Upright phones: the status bar fills the top row, so go under it.
		b.position = Vector2(x, safe.position.y + (24.0 if Game.is_portrait() and battle == false else 3.0))
		x -= 4.0


func _toggle_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)

