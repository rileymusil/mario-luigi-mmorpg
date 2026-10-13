class_name TextPrompt
extends PanelContainer
## A one-line text box in a speech balloon, for usernames and chat.
##     var text: String = await prompt.ask("Pick a username", "Mario", 16)
## Enter or the OK button confirms; Escape, the Back button or a right click
## cancels (returns ""). Playing by touch in a browser, it asks with the
## browser's own text box instead (window.prompt), which always brings up the
## phone's keyboard: Godot's web keyboard support can't open it on iPhones,
## because Godot only focuses its hidden text field after the tap is over.

signal _done(text: String)

var _title: Label
var _edit: LineEdit
var _hint: Label


func _init() -> void:
	# The touch screen buttons step aside while it is open.
	add_to_group(&"touch_blockers")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	box.add_child(_title)
	_edit = LineEdit.new()
	_edit.custom_minimum_size = Vector2(150, 0)
	_edit.select_all_on_focus = true
	_edit.text_submitted.connect(func(t: String): _done.emit(t.strip_edges()))
	box.add_child(_edit)
	# The hint shares its row with OK and Back buttons for the mouse.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	box.add_child(row)
	_hint = Label.new()
	_hint.theme_type_variation = &"InfoLabel"
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_hint)
	row.add_child(_button("OK", func(): _done.emit(_edit.text.strip_edges())))
	row.add_child(_button("Back", func(): _done.emit("")))
	visible = false


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # typing stays in the text box
	b.pressed.connect(on_press)
	return b


func is_open() -> bool:
	return visible


## Shows the box and waits. Returns the trimmed text, or "" if cancelled.
func ask(title: String, initial := "", max_length := 16, hint := "Enter: OK   Esc: cancel") -> String:
	_title.text = title
	_title.visible = title != ""
	_hint.text = hint
	_edit.max_length = max_length
	_edit.text = initial
	visible = true
	# Stay on screen however long the hint is.
	reset_size()
	var vp := get_viewport_rect().size
	position.x = clampf(position.x, 4.0, maxf(4.0, vp.x - size.x - 4.0))
	position.y = clampf(position.y, 2.0, maxf(2.0, vp.y - size.y - 2.0))
	if _use_browser_box():
		_ask_browser.call_deferred(title, initial, max_length)
	else:
		_edit.grab_focus()
		_edit.caret_column = initial.length()
	var text: String = await _done
	visible = false
	_edit.release_focus()
	# Enter and Escape are also game keys (menu); wait until they're let go so
	# the same press doesn't open the pause menu or pick a menu option.
	while Input.is_action_pressed("menu") or Input.is_action_pressed("action"):
		await get_tree().process_frame
	await get_tree().process_frame
	return text


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) or Pointer.is_back(event):
		get_viewport().set_input_as_handled()
		_done.emit("")


func _use_browser_box() -> bool:
	return OS.has_feature("web") and TouchControls.active


## The JavaScript that asks for the text with the browser's own box.
static func browser_prompt_js(title: String, initial: String) -> String:
	return "window.prompt(%s, %s)" % [JSON.stringify(title), JSON.stringify(initial)]


func _ask_browser(title: String, initial: String, max_length: int) -> void:
	# Let the balloon show behind the browser's box first.
	await get_tree().process_frame
	if not visible:
		return  # closed in the meantime
	var asked_at := Time.get_ticks_msec()
	var answer: Variant = JavaScriptBridge.eval(browser_prompt_js(title if title != "" else "Type a message", initial), true)
	if answer == null and Time.get_ticks_msec() - asked_at < 150:
		# No box came up (some pages that embed the game block it): type here instead.
		_edit.grab_focus()
		return
	# null: the player pressed Cancel.
	var text := "" if answer == null else str(answer).strip_edges().left(max_length)
	_edit.text = text
	_done.emit(text)
