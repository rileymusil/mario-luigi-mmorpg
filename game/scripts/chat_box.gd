class_name ChatBox
extends CanvasLayer
## Text chat with the players on your map: a short log in the bottom-left
## corner and a text box opened with T (or /, or the Chat button).
## Commands: /mute name, /unmute name, /who, /help.
## Muted names are kept in the save (Game.player["muted"]).

signal message_shown(id: String, text: String)  # for speech bubbles

const MAX_LINES := 6
const FADE_AFTER := 12.0
const HELP := "T: chat   /who: who's here   /mute name   /unmute name"

var _log: VBoxContainer
var _prompt: TextPrompt
var _button: Button
var _lines: Array = []  # [{label, age}]
var _open_requested := false


func _ready() -> void:
	layer = 5
	_log = VBoxContainer.new()
	_log.add_theme_constant_override("separation", 0)
	_log.position = Vector2(6, 112)
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_log)
	_prompt = TextPrompt.new()
	_prompt.position = Vector2(6, 158)
	add_child(_prompt)
	_button = Button.new()
	_button.text = "Chat"
	_button.focus_mode = Control.FOCUS_NONE
	_button.position = Vector2(340, 178)
	_button.pressed.connect(func(): _open_requested = true)
	add_child(_button)
	Net.chat_received.connect(_on_chat)
	Net.player_arrived.connect(func(p): system("%s arrived." % p["name"]))


func is_typing() -> bool:
	return _prompt.is_open()


## True once when the player asks to chat (key or button).
func wants_to_open() -> bool:
	var asked := _open_requested or Input.is_action_just_pressed("chat")
	_open_requested = false
	return asked and not is_typing()


## Opens the text box and sends what was typed. Await it.
func type_message() -> void:
	_show_all()
	_button.visible = false
	var text := await _prompt.ask("", "", 80, "Enter: send   Esc: close   /help")
	_button.visible = true
	if text == "":
		return
	if text.begins_with("/"):
		_command(text)
	elif not Net.send_chat(text):
		system("You're offline, so nobody can hear you.")


func system(text: String) -> void:
	_add_line(text, Color(1, 0.85, 0.2))


func _on_chat(id: String, who: String, text: String) -> void:
	if is_muted(who):
		return
	_add_line("%s: %s" % [who, text], Color.WHITE)
	message_shown.emit(id, text)


static func is_muted(who: String) -> bool:
	return who.to_lower() in Game.player.get("muted", [])


func _command(text: String) -> void:
	var parts := text.split(" ", false, 1)
	var arg := parts[1].strip_edges() if parts.size() > 1 else ""
	match parts[0].to_lower():
		"/mute":
			if arg == "":
				system("Type /mute and their name.")
				return
			var muted: Array = Game.player.get("muted", [])
			if not arg.to_lower() in muted:
				muted.append(arg.to_lower())
			Game.player["muted"] = muted
			Game.save()
			system("Muted %s. /unmute %s to undo." % [arg, arg])
		"/unmute":
			var muted: Array = Game.player.get("muted", [])
			muted.erase(arg.to_lower())
			Game.player["muted"] = muted
			Game.save()
			system("Unmuted %s." % arg)
		"/who":
			if not Net.is_online():
				system("You're offline.")
				return
			var names := []
			for p in Net.players.values():
				names.append(p["name"] + (" (muted)" if is_muted(p["name"]) else ""))
			system("Here: you" + (", " + ", ".join(names) if not names.is_empty() else ". Nobody else yet."))
		_:
			system(HELP)


func _add_line(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"OutlineLabel"
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 250
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_child(l)
	_lines.append({"label": l, "age": 0.0})
	while _lines.size() > MAX_LINES:
		_lines.pop_front()["label"].queue_free()


func _show_all() -> void:
	for line in _lines:
		line["age"] = 0.0


func _process(delta: float) -> void:
	# Keep the log's bottom edge just above the hint bar (or the text box).
	_log.size = _log.get_combined_minimum_size()
	_log.position.y = (156.0 if is_typing() else 186.0) - _log.size.y
	for line in _lines:
		line["age"] += delta
		var a: float = 1.0 if is_typing() else clampf((FADE_AFTER + 1.0 - line["age"]), 0.0, 1.0)
		line["label"].modulate.a = a
