class_name LeadersScreen
extends Control
## The leaderboards (pause menu > Leaders): the top 10 players by level, PvP
## wins and boss wins, and the bounties, from the server (Cloud.leaders).
## Left/Right or the arrow buttons switch boards; X, Enter or Close shuts it.
## Also shows any other list in pages (the achievements, see show_pages).
##     await leaders_screen.show_boards()

signal closed

const BOARDS := [
	{"key": "level", "title": "Top levels", "value": "Lv %d"},
	{"key": "pvp", "title": "PvP wins", "value": "%d wins"},
	{"key": "bosses", "title": "Bosses beaten", "value": "%d bosses"},
	{"key": "bounties", "field": "bounty", "title": "Bounties", "value": "%d coins",
		"note": "Beat them in a duel to collect.", "empty": "No bounties right now."},
]
const ROWS := 10
const GOOD_COLOR := Color(0.55, 0.8, 1)
const EVIL_COLOR := Color(1, 0.55, 0.5)

var _board := 0
var _data: Dictionary = {}
var _pages: Array = []
var _panel: PanelContainer
var _title: Label
var _rows: Array[Label] = []
var _values: Array[Label] = []
var _note: Label
var _open := false


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # taps outside the panel close it
	add_to_group(&"touch_blockers")
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0.08, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"NavyPanel"
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	_panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	box.add_child(head)
	head.add_child(_button("<", func(): _switch(-1)))
	_title = _label("", &"LightLabel")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	head.add_child(_button(">", func(): _switch(1)))
	for i in ROWS:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(196, 0)
		box.add_child(row)
		var name_label := _label("", &"LightLabel")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		row.add_child(name_label)
		var value := _label("", &"LightLabel")
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)
		_rows.append(name_label)
		_values.append(value)
	_note = _label("", &"LightLabel")
	_note.modulate = Color(1, 1, 1, 0.7)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_note)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(foot)
	foot.add_child(_button("Close", close))


func _label(text: String, variation: StringName) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(pressed)
	return b


## Opens the boards and waits until they're closed.
func show_boards() -> void:
	_open = true
	visible = true
	_board = 0
	_data = {}
	_pages = _leader_pages("Loading...")
	_draw_board()
	_data = await Cloud.leaders()
	if not _open:
		return
	_pages = _leader_pages("" if not _data.is_empty() else "Couldn't reach the server. Try again in a bit.")
	_draw_board()
	await closed


## Shows your own pages (the achievements list) the same way and waits until
## they're closed. Each page: {title, rows: [[text, value, color]], note}.
func show_pages(pages: Array) -> void:
	_open = true
	visible = true
	_board = 0
	_pages = pages
	_draw_board()
	await closed


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	closed.emit()


func _switch(step: int) -> void:
	_board = posmod(_board + step, maxi(1, _pages.size()))
	_draw_board()


## The server's boards as pages; `note` replaces the usual footer when set.
func _leader_pages(note: String) -> Array:
	var pages: Array = []
	var me := Game.username().to_lower()
	for b in BOARDS:
		var list: Array = _data.get(b["key"], []) if typeof(_data.get(b["key"])) == TYPE_ARRAY else []
		var rows: Array = []
		for i in mini(ROWS, list.size()):
			var e: Dictionary = list[i]
			var who := str(e.get("name", "?"))
			var character: String = Game.CHARACTERS.get(str(e.get("character", "")), {}).get("name", "")
			var color := GOOD_COLOR if str(e.get("side", "good")) == "good" else EVIL_COLOR
			if who.to_lower() == me:
				color = Color(1, 0.9, 0.3)
			rows.append(["%d. %s" % [i + 1, who] + (" (%s)" % character if character != "" else ""),
				b["value"] % int(e.get(b.get("field", b["key"]), 0)), color])
		var page_note := note
		if page_note == "":
			page_note = b.get("empty", "Nobody yet. Be the first!") if rows.is_empty() else b.get("note", "Blue: good   Red: evil   Yellow: you")
		pages.append({"title": b["title"], "rows": rows, "note": page_note})
	return pages


func _draw_board() -> void:
	if _pages.is_empty():
		return
	var page: Dictionary = _pages[_board]
	_title.text = "%s  (%d/%d)" % [page["title"], _board + 1, _pages.size()] if _pages.size() > 1 else str(page["title"])
	var rows: Array = page.get("rows", [])
	for i in ROWS:
		if i < rows.size():
			_rows[i].text = str(rows[i][0])
			_values[i].text = str(rows[i][1])
			_rows[i].add_theme_color_override("font_color", rows[i][2])
			_values[i].add_theme_color_override("font_color", rows[i][2])
		else:
			_rows[i].text = ""
			_values[i].text = ""
	_note.text = str(page.get("note", ""))
	_center.call_deferred()


func _center() -> void:
	_panel.reset_size()
	_panel.position = ((get_viewport_rect().size - _panel.size) / 2.0).round()


func _gui_input(event: InputEvent) -> void:
	# A click or tap outside the panel closes the boards.
	if event is InputEventMouseButton and event.pressed and not _panel.get_global_rect().has_point(event.global_position):
		close()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("move_left"):
		_switch(-1)
	elif event.is_action_pressed("move_right") or event.is_action_pressed("action"):
		_switch(1)
	elif event.is_action_pressed("talk") or event.is_action_pressed("menu"):
		close()
	else:
		return
	get_viewport().set_input_as_handled()
