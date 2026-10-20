class_name PlayerLookupScreen
extends Control
## Player Directory & Lookup Screen: allows searching any player, viewing nearby players,
## sending direct trade requests, private messages (whispers), and party invites.

signal closed

@onready var dim: ColorRect = $Dim
@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/VBox/Header/Title
@onready var tab_nearby_btn: Button = $Panel/VBox/Tabs/NearbyTab
@onready var tab_search_btn: Button = $Panel/VBox/Tabs/SearchTab

# Content boxes
@onready var nearby_box: VBoxContainer = $Panel/VBox/NearbyBox
@onready var nearby_scroll: ScrollContainer = $Panel/VBox/NearbyBox/Scroll
@onready var nearby_list: VBoxContainer = $Panel/VBox/NearbyBox/Scroll/List

@onready var search_box: VBoxContainer = $Panel/VBox/SearchBox
@onready var search_query_label: Label = $Panel/VBox/SearchBox/SearchRow/QueryLabel
@onready var search_edit_btn: Button = $Panel/VBox/SearchBox/SearchRow/EditBtn
@onready var search_run_btn: Button = $Panel/VBox/SearchBox/SearchRow/SearchBtn

# Selected Player Card
@onready var profile_card: PanelContainer = $Panel/VBox/ProfileCard
@onready var profile_sprite: CharacterSprite = $Panel/VBox/ProfileCard/HBox/SpriteAnchor/Sprite
@onready var profile_name: Label = $Panel/VBox/ProfileCard/HBox/Details/Name
@onready var profile_meta: Label = $Panel/VBox/ProfileCard/HBox/Details/Meta
@onready var profile_status: Label = $Panel/VBox/ProfileCard/HBox/Details/Status

# Action Buttons
@onready var actions_box: HBoxContainer = $Panel/VBox/Actions
@onready var btn_pm: Button = $Panel/VBox/Actions/PMBtn
@onready var btn_trade: Button = $Panel/VBox/Actions/TradeBtn
@onready var btn_party: Button = $Panel/VBox/Actions/PartyBtn

@onready var feedback_label: Label = $Panel/VBox/FeedbackLabel
@onready var close_btn: Button = $Panel/VBox/CloseBtn

var prompt: TextPrompt
var mode := "nearby" # "nearby", "search"
var current_search := ""
var selected_player: Dictionary = {}


func _ready() -> void:
	visible = false
	prompt = TextPrompt.new()
	add_child(prompt)

	get_tree().root.size_changed.connect(_layout_screen)
	tab_nearby_btn.pressed.connect(_set_mode.bind("nearby"))
	tab_search_btn.pressed.connect(_set_mode.bind("search"))
	search_edit_btn.pressed.connect(_edit_search_query)
	search_run_btn.pressed.connect(_run_search)
	btn_pm.pressed.connect(_send_pm)
	btn_trade.pressed.connect(_send_trade)
	btn_party.pressed.connect(_send_party)
	close_btn.pressed.connect(close)


func _layout_screen() -> void:
	if not visible:
		return
	var vp := get_viewport_rect().size
	var safe := Game.get_safe_rect()
	dim.size = vp
	dim.position = Vector2.ZERO
	panel.custom_minimum_size = Vector2(minf(340.0, safe.size.x - 12.0), minf(206.0, safe.size.y - 8.0))
	panel.size = panel.custom_minimum_size
	panel.position = (safe.position + (safe.size - panel.size) / 2.0).round()
	if prompt:
		prompt.position = ((vp - prompt.size) / 2.0).round()


func open(default_mode := "nearby", initial_search := "") -> void:
	mode = default_mode
	current_search = initial_search
	selected_player.clear()
	feedback_label.text = ""
	visible = true
	_set_mode(mode)
	if initial_search != "":
		_run_search()
	_layout_screen()


func close() -> void:
	visible = false
	closed.emit()


func _set_mode(new_mode: String) -> void:
	mode = new_mode
	feedback_label.text = ""
	if mode == "nearby":
		tab_nearby_btn.disabled = true
		tab_search_btn.disabled = false
		nearby_box.visible = true
		search_box.visible = false
		_refresh_nearby()
	else:
		tab_nearby_btn.disabled = false
		tab_search_btn.disabled = true
		nearby_box.visible = false
		search_box.visible = true
		_refresh_search_ui()

	_update_profile_card()
	_layout_screen()


func _refresh_nearby() -> void:
	for child in nearby_list.get_children():
		child.queue_free()

	var players: Array = Net.players.values()
	if players.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No other players on this map right now."
		empty_lbl.theme_type_variation = &"LightLabel"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nearby_list.add_child(empty_lbl)
		return

	for p in players:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var btn := Button.new()
		var char_name: String = str(p.get("character", "mario")).capitalize()
		var side: String = str(p.get("side", "good")).capitalize()
		btn.text = "%s (%s - %s)" % [p.get("name", "Player"), char_name, side]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_select_player.bind(p))
		row.add_child(btn)
		nearby_list.add_child(row)

	if not players.is_empty() and selected_player.is_empty():
		_select_player(players[0])


func _refresh_search_ui() -> void:
	search_query_label.text = current_search if current_search != "" else "(Type username)"
	search_query_label.add_theme_color_override("font_color", Color(1, 1, 1) if current_search != "" else Color(0.7, 0.7, 0.7))


func _edit_search_query() -> void:
	var q := await prompt.ask("Search Player", current_search, 16, "Enter exact or partial username")
	if q != "":
		current_search = q.strip_edges()
		_refresh_search_ui()
		_run_search()


func _run_search() -> void:
	if current_search == "":
		feedback_label.text = "Please enter a username to search."
		feedback_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
		return

	feedback_label.text = "Searching player database..."
	feedback_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))

	# First check in current zone
	for p in Net.players.values():
		if str(p.get("name", "")).to_lower() == current_search.to_lower():
			feedback_label.text = "Player found online in this zone!"
			feedback_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
			_select_player(p)
			return

	# Then query server accounts
	var info := await Cloud.lookup_player(current_search)
	if info.is_empty() or not bool(info.get("exists", false)):
		feedback_label.text = "No account found for '%s'." % current_search
		feedback_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
		selected_player.clear()
		_update_profile_card()
		return

	feedback_label.text = "Player account found!"
	feedback_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	_select_player(info)


func _select_player(p: Dictionary) -> void:
	selected_player = p.duplicate()
	_update_profile_card()


func _update_profile_card() -> void:
	if selected_player.is_empty():
		profile_card.visible = false
		actions_box.visible = false
		return

	profile_card.visible = true
	actions_box.visible = true

	var who: String = str(selected_player.get("name", "Player"))
	var char_id: String = str(selected_player.get("character", "mario"))
	var side: String = str(selected_player.get("side", "good"))
	var level: int = int(selected_player.get("level", 1))

	profile_name.text = who
	profile_meta.text = "%s Lv %d (%s Side)" % [char_id.capitalize(), level, side.capitalize()]

	# Check online presence
	var is_here := false
	for p in Net.players.values():
		if str(p.get("name", "")).to_lower() == who.to_lower():
			is_here = true
			break

	if is_here:
		profile_status.text = "ONLINE - Nearby in this zone"
		profile_status.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
		btn_trade.disabled = false
	else:
		profile_status.text = "ONLINE / CLOUD ACCOUNT"
		profile_status.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
		btn_trade.disabled = false # Can still send name-based trade requests!

	profile_sprite.character_id = char_id
	profile_sprite.scale = Vector2.ONE * minf(1.0, 30.0 / maxf(1.0, profile_sprite.height()))

	var same_side: bool = side == Game.player.get("side", "good")
	btn_party.disabled = not same_side or Net.party_id != ""


func _send_pm() -> void:
	if selected_player.is_empty():
		return
	var who: String = str(selected_player.get("name", ""))
	var text := await prompt.ask("Private Message to %s" % who, "", 80, "Enter message to send")
	if text != "":
		var target_id := str(selected_player.get("id", ""))
		Net.send_whisper(who, text, target_id)
		feedback_label.text = "Sent private message to %s!" % who
		feedback_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))


func _send_trade() -> void:
	if selected_player.is_empty():
		return
	var who: String = str(selected_player.get("name", ""))
	var target_id := str(selected_player.get("id", ""))
	Net.request_trade(target_id, who)
	feedback_label.text = "Trade request sent to %s!" % who
	feedback_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))


func _send_party() -> void:
	if selected_player.is_empty():
		return
	var who: String = str(selected_player.get("name", ""))
	var target_id := str(selected_player.get("id", ""))
	if target_id != "":
		Net.send_invite(target_id)
		feedback_label.text = "Party invite sent to %s!" % who
		feedback_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	else:
		feedback_label.text = "Cannot invite across maps; travel to their zone."
		feedback_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
