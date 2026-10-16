class_name ChatBox
extends CanvasLayer
## Text chat with the players on your map: a short log in the bottom-left
## corner and a text box opened with T (or /, or the Chat button).
## Commands: /p message (party), /w name message (whisper, any map), /r message
## (answer the last whisper), /friend name, /unfriend name, /friends,
## /mute name, /unmute name, /who, /help.
## Muted names and friends are kept in the save (Game.player["muted"],
## Game.player["friends"]).

signal message_shown(id: String, text: String)  # for speech bubbles

const MAX_LINES := 6
const FADE_AFTER := 12.0
const HELP := "/p: party chat   /w name: whisper   /r: answer   /friend name   /friends   /who   /mute name"
const WHISPER_COLOR := Color(1, 0.6, 0.95)
const MAX_FRIENDS := 50

var _log: VBoxContainer
var _prompt: TextPrompt
var _button: Button
var _lines: Array = []  # [{label, age}]
var _open_requested := false
## Lines survive map changes (each map makes a new ChatBox): [{text, color, at}]
static var _history: Array = []
static var _last_whisper := ""  # who whispered you last, for /r
var _asked_friends := false  # /friends is waiting for the server's answer


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
	var now := Time.get_ticks_msec() / 1000.0
	for h in _history.slice(-MAX_LINES):
		_add_line(h["text"], h["color"], false)
		_lines.back()["age"] = now - h["at"]
	Net.chat_received.connect(_on_chat)
	Net.player_arrived.connect(func(p):
		system("%s arrived." % p["name"] + (" (friend)" if is_friend(p["name"]) else "")))
	Net.whisper_received.connect(_on_whisper)
	Net.whisper_sent.connect(func(to, text): _add_line("[To %s] %s" % [to, text], WHISPER_COLOR))
	Net.whisper_failed.connect(func(to): system("%s isn't online right now." % to))
	Net.friends_status.connect(_on_friends_status)


func is_typing() -> bool:
	return _prompt.is_open()


## True once when the player asks to chat (key or button).
func wants_to_open() -> bool:
	var asked := _open_requested or Input.is_action_just_pressed("chat")
	_open_requested = false
	return asked and not is_typing()


## Opens the text box and sends what was typed. Await it.
func type_message(initial := "") -> void:
	_show_all()
	_button.visible = false
	var text := await _prompt.ask("", initial, 100, "Enter: send   Esc: close   /help")
	_button.visible = true
	if text == "":
		return
	if text.begins_with("/"):
		_command(text)
	elif not Net.send_chat(text):
		system("You're offline, so nobody can hear you.")


func system(text: String) -> void:
	_add_line(text, Color(1, 0.85, 0.2))


func _on_chat(id: String, who: String, text: String, party: bool) -> void:
	if is_muted(who):
		return
	if party:
		_add_line("[Party] %s: %s" % [who, text], Color(0.55, 1, 0.55))
	else:
		_add_line("%s: %s" % [who, text], Color.WHITE)
	message_shown.emit(id, text)


static func is_muted(who: String) -> bool:
	return who.to_lower() in Game.player.get("muted", [])


func _command(text: String) -> void:
	var parts := text.split(" ", false, 1)
	var arg := parts[1].strip_edges() if parts.size() > 1 else ""
	match parts[0].to_lower():
		"/p", "/party":
			if Net.party_id == "":
				system("You're not in a party. Walk up to someone and press X to team up.")
			elif not Net.party_here:
				system("%s isn't on this map right now." % Net.party_name)
			elif arg != "":
				Net.send_chat(arg, true)
		"/leave":
			if Net.party_id != "":
				system("You left the party with %s." % Net.party_name)
				Net.leave_party()
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
		"/w", "/whisper", "/msg", "/tell":
			var split := split_name(arg)
			if split[0] == "" or split[1] == "":
				system("Type /w, their name, then your message.")
			elif not Net.whisper(split[0], split[1]):
				system("You're offline, so nobody can hear you.")
		"/r", "/reply":
			if _last_whisper == "":
				system("Nobody has whispered you yet.")
			elif arg != "" and not Net.whisper(_last_whisper, arg):
				system("You're offline, so nobody can hear you.")
		"/friend", "/addfriend":
			if arg == "":
				system("Type /friend and their name.")
			else:
				system(add_friend(arg))
		"/unfriend":
			system(remove_friend(arg) if arg != "" else "Type /unfriend and their name.")
		"/friends":
			if friends().is_empty():
				system("No friends yet. /friend name, or walk up to someone and press X.")
			elif Net.request_friends(friends()):
				_asked_friends = true
			else:
				system("Friends: " + ", ".join(friends()) + " (you're offline)")
		"/who":
			if not Net.is_online():
				system("You're offline.")
				return
			var names := []
			for p in Net.players.values():
				names.append(p["name"] + (" (muted)" if is_muted(p["name"]) else ""))
			system("Here: you" + (", " + ", ".join(names) if not names.is_empty() else ". Nobody else yet."))
			if Net.party_id != "":
				system("Party: %s%s" % [Net.party_name, "" if Net.party_here else " (on another map)"])
		_:
			system(HELP)


func _on_whisper(from: String, text: String) -> void:
	if is_muted(from):
		return
	_last_whisper = from
	_add_line("[From %s] %s" % [from, text], WHISPER_COLOR)
	_show_all()


func _on_friends_status(online: Dictionary) -> void:
	if not _asked_friends:
		return  # the pause menu's Friends page asked
	_asked_friends = false
	var on: Array = []
	var off: Array = []
	for f in friends():
		var where = online.get(f.to_lower())
		if where == null:
			off.append(f)
		else:
			on.append("%s (%s)" % [f, Game.MAPS.get(where, {}).get("name", where)])
	system("Online: " + (", ".join(on) if not on.is_empty() else "nobody") +
		("   Offline: " + ", ".join(off) if not off.is_empty() else ""))


## Splits "Name message" into [name, message]. Names can have spaces, so a
## name you know (someone here, a friend, your last whisper) is matched
## first; otherwise the name is the first word.
static func split_name(arg: String) -> Array:
	var known: Array = friends().duplicate()
	if _last_whisper != "":
		known.append(_last_whisper)
	for p in Net.players.values():
		known.append(str(p["name"]))
	var best := ""
	for n in known:
		if arg.to_lower().begins_with(str(n).to_lower() + " ") and str(n).length() > best.length():
			best = str(n)
	if best != "":
		return [best, arg.substr(best.length() + 1).strip_edges()]
	var parts := arg.split(" ", false, 1)
	return [parts[0] if parts.size() > 0 else "", parts[1].strip_edges() if parts.size() > 1 else ""]


# --- Friends (names kept in the save) ---------------------------------------------

static func friends() -> Array:
	if typeof(Game.player.get("friends")) != TYPE_ARRAY:
		Game.player["friends"] = []
	return Game.player["friends"]


static func is_friend(who: String) -> bool:
	return friends().any(func(f): return str(f).to_lower() == who.to_lower())


## Adds a friend; returns what to tell the player.
static func add_friend(who: String) -> String:
	who = Game.clean_username(who)
	if who == "":
		return "That isn't a name anyone can have."
	if who.to_lower() == Game.username().to_lower():
		return "You're already your own best friend!"
	if is_friend(who):
		return "%s is already your friend." % who
	if friends().size() >= MAX_FRIENDS:
		return "Your friends list is full (%d). /unfriend someone first." % MAX_FRIENDS
	friends().append(who)
	Game.save()
	return "%s is your friend now. /friends shows who's online and where." % who


static func remove_friend(who: String) -> String:
	for f in friends():
		if str(f).to_lower() == who.strip_edges().to_lower():
			friends().erase(f)
			Game.save()
			return "%s isn't on your friends list anymore." % f
	return "%s isn't on your friends list." % who


func _add_line(text: String, color: Color, remember := true) -> void:
	if remember:
		_history.append({"text": text, "color": color, "at": Time.get_ticks_msec() / 1000.0})
		if _history.size() > MAX_LINES:
			_history.pop_front()
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
	var safe := Game.get_safe_rect()
	var touch: bool = TouchControls.stick.visible
	var left_x := safe.position.x + (88.0 if touch else 6.0)
	_log.position.x = left_x
	_log.size = _log.get_combined_minimum_size()

	_prompt.position = Vector2(left_x, safe.end.y - _prompt.size.y - 4.0)

	# On touch the Chat button sits under MENU (the top row has no room for it
	# beside the status bar on narrow screens) and only while you can walk,
	# like MENU; on keys it sits bottom right.
	if touch:
		var menu: Control = TouchControls.menu_button
		_button.position = Vector2(menu.position.x + menu.size.x - _button.size.x, menu.position.y + menu.size.y + 3.0)
	elif Game.is_portrait():  # above the hint bar, which is as wide as the screen
		_button.position = Vector2(safe.end.x - _button.size.x - 4.0, safe.end.y - _button.size.y - 22.0)
	else:
		_button.position = Vector2(safe.end.x - _button.size.x - 6.0, safe.end.y - _button.size.y - 4.0)
	_button.visible = not is_typing() and (touch or not TouchControls.active) and not _text_box_open()

	# Keep the log's bottom edge just above the text box or hint bar
	var base_bottom := (_prompt.position.y - 2.0) if is_typing() else (safe.end.y - 24.0)
	_log.position.y = base_bottom - _log.size.y

	for line in _lines:
		line["label"].custom_minimum_size.x = clampf(safe.size.x - 140.0, 180.0, 320.0) if touch else clampf(safe.size.x - 40.0, 220.0, 360.0)
		line["age"] += delta
		var a: float = 1.0 if is_typing() else clampf((FADE_AFTER + 1.0 - line["age"]), 0.0, 1.0)
		line["label"].modulate.a = a


## A speech balloon or text box is up (they cover the bottom of the screen).
func _text_box_open() -> bool:
	for n in get_tree().get_nodes_in_group(&"touch_blockers"):
		if n is CanvasItem and n.is_visible_in_tree():
			return true
	return false
