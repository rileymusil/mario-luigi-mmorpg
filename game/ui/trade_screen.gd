class_name TradeScreen
extends Control
## Online Trading Screen: allows players to trade coins, items, and partners/recruits
## in real-time over WebSockets with live offer updates and anti-scam two-step confirmation.

signal closed

const COIN_ICON := preload("res://assets/ui/coin.png")
const CARD_GREEN := preload("res://assets/ui/card_green.png")
const CARD_RED := preload("res://assets/ui/card_red.png")
const ICONS := {
	"lv": preload("res://assets/ui/lv.png"),
	"heart": preload("res://assets/ui/icon_heart.png"),
	"pow": preload("res://assets/ui/icon_pow.png"),
	"def": preload("res://assets/ui/icon_def.png"),
}

@onready var dim: ColorRect = $Dim
@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/VBox/Header/Title
@onready var peer_header_label: Label = $Panel/VBox/Columns/RightCol/Header
@onready var my_header_label: Label = $Panel/VBox/Columns/LeftCol/Header

# Your side controls
@onready var my_coins_label: Label = $Panel/VBox/Columns/LeftCol/CoinsBox/Label
@onready var my_items_container: VBoxContainer = $Panel/VBox/Columns/LeftCol/ItemsScroll/ItemsBox
@onready var my_partner_container: PanelContainer = $Panel/VBox/Columns/LeftCol/PartnerCard
@onready var my_confirm_btn: Button = $Panel/VBox/Columns/LeftCol/ConfirmBtn

# Peer side controls
@onready var peer_coins_label: Label = $Panel/VBox/Columns/RightCol/CoinsBox/Label
@onready var peer_items_container: VBoxContainer = $Panel/VBox/Columns/RightCol/ItemsScroll/ItemsBox
@onready var peer_partner_container: PanelContainer = $Panel/VBox/Columns/RightCol/PartnerCard
@onready var peer_status_label: Label = $Panel/VBox/Columns/RightCol/PeerStatus

# Sub-pickers
@onready var sub_menu: ChoiceMenu = $SubMenu
@onready var footer_info: Label = $Panel/VBox/Footer/Info
@onready var cancel_btn: Button = $Panel/VBox/Footer/CancelBtn

var peer_id := ""
var peer_name := ""
var my_coins := 0
var my_items: Dictionary = {}  # item_id -> count
var my_partner: Variant = null  # Dictionary or null
var my_confirmed := false

var peer_coins := 0
var peer_items: Dictionary = {}
var peer_partner: Variant = null
var peer_confirmed := false

var _picker_mode := ""  # "item", "partner", "item_count"
var _selected_item_id := ""


func _ready() -> void:
	visible = false
	get_tree().root.size_changed.connect(_layout_screen)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	my_confirm_btn.pressed.connect(_on_confirm_pressed)
	_setup_coin_buttons()
	_setup_sub_menu()


func _setup_sub_menu() -> void:
	sub_menu.visible = false
	sub_menu.max_rows = 6


func _setup_coin_buttons() -> void:
	var col = $Panel/VBox/Columns/LeftCol/CoinsBox/Buttons
	for btn in col.get_children():
		if btn is Button:
			btn.pressed.connect(_on_coin_btn_pressed.bind(btn.name))


func _layout_screen() -> void:
	if not visible:
		return
	var safe := Game.get_safe_rect()
	var vp_size := get_viewport_rect().size
	dim.size = vp_size
	dim.position = Vector2.ZERO
	# Center panel comfortably inside safe area
	panel.custom_minimum_size = Vector2(minf(370.0, safe.size.x - 8.0), minf(206.0, safe.size.y - 6.0))
	panel.size = panel.custom_minimum_size
	panel.position = (safe.position + (safe.size - panel.size) / 2.0).round()
	sub_menu.position = Vector2(safe.position.x + (safe.size.x - sub_menu.size.x) / 2.0, safe.position.y + 20.0).round()


func open(target_peer_id: String, target_peer_name: String) -> void:
	peer_id = target_peer_id
	peer_name = target_peer_name
	my_coins = 0
	my_items.clear()
	my_partner = null
	my_confirmed = false

	peer_coins = 0
	peer_items.clear()
	peer_partner = null
	peer_confirmed = false

	_connect_net_signals()

	peer_header_label.text = "%s'S OFFER" % peer_name.to_upper()
	my_header_label.text = "%s'S OFFER" % Game.username().to_upper()
	footer_info.text = "Add items, coins, or a partner, then confirm."
	footer_info.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))

	_refresh_my_view()
	_refresh_peer_view()
	_sync_offer()

	visible = true
	_layout_screen()


func close() -> void:
	_disconnect_net_signals()
	sub_menu.visible = false
	visible = false
	closed.emit()


func _connect_net_signals() -> void:
	_disconnect_net_signals()
	Net.trade_offer_updated.connect(_on_peer_offer_updated)
	Net.trade_confirmed_by.connect(_on_peer_confirmed)
	Net.trade_completed.connect(_on_trade_completed)
	Net.trade_cancelled.connect(_on_trade_cancelled)


func _disconnect_net_signals() -> void:
	if Net.trade_offer_updated.is_connected(_on_peer_offer_updated):
		Net.trade_offer_updated.disconnect(_on_peer_offer_updated)
	if Net.trade_confirmed_by.is_connected(_on_peer_confirmed):
		Net.trade_confirmed_by.disconnect(_on_peer_confirmed)
	if Net.trade_completed.is_connected(_on_trade_completed):
		Net.trade_completed.disconnect(_on_trade_completed)
	if Net.trade_cancelled.is_connected(_on_trade_cancelled):
		Net.trade_cancelled.disconnect(_on_trade_cancelled)


func _on_peer_offer_updated(offer: Dictionary) -> void:
	peer_coins = clampi(int(offer.get("coins", 0)), 0, 99999)
	var raw_items = offer.get("items", {})
	peer_items.clear()
	if typeof(raw_items) == TYPE_DICTIONARY:
		for k in raw_items:
			var c = int(raw_items[k])
			if c > 0:
				peer_items[str(k)] = c
	var raw_p = offer.get("partner")
	if typeof(raw_p) == TYPE_DICTIONARY and not raw_p.is_empty():
		peer_partner = raw_p.duplicate()
	else:
		peer_partner = null

	# Any offer change resets both players' confirmation
	peer_confirmed = false
	my_confirmed = false
	footer_info.text = "%s modified their offer." % peer_name
	footer_info.add_theme_color_override("font_color", Color(1, 0.85, 0.3))

	_refresh_my_view()
	_refresh_peer_view()


func _on_peer_confirmed(by_id: String) -> void:
	if by_id == peer_id or by_id == "":
		peer_confirmed = true
		_refresh_peer_view()
		if my_confirmed:
			footer_info.text = "Both offers confirmed! Finalizing trade..."
			footer_info.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
		else:
			footer_info.text = "%s confirmed their offer! Review and confirm." % peer_name
			footer_info.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))


func _on_trade_completed(give: Dictionary, recv: Dictionary) -> void:
	footer_info.text = "Trade completed successfully!"
	footer_info.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	my_confirm_btn.disabled = true
	cancel_btn.disabled = true
	# Give feedback and close
	var timer := get_tree().create_timer(1.2)
	timer.timeout.connect(func():
		close())


func _on_trade_cancelled(reason: String) -> void:
	footer_info.text = "Trade cancelled: %s" % ("Player left" if reason == "left" else "Declined")
	footer_info.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	var timer := get_tree().create_timer(1.0)
	timer.timeout.connect(func():
		close())


func _sync_offer() -> void:
	Net.send_trade_offer(my_coins, my_items, my_partner)


func _on_coin_btn_pressed(btn_name: String) -> void:
	if my_confirmed:
		return
	var max_coins: int = int(Game.player.get("coins", 0))
	match btn_name:
		"Minus10":
			my_coins = maxi(0, my_coins - 10)
		"Minus1":
			my_coins = maxi(0, my_coins - 1)
		"Plus1":
			my_coins = mini(max_coins, my_coins + 1)
		"Plus10":
			my_coins = mini(max_coins, my_coins + 10)
		"Max":
			my_coins = max_coins
		"Zero":
			my_coins = 0
	_unconfirm()
	_refresh_my_view()
	_sync_offer()


func _unconfirm() -> void:
	if my_confirmed:
		my_confirmed = false
		peer_confirmed = false
		footer_info.text = "Offer changed. Confirmation reset."
		footer_info.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		_refresh_my_view()
		_refresh_peer_view()


func _on_confirm_pressed() -> void:
	if my_confirmed:
		# Toggle back to unconfirmed so you can adjust
		_unconfirm()
		_sync_offer()
		return

	my_confirmed = true
	_refresh_my_view()
	Net.confirm_trade()
	if peer_confirmed:
		footer_info.text = "Both confirmed! Finalizing trade..."
		footer_info.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	else:
		footer_info.text = "You confirmed! Waiting for %s..." % peer_name
		footer_info.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))


func _on_cancel_pressed() -> void:
	Net.cancel_trade()
	close()


# --- Left Column (YOU) Rendering ---------------------------------------------

func _refresh_my_view() -> void:
	var total_coins: int = int(Game.player.get("coins", 0))
	my_coins_label.text = "%d / %d" % [my_coins, total_coins]

	# Render items list
	for child in my_items_container.get_children():
		child.queue_free()

	for item_id in my_items:
		var count: int = int(my_items[item_id])
		if count <= 0:
			continue
		var row := _build_item_row(item_id, count, true)
		my_items_container.add_child(row)

	var add_item_btn := Button.new()
	add_item_btn.text = "+ Add Item"
	add_item_btn.disabled = my_confirmed
	add_item_btn.pressed.connect(_open_add_item_picker)
	my_items_container.add_child(add_item_btn)

	# Render partner card
	_render_partner_card(my_partner_container, my_partner, true)

	# Confirm button styling
	if my_confirmed:
		my_confirm_btn.text = "LOCKED IN (Click to Edit)"
		my_confirm_btn.add_theme_color_override("font_color", Color(0.2, 0.85, 0.2))
	else:
		my_confirm_btn.text = "CONFIRM OFFER"
		my_confirm_btn.remove_theme_color_override("font_color")


func _render_partner_card(container: PanelContainer, partner_data: Variant, is_mine: bool) -> void:
	for c in container.get_children():
		c.queue_free()

	if partner_data == null or (partner_data is Dictionary and partner_data.is_empty()):
		if is_mine:
			var btn := Button.new()
			btn.text = "+ Offer Partner"
			btn.disabled = my_confirmed
			btn.pressed.connect(_open_partner_picker)
			container.add_child(btn)
		else:
			var none_label := Label.new()
			none_label.text = "(No partner offered)"
			none_label.theme_type_variation = &"LightLabel"
			none_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			container.add_child(none_label)
		return

	var card_bg := TextureRect.new()
	card_bg.texture = CARD_GREEN
	card_bg.custom_minimum_size = Vector2(160, 48)
	container.add_child(card_bg)

	var p: Dictionary = partner_data
	var name_label := Label.new()
	name_label.theme_type_variation = &"LightLabel"
	name_label.text = str(p.get("name", "Partner"))
	name_label.position = Vector2(16, 2)
	card_bg.add_child(name_label)

	var sprite := CharacterSprite.new()
	sprite.character_id = str(p.get("id", "goombario"))
	sprite.position = Vector2(24, 38)
	card_bg.add_child(sprite)
	sprite.scale = Vector2.ONE * minf(1.0, 26.0 / maxf(1.0, sprite.height()))

	var stats_box := HBoxContainer.new()
	stats_box.position = Vector2(48, 18)
	stats_box.add_theme_constant_override("separation", 4)
	card_bg.add_child(stats_box)

	var hp_icon := TextureRect.new()
	hp_icon.texture = ICONS["heart"]
	stats_box.add_child(hp_icon)
	var hp_label := Label.new()
	hp_label.theme_type_variation = &"LightLabel"
	hp_label.text = "%d/%d" % [int(p.get("hp", 10)), int(p.get("max_hp", 10))]
	stats_box.add_child(hp_label)

	var pow_icon := TextureRect.new()
	pow_icon.texture = ICONS["pow"]
	stats_box.add_child(pow_icon)
	var pow_label := Label.new()
	pow_label.theme_type_variation = &"LightLabel"
	pow_label.text = str(p.get("pow", 1))
	stats_box.add_child(pow_label)

	var def_icon := TextureRect.new()
	def_icon.texture = ICONS["def"]
	stats_box.add_child(def_icon)
	var def_label := Label.new()
	def_label.theme_type_variation = &"LightLabel"
	def_label.text = str(p.get("def", 0))
	stats_box.add_child(def_label)

	if is_mine:
		var remove_btn := Button.new()
		remove_btn.text = "X"
		remove_btn.size = Vector2(16, 14)
		remove_btn.position = Vector2(142, 2)
		remove_btn.disabled = my_confirmed
		remove_btn.pressed.connect(_remove_offered_partner)
		card_bg.add_child(remove_btn)


func _remove_offered_partner() -> void:
	my_partner = null
	_unconfirm()
	_refresh_my_view()
	_sync_offer()


func _build_item_row(item_id: String, count: int, is_mine: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)

	var icon_path := "res://assets/items/%s.png" % item_id
	if ResourceLoader.exists(icon_path):
		var icon_tex := load(icon_path) as Texture2D
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.custom_minimum_size = Vector2(12, 12)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)

	var good: Dictionary = Game.goods(item_id)
	var item_name: String = good.get("name", item_id.capitalize())
	var label := Label.new()
	label.theme_type_variation = &"LightLabel"
	label.text = "%s x%d" % [item_name, count]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	if is_mine:
		var minus_btn := Button.new()
		minus_btn.text = "-"
		minus_btn.disabled = my_confirmed
		minus_btn.pressed.connect(_adjust_item_count.bind(item_id, -1))
		row.add_child(minus_btn)

		var max_avail: int = Game.item_count(item_id)
		var plus_btn := Button.new()
		plus_btn.text = "+"
		plus_btn.disabled = my_confirmed or count >= max_avail
		plus_btn.pressed.connect(_adjust_item_count.bind(item_id, 1))
		row.add_child(plus_btn)

		var rem_btn := Button.new()
		rem_btn.text = "X"
		rem_btn.disabled = my_confirmed
		rem_btn.pressed.connect(_remove_item.bind(item_id))
		row.add_child(rem_btn)

	return row


func _adjust_item_count(item_id: String, delta: int) -> void:
	var cur: int = int(my_items.get(item_id, 0))
	var max_avail: int = Game.item_count(item_id)
	var next_count: int = clampi(cur + delta, 0, max_avail)
	if next_count <= 0:
		my_items.erase(item_id)
	else:
		my_items[item_id] = next_count
	_unconfirm()
	_refresh_my_view()
	_sync_offer()


func _remove_item(item_id: String) -> void:
	my_items.erase(item_id)
	_unconfirm()
	_refresh_my_view()
	_sync_offer()


# --- Right Column (PEER) Rendering -------------------------------------------

func _refresh_peer_view() -> void:
	peer_coins_label.text = "%d Coins" % peer_coins

	for child in peer_items_container.get_children():
		child.queue_free()

	if peer_items.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "(No items offered)"
		empty_lbl.theme_type_variation = &"LightLabel"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		peer_items_container.add_child(empty_lbl)
	else:
		for item_id in peer_items:
			var count: int = int(peer_items[item_id])
			var row := _build_item_row(item_id, count, false)
			peer_items_container.add_child(row)

	_render_partner_card(peer_partner_container, peer_partner, false)

	if peer_confirmed:
		peer_status_label.text = "OFFER LOCKED & CONFIRMED"
		peer_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	else:
		peer_status_label.text = "Deciding on offer..."
		peer_status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))


# --- Pickers ------------------------------------------------------------------

func _open_add_item_picker() -> void:
	if my_confirmed:
		return
	var available_ids: Array = Game.owned_items()
	if available_ids.is_empty():
		footer_info.text = "You don't have any items to offer."
		return

	var labels: Array = []
	var icons: Array = []
	var valid_ids: Array = []

	for id in available_ids:
		var owned: int = Game.item_count(id)
		var already_offered: int = int(my_items.get(id, 0))
		var left: int = owned - already_offered
		if left > 0:
			valid_ids.append(id)
			var good: Dictionary = Game.goods(id)
			labels.append("%s (x%d)" % [good.get("name", id), left])
			var path := "res://assets/items/%s.png" % id
			icons.append(load(path) if ResourceLoader.exists(path) else null)

	if valid_ids.is_empty():
		footer_info.text = "All your carried items are already in the offer."
		return

	_picker_mode = "item"
	sub_menu.position = Vector2(panel.position.x + 30, panel.position.y + 20)
	var choice := await sub_menu.choose(labels, "Choose Item to Offer", true, [], [], icons)
	if choice >= 0 and choice < valid_ids.size():
		var chosen_id = valid_ids[choice]
		my_items[chosen_id] = int(my_items.get(chosen_id, 0)) + 1
		_unconfirm()
		_refresh_my_view()
		_sync_offer()


func _open_partner_picker() -> void:
	if my_confirmed:
		return
	var partners: Array = Game.all_tradeable_partners()
	if partners.is_empty():
		footer_info.text = "You don't have any partners or recruits to trade."
		return

	var labels: Array = []
	var valid_partners: Array = []
	for p in partners:
		var name_str = str(p.get("name", "Partner"))
		var loc = " (Party)" if p.get("location") == "party" else " (Bench)"
		var stats = " HP:%d POW:%d" % [int(p.get("max_hp", 10)), int(p.get("pow", 1))]
		labels.append(name_str + loc + stats)
		valid_partners.append(p)

	_picker_mode = "partner"
	sub_menu.position = Vector2(panel.position.x + 30, panel.position.y + 20)
	var choice := await sub_menu.choose(labels, "Choose Partner to Offer", true)
	if choice >= 0 and choice < valid_partners.size():
		my_partner = valid_partners[choice].duplicate()
		_unconfirm()
		_refresh_my_view()
		_sync_offer()
