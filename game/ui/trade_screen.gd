class_name TradeScreen
extends Control
## Online trading on the Superstar Saga notebook (like the Items page): your
## offer is a menu down the left page (coins, items, a partner, Ready!), the
## other player's offer is shown on the right page and updates live. Arrow
## keys / Z / X, mouse or touch, like every other menu.
## Both players press Ready! to trade; any change to either offer un-readies
## both. Good and evil can trade anyone: it's the only way to get the other
## side's partners and recruits.

signal closed

const COIN := preload("res://assets/ui/coin.png")
const COIN_STEPS := [1, 10, 100, -1, -10, -100]

@onready var book: TextureRect = $Book
@onready var menu: ChoiceMenu = $Book/Menu
@onready var pick: ChoiceMenu = $Book/Pick
@onready var my_name: Label = $Book/MyName
@onready var peer_name_label: Label = $Book/PeerName
@onready var peer_coins: Label = $Book/Peer/Coins/Label
@onready var peer_items_box: HFlowContainer = $Book/Peer/Items
@onready var peer_partner_spot: Control = $Book/Peer/Partner/Spot
@onready var peer_partner_label: Label = $Book/Peer/Partner/Label
@onready var peer_status: Label = $Book/Peer/Status
@onready var footer: Label = $Book/Place

var peer_id := ""
var peer_name := ""
var my_coins := 0
var my_items: Dictionary = {}  # item id -> count
var my_partner: Dictionary = {}  # a copy of the member, with "slot": [where, index]
var my_ready := false
var peer_offer: Dictionary = {"coins": 0, "items": {}, "partner": null}
var peer_ready := false
var _done := false
var _cursor := 0


func _ready() -> void:
	visible = false
	menu.max_rows = 6
	pick.max_rows = 6
	get_tree().root.size_changed.connect(_center_book)


func _center_book() -> void:
	book.position = ((get_viewport_rect().size - book.size) / 2.0).round()


func open(target_peer_id: String, target_peer_name: String) -> void:
	peer_id = target_peer_id
	peer_name = target_peer_name
	my_coins = 0
	my_items = {}
	my_partner = {}
	my_ready = false
	peer_offer = {"coins": 0, "items": {}, "partner": null}
	peer_ready = false
	_done = false
	_cursor = 0
	my_name.text = Game.username()
	peer_name_label.text = peer_name
	_connect_net(true)
	_refresh_peer()
	_say("Pick what to give, then Ready!")
	_center_book()
	visible = true
	_sync_offer()
	_run()


func close() -> void:
	_connect_net(false)
	visible = false
	closed.emit()


func _connect_net(on: bool) -> void:
	var links := {Net.trade_offer_updated: _on_peer_offer, Net.trade_confirmed_by: _on_peer_ready,
		Net.trade_completed: _on_completed, Net.trade_cancelled: _on_cancelled}
	for sig in links:
		if sig.is_connected(links[sig]):
			sig.disconnect(links[sig])
		if on:
			sig.connect(links[sig])


# --- Your offer (left page) ---------------------------------------------------

func _run() -> void:
	while not _done:
		var labels: Array = []
		var icons: Array = []
		var enabled: Array = []
		var acts: Array = []
		labels.append("%d" % my_coins)
		icons.append(COIN)
		enabled.append(not my_ready)
		acts.append(["coins"])
		for id in my_items:
			labels.append("x%d" % my_items[id])
			icons.append(ItemsScreen.icon_of(id))
			enabled.append(not my_ready)
			acts.append(["item", id])
		labels.append(my_partner["name"] if not my_partner.is_empty() else "Partner...")
		icons.append(null)
		enabled.append(not my_ready and (not my_partner.is_empty() or not Game.all_tradeable_partners().is_empty()))
		acts.append(["partner"])
		labels.append("Item...")
		icons.append(null)
		enabled.append(not my_ready and not _items_left().is_empty())
		acts.append(["add_item"])
		labels.append("Not ready" if my_ready else "Ready!")
		icons.append(null)
		enabled.append(my_ready or _room_for_peer_partner())
		acts.append(["ready"])
		labels.append("Quit")
		icons.append(null)
		enabled.append(true)
		acts.append(["quit"])
		var i := await menu.choose(labels, "", true, enabled, [], icons, mini(_cursor, labels.size() - 1))
		if _done:
			return
		if i == -2:  # the other offer changed: redraw
			continue
		if i == -1:
			i = acts.size() - 1  # X: same as Quit
		_cursor = i
		match acts[i][0]:
			"coins":
				await _pick_coins()
			"item":
				await _change_item(acts[i][1])
			"partner":
				await _pick_partner()
			"add_item":
				await _add_item()
			"ready":
				_toggle_ready()
			"quit":
				var q := await pick.choose(["Keep trading", "Quit trade"], "Quit?", true)
				if q == 1 and not _done:
					Net.cancel_trade()
					_done = true
					close()
					return
		if not _done and acts[i][0] != "ready" and acts[i][0] != "quit":
			_offer_changed()


func _pick_coins() -> void:
	var have: int = int(Game.player.get("coins", 0))
	var k := 0
	while not _done:
		var labels: Array = COIN_STEPS.map(func(n): return ("+%d" if n > 0 else "%d") % n) + ["All", "None"]
		k = await pick.choose(labels, "Coins %d/%d" % [my_coins, have], true, [], [], [], k)
		if k < 0:
			return
		if k < COIN_STEPS.size():
			my_coins = clampi(my_coins + COIN_STEPS[k], 0, have)
		else:
			my_coins = have if k == COIN_STEPS.size() else 0


func _change_item(id: String) -> void:
	var k := 0
	while not _done and my_items.has(id):
		var name: String = Game.goods(id)["name"]
		var more: bool = my_items[id] < Game.item_count(id)
		k = await pick.choose(["One more", "One less", "Take back"], "%s x%d" % [name, my_items[id]], true,
			[more, true, true], [], [], k)
		match k:
			0:
				my_items[id] += 1
			1:
				my_items[id] -= 1
			2:
				my_items[id] = 0
			_:
				return
		if my_items[id] <= 0:
			my_items.erase(id)


## Item ids you carry that aren't all in the offer yet.
func _items_left() -> Array:
	return Game.owned_items().filter(func(id): return Game.item_count(id) > int(my_items.get(id, 0)))


func _add_item() -> void:
	var ids := _items_left()
	if ids.is_empty():
		return
	var labels := ids.map(func(id): return "%s x%d" % [Game.goods(id)["name"], Game.item_count(id) - int(my_items.get(id, 0))])
	var icons := ids.map(func(id): return ItemsScreen.icon_of(id))
	var k := await pick.choose(labels, "Offer which?", true, [], [], icons)
	if k >= 0 and not _done:
		my_items[ids[k]] = int(my_items.get(ids[k], 0)) + 1


func _pick_partner() -> void:
	if not my_partner.is_empty():
		var k := await pick.choose(["Take back", "Keep"], my_partner["name"], true)
		if k == 0:
			my_partner = {}
		return
	var party: Array = Game.player["party"]
	var bench: Array = Game.bench()
	var slots: Array = []
	var labels: Array = []
	for j in party.size():
		slots.append(["party", j])
		labels.append("%s  HP %d" % [party[j]["name"], party[j]["max_hp"]])
	for j in bench.size():
		slots.append(["bench", j])
		labels.append("%s (home)" % bench[j]["name"])
	var k := await pick.choose(labels, "Offer who?", true)
	if k < 0 or _done:
		return
	var src: Dictionary = (party if slots[k][0] == "party" else bench)[slots[k][1]]
	my_partner = src.duplicate()
	my_partner["slot"] = slots[k]


## True unless the other player offers a partner and you've nowhere to put one.
func _room_for_peer_partner() -> bool:
	return typeof(peer_offer.get("partner")) != TYPE_DICTIONARY or Game.can_recruit() or not my_partner.is_empty()


func _toggle_ready() -> void:
	if my_ready:
		my_ready = false
		peer_ready = false
		_sync_offer()  # re-sending the offer un-readies both on the server
		_say("You're not ready.")
		_refresh_peer()
		return
	my_ready = true
	Net.confirm_trade()
	_say("Ready! Trading..." if peer_ready else "Ready! Waiting for %s..." % peer_name)


func _offer_changed() -> void:
	my_ready = false
	peer_ready = false
	_sync_offer()
	_refresh_peer()


func _sync_offer() -> void:
	var partner = null
	if not my_partner.is_empty():
		partner = {}
		for key in ["kind", "id", "name", "hp", "max_hp", "pow", "def"]:
			partner[key] = my_partner.get(key)
	Net.send_trade_offer(my_coins, my_items.duplicate(), partner)


# --- Their offer (right page) -------------------------------------------------

func _refresh_peer() -> void:
	peer_coins.text = str(int(peer_offer.get("coins", 0)))
	for c in peer_items_box.get_children():
		c.queue_free()
	var items = peer_offer.get("items", {})
	if typeof(items) == TYPE_DICTIONARY:
		for id in items:
			if not Game.ITEMS.has(id) and not Game.GEAR.has(id):
				continue
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 0)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var pic := TextureRect.new()
			pic.texture = ItemsScreen.icon_of(id)
			pic.custom_minimum_size = Vector2(14, 14)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(pic)
			var count := Label.new()
			count.text = "x%d" % int(items[id])
			row.add_child(count)
			peer_items_box.add_child(row)
	for c in peer_partner_spot.get_children():
		c.queue_free()
	var p = peer_offer.get("partner")
	if typeof(p) == TYPE_DICTIONARY:
		var s := CharacterSprite.new()
		s.character_id = str(p.get("id", ""))
		s.position = Vector2(10, 21)
		peer_partner_spot.add_child(s)
		s.scale = Vector2.ONE * minf(1.0, 22.0 / maxf(1.0, s.height()))
		peer_partner_label.text = "%s\nHP%d POW%d" % [p.get("name", "?"), int(p.get("max_hp", 0)), int(p.get("pow", 0))]
	else:
		peer_partner_label.text = "No partner"
	peer_status.text = "Ready!" if peer_ready else "Choosing..."
	peer_status.theme_type_variation = &"TitleLabel" if peer_ready else &"InfoLabel"


func _say(text: String) -> void:
	footer.text = text


## Something changed under the open menu: close it so it redraws.
func _interrupt() -> void:
	for m in [pick, menu]:
		if m.is_choosing() or m.visible:
			m.chosen.emit(-2 if m == menu else -1)


func _on_peer_offer(offer: Dictionary) -> void:
	peer_offer = offer
	var was_ready := my_ready
	my_ready = false
	peer_ready = false
	_refresh_peer()
	_say("%s changed their offer." % peer_name + (" Ready again?" if was_ready else ""))
	if not _room_for_peer_partner():
		_say("No room for %s: your party and home are full." % offer["partner"].get("name", "them"))
	if not pick.visible:
		_interrupt()


func _on_peer_ready(by_id: String) -> void:
	if by_id != "" and by_id != peer_id:
		return
	peer_ready = true
	_refresh_peer()
	_say("Ready! Trading..." if my_ready else "%s is ready. Press Ready! to trade." % peer_name)


func _on_completed(give: Dictionary, recv: Dictionary) -> void:
	_done = true
	_interrupt()
	Game.apply_trade(give, recv, my_partner.get("slot", []))
	_say("Traded with %s!" % peer_name)
	await get_tree().create_timer(1.2).timeout
	close()


func _on_cancelled(reason: String) -> void:
	if _done:
		return
	_done = true
	_interrupt()
	_say("%s left. Trade cancelled." % peer_name if reason == "left" else "%s quit the trade." % peer_name)
	await get_tree().create_timer(1.4).timeout
	close()
