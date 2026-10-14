extends Control
## Title screen: Continue / New Game / Log In (an online save), then pick a
## side and a character.

@onready var menu: ChoiceMenu = $Menu
@onready var preview: CharacterSprite = $Preview
var prompt: TextPrompt
# Character select: the highlighted character's stats and signature move,
# in a balloon to the right of the list.
var card: PanelContainer
var card_special: Label
var card_stats: Label
var card_info: Label


func _ready() -> void:
	preview.visible = false
	prompt = TextPrompt.new()
	prompt.position = Vector2(110, 80)
	add_child(prompt)
	_build_card()
	TouchControls.active_changed.connect(_show_controls_hint)
	_show_controls_hint(TouchControls.active)
	get_tree().root.size_changed.connect(_layout_title)
	_layout_title()
	_main_menu()


func _show_controls_hint(touch: bool) -> void:
	$HintBox/Hint.text = "Tap to choose   Tap outside: back" if touch else "Arrows: choose   Z: confirm   X: back"
	$HintBox.reset_size()
	if is_node_ready():
		_layout_title()


func _layout_title() -> void:
	var vp := get_viewport_rect().size
	var safe := Game.get_safe_rect()
	var sky: TextureRect = $Sky
	sky.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.position = Vector2.ZERO
	sky.size = vp

	var logo: TextureRect = $Logo
	var mmo: Label = $MMO
	var logo_total_w := 275.0
	var logo_start_x := roundf(safe.position.x + (safe.size.x - logo_total_w) / 2.0)
	logo.position = Vector2(logo_start_x, safe.position.y + 8.0)
	mmo.position = Vector2(logo_start_x + 219.0, safe.position.y + 12.0)

	var hint_box: Control = $HintBox
	hint_box.position.x = roundf(safe.position.x + (safe.size.x - hint_box.size.x) / 2.0)
	hint_box.position.y = safe.end.y - hint_box.size.y - 2.0

	prompt.position = ((vp - prompt.size) / 2.0).round()

	if not preview.visible:
		menu.position = ((vp - menu.size) / 2.0).round()
		menu.position.y = maxf(safe.position.y + 60.0, menu.position.y)
	else:
		_layout_char_select()


func _layout_char_select() -> void:
	var safe := Game.get_safe_rect()
	var total_w := 270.0
	var start_x := roundf(safe.position.x + (safe.size.x - total_w) / 2.0)
	preview.position = Vector2(start_x + 24.0, safe.position.y + 144.0)
	menu.position = Vector2(start_x + 64.0, safe.position.y + 50.0)
	card.position = Vector2(start_x + 180.0, safe.position.y + 50.0)


func _build_card() -> void:
	card = PanelContainer.new()
	card.position = Vector2(250, 50)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	card.add_child(box)
	card_special = Label.new()
	card_special.theme_type_variation = &"TitleLabel"
	box.add_child(card_special)
	card_stats = Label.new()
	box.add_child(card_stats)
	card_info = Label.new()
	card_info.theme_type_variation = &"InfoLabel"
	card_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_info.custom_minimum_size.x = 112.0
	box.add_child(card_info)
	card.visible = false
	add_child(card)


func _main_menu() -> void:
	var options := ["New Game", "Log In"]
	var has_save := Game.load_save()
	if has_save:
		options.push_front("Continue (%s Lv %d)" % [Game.character_name(), Game.player["level"]])
	var i := await menu.choose(options)
	if options[i] == "New Game":
		_pick_side()
		return
	if options[i] == "Log In":
		_log_in(has_save)
		return
	# Saved online too: if another device played on since, carry on from there.
	if Cloud.linked():
		_note("Checking your online save...")
		await Cloud.pull_newer()
	# Saves from before usernames existed pick one now.
	if Game.player.get("username", "") == "":
		var u := await _ask_username(Game.character_name())
		if u == "":
			_main_menu()
			return
		Game.player["username"] = u
		Game.save()
	Game.continue_game()


## Log In: name and password, then the online save replaces this browser's.
func _log_in(has_save: bool) -> void:
	if has_save and not Cloud.linked():
		var c := await menu.choose(["Log in", "Back"], "This replaces %s Lv %d saved in this browser." % [
			Game.username(), Game.player["level"]], true)
		if c != 0:
			_main_menu()
			return
	var who := Game.clean_username(await prompt.ask("Username", "", 16, "The name you saved online with."))
	if who == "":
		_main_menu()
		return
	var password := await prompt.ask("Password", "", 64, "Enter: OK   Esc: back", true)
	if password == "":
		_main_menu()
		return
	_note("Logging in...")
	var err := await Cloud.login(who, password)
	_show_controls_hint(TouchControls.active)
	if err != "":
		await _show_message(Cloud.error_text(err))
		_main_menu()
		return
	Game.continue_game()


## A line of text in the menu balloon, until the player says OK.
func _show_message(text: String) -> void:
	await menu.choose(["OK"], text, true)


## Shows what the game is waiting on where the controls hint goes.
func _note(text: String) -> void:
	$HintBox/Hint.text = text
	$HintBox.reset_size()
	_layout_title()


## Returns a cleaned username, or "" if the player backed out.
func _ask_username(suggested: String) -> String:
	while true:
		var text := await prompt.ask("Pick a username", Game.clean_username(suggested), 16,
			"Other players see this name.")
		if text == "":
			return ""
		var u := Game.clean_username(text)
		if u != "":
			return u
		suggested = ""
	return ""


func _pick_side() -> void:
	var i := await menu.choose(["Good", "Evil"], "Choose your side", true, [], [
		"Explore, collect items, recruit partners and grow stronger. Start in Beanbean Castle Town.",
		"Recruit the enemies you meet and hunt good players. Start at Bowser's Castle.",
	])
	if i < 0:
		_main_menu()
		return
	_pick_character("good" if i == 0 else "evil")


## Each side's characters: the list in the middle, the walking preview on
## the left and the highlighted character's card on the right.
func _pick_character(side: String) -> void:
	var ids: Array = []
	var names: Array = []
	for id in Game.CHARACTERS:
		var c: Dictionary = Game.CHARACTERS[id]
		if c["side"] == side:
			ids.append(id)
			names.append(c["name"])
	preview.visible = true
	card.visible = true
	_show_character(ids[0])
	var watcher := func():
		var shown: String = ids[0]
		while preview.visible:
			var id: String = ids[clampi(menu._index, 0, ids.size() - 1)]
			if id != shown:
				shown = id
				_show_character(id)
			await get_tree().process_frame
	watcher.call()
	_layout_char_select()
	var i := await menu.choose(names, "Choose your character", true)
	preview.visible = false
	card.visible = false
	_layout_title()
	if i < 0:
		_pick_side()
		return
	var u := await _ask_username(names[i])
	if u == "":
		_pick_character(side)
		return
	Game.new_player(ids[i], u)
	Game.go_to_map(Game.HOME_MAP[side], "start")


func _show_character(id: String) -> void:
	var c: Dictionary = Game.CHARACTERS[id]
	preview.character_id = id
	# Big sheets (Grodus) are drawn smaller so they stay left of the list.
	var tex: Texture2D = load("res://assets/characters/%s.png" % id)
	var cell := Vector2(tex.get_width() / float(c["frames"]), tex.get_height() / 3.0)
	preview.scale = Vector2.ONE * clampf(minf(84.0 / cell.x, 92.0 / cell.y), 1.0, 2.0)
	var sp: Dictionary = Game.SPECIALS[c["special"]]
	card_special.text = sp["name"]
	card_stats.text = "HP %d  POW %d  DEF %d" % [c["hp"], c["pow"], c["def"]]
	card_info.text = sp["info"].replace("{a}", "A" if TouchControls.active else "Z")
	card.reset_size()


func _process(delta: float) -> void:
	if preview.visible:
		preview.move_velocity = Vector2(0, 1)
