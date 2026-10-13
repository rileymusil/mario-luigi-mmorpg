class_name TextPrompt
extends PanelContainer
## A one-line text box in a speech balloon, for usernames and chat.
##     var text: String = await prompt.ask("Pick a username", "Mario", 16)
## Enter confirms, Escape cancels (returns ""). Works with on-screen
## keyboards on phones because it is a real LineEdit.

signal _done(text: String)

var _title: Label
var _edit: LineEdit
var _hint: Label


func _init() -> void:
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
	_hint = Label.new()
	_hint.theme_type_variation = &"InfoLabel"
	box.add_child(_hint)
	visible = false


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
	_edit.grab_focus()
	_edit.caret_column = initial.length()
	var text: String = await _done
	visible = false
	_edit.release_focus()
	# Let the Enter / Escape key press finish before the game reads input again.
	await get_tree().process_frame
	return text


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_done.emit("")
