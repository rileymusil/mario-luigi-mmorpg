extends Control
## Title screen: Continue / New Game, then pick a side and a character.

@onready var menu: ChoiceMenu = $Menu
@onready var preview: CharacterSprite = $Preview
@onready var subtitle: Label = $Subtitle


func _ready() -> void:
	preview.visible = false
	_main_menu()


func _main_menu() -> void:
	var options := ["New Game"]
	if Game.load_save():
		options.push_front("Continue (%s Lv %d)" % [Game.character_name(), Game.player["level"]])
	var i := await menu.choose(options)
	if options[i] == "New Game":
		_pick_side()
	else:
		Game.continue_game()


func _pick_side() -> void:
	subtitle.text = "Choose your side"
	var i := await menu.choose(["Good", "Evil"], "", true, [], [
		"Explore, collect items, recruit partners and grow stronger. Start in Beanbean Castle Town.",
		"Recruit the enemies you meet and hunt good players. Start at Bowser's Castle.",
	])
	if i < 0:
		subtitle.text = ""
		_main_menu()
		return
	_pick_character("good" if i == 0 else "evil")


func _pick_character(side: String) -> void:
	subtitle.text = "Choose your character"
	var ids: Array = []
	var names: Array = []
	var infos: Array = []
	for id in Game.CHARACTERS:
		var c: Dictionary = Game.CHARACTERS[id]
		if c["side"] == side:
			ids.append(id)
			names.append(c["name"])
			var sp: Dictionary = Game.SPECIALS[c["special"]]
			infos.append("HP %d  POW %d  DEF %d\n%s: %s" % [c["hp"], c["pow"], c["def"], sp["name"], sp["info"]])
	preview.visible = true
	preview.character_id = ids[0]
	var watcher := func():
		while menu.visible:
			preview.character_id = ids[menu._index]
			await get_tree().process_frame
	watcher.call()
	var i := await menu.choose(names, "", true, [], infos)
	preview.visible = false
	if i < 0:
		_pick_side()
		return
	Game.new_player(ids[i])
	Game.go_to_map(Game.HOME_MAP[side], "start")


func _process(delta: float) -> void:
	if preview.visible:
		preview.move_velocity = Vector2(0, 1)
