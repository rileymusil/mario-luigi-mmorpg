extends Node2D
## Turn-based battle with Superstar Saga style timed presses (Z).
##
## Jump: press Z just as you land on the enemy for a second stomp.
## Specials and partner attacks: press Z when the marker is in the gold zone.
## Enemy turns: press Z so whoever is attacked is in the air when it hits.
##
## Looks: the map's battle background (Game.MAPS[map]["battle_bg"], from
## res://assets/battle/backgrounds/), command blocks over whoever's turn it is,
## a pointer for picking targets (both work with the mouse and touch too),
## word-art ratings, A-button badges during timed presses, and HP on the navy
## bar at the bottom.

const LAND_EARLY := 0.15     # seconds before landing that still count
const LAND_LATE := 0.08
const LAND_EXCELLENT := 0.06
const ALLY_SPOTS := [Vector2(125, 176), Vector2(62, 146), Vector2(52, 192)]
const ENEMY_SPOTS := [Vector2(280, 168), Vector2(320, 145)]
const SCALE := 1.5

const BACKGROUNDS := "res://assets/battle/backgrounds/%s.png"
const DEFAULT_BACKGROUND := "outskirts"
## Word art for ratings; anything else shows as gold text.
const RATING_ART := {
	"Excellent": preload("res://assets/battle/rating_great.png"),
	"Good": preload("res://assets/battle/rating_good.png"),
	"Miss": preload("res://assets/battle/rating_miss.png"),
	"Dodged!": preload("res://assets/battle/rating_good.png"),
	"Lucky!": preload("res://assets/battle/rating_lucky.png"),
}
## A-button badges for timed presses: red over you, green over partners.
const BADGES := {
	"jump_red": preload("res://assets/battle/prompt_jump_red.png"),
	"jump_green": preload("res://assets/battle/prompt_jump_green.png"),
	"burst_red": preload("res://assets/battle/prompt_burst_red.png"),
	"hammer_green": preload("res://assets/battle/prompt_hammer_green.png"),
}
const ICON_HEART := preload("res://assets/ui/icon_heart.png")
const ICON_BEAN := preload("res://assets/ui/icon_bean.png")
const STATUS_BURN := preload("res://assets/battle/status_burn.png")
const STATUS_STUN := preload("res://assets/battle/status_stun.png")

## Some enemies' hits can leave you burning or dizzy: type -> [status, chance].
## A Refreshing Herb cures both.
const FOE_STATUS := {"dry_bones": ["burn", 0.3], "beanie": ["dizzy", 0.25], "shy_guy": ["dizzy", 0.2]}

## Battle actors: {name, node, hp, max_hp, pow, def, ally, member, type, burn, stun}
## (allies can also have burn and dizzy, see FOE_STATUS)
var allies: Array = []
var foes: Array = []
var xp_earned := 0
var coins_earned := 0
var _rating_tween: Tween
var _time := 0.0
var _badges: Array = []  # [badge sprite, character it follows]
var _presented := false
var _hint := ""         # the hint in the message box, before key names went in
var _hint_args: Array = []
var _hint_shown := ""

@onready var background: TextureRect = $Background
@onready var stage: Node2D = $Stage
@onready var message: Label = $UI/MessageBox/Message
@onready var party_bar: HBoxContainer = $UI/PartyBar
@onready var foe_box: PanelContainer = $UI/FoeBox
@onready var foe_list: VBoxContainer = $UI/FoeBox/FoeList
@onready var rating: Label = $UI/Rating
@onready var rating_art: TextureRect = $UI/Rating/Art
## The plain list menu. battle.gd uses the command blocks; scenes built on it
## (pvp_battle.gd) can still use this.
@onready var menu: ChoiceMenu = $UI/Menu
@onready var blocks: CommandBlocks = $UI/Commands
@onready var targets: TargetPicker = $UI/Targets
@onready var bar: Control = $UI/TimingBar
@onready var bar_zone: ColorRect = $UI/TimingBar/Zone
@onready var bar_best: ColorRect = $UI/TimingBar/Best
@onready var bar_marker: ColorRect = $UI/TimingBar/Marker
@onready var bar_badge: TextureRect = $UI/TimingBadge
@onready var bar_frame: Control = $UI/TimingFrame


func _ready() -> void:
	if Game.player.is_empty():
		Game.new_player("mario")
		Game.pending_battle = {"enemies": ["goomba"], "key": "test"}
	var p: Dictionary = Game.player
	_add_ally({"name": Game.character_name(), "id": p["character"], "member": p})
	for m in p["party"]:
		_add_ally({"name": m["name"], "id": m["id"], "member": m})
	for type in Game.pending_battle.get("enemies", ["goomba"]):
		_add_foe(type)
	_setup_presentation(p["map"])
	_refresh()
	_run_battle()


## The looks: the map's battle background, the HP boxes for `allies`, and the
## UI pieces' starting state. Call it once the allies are added. Scenes built
## on this one call it from their own _ready (if they don't, it runs on the
## first frame).
func _setup_presentation(map_id: String) -> void:
	if _presented:
		return
	_presented = true
	_load_background(Game.pending_battle.get("battle_bg", Game.MAPS.get(map_id, {}).get("battle_bg", DEFAULT_BACKGROUND)))
	bar.visible = false
	bar_badge.visible = false
	menu.visible = false
	rating.text = ""
	rating.modulate.a = 0.0
	blocks.highlighted.connect(func(info: String): _say(info))
	TouchControls.active_changed.connect(_on_touch_mode_changed)
	_refresh()


## Shows a hint in the message box. {a} and {b} in it name the buttons: the
## Z and X keys, or the on-screen A and B buttons when playing by touch.
## args fill its %s / %d after that. The wording follows along if the player
## switches between keys and touch while the hint is up.
func _say(hint: String, args: Array = []) -> void:
	_hint = hint
	_hint_args = args
	_hint_shown = _keys(hint) % args if not args.is_empty() else _keys(hint)
	message.text = _hint_shown


## {a} / {b} in text as Z / X, or A / B when playing by touch.
func _keys(text: String) -> String:
	var touch: bool = TouchControls.active
	return text.replace("{a}", "A" if touch else "Z").replace("{b}", "B" if touch else "X")


func _on_touch_mode_changed(_touch: bool) -> void:
	if _hint != "" and message.text == _hint_shown:
		_say(_hint, _hint_args)


func _load_background(id: String) -> void:
	var path := BACKGROUNDS % id
	if not ResourceLoader.exists(path):
		path = BACKGROUNDS % DEFAULT_BACKGROUND
	background.texture = load(path)


func _add_ally(info: Dictionary) -> void:
	var node := CharacterSprite.new()
	node.character_id = info["id"]
	node.facing = Vector2.RIGHT
	node.scale = Vector2(SCALE, SCALE)
	node.position = ALLY_SPOTS[allies.size()]
	stage.add_child(node)
	var m: Dictionary = info["member"]
	allies.append({"name": info["name"], "node": node, "member": m, "ally": true, "home": node.position,
		"pow": m["pow"], "def": m["def"]})


func _add_foe(type: String) -> void:
	var e: Dictionary = Game.ENEMIES[type]
	var node := CharacterSprite.new()
	node.character_id = type
	node.facing = Vector2.LEFT
	node.scale = Vector2(SCALE, SCALE)
	node.position = ENEMY_SPOTS[foes.size()]
	stage.add_child(node)
	var count := foes.filter(func(f): return f["type"] == type).size()
	foes.append({"name": e["name"] + (" B" if count > 0 else ""), "type": type, "node": node, "ally": false,
		"hp": e["hp"], "max_hp": e["hp"], "pow": e["pow"], "def": e["def"], "burn": 0, "stun": false,
		"home": node.position})


func _hp(a: Dictionary) -> int:
	return a["member"]["hp"] if a["ally"] else a["hp"]


func _set_hp(a: Dictionary, value: int) -> void:
	if a["ally"]:
		a["member"]["hp"] = clampi(value, 0, a["member"]["max_hp"])
		a["node"].modulate.a = 1.0 if a["member"]["hp"] > 0 else 0.4
	else:
		a["hp"] = clampi(value, 0, a["max_hp"])


func _alive(list: Array) -> Array:
	return list.filter(func(a): return _hp(a) > 0)


func _is_player(a: Dictionary) -> bool:
	return a["ally"] and is_same(a["member"], Game.player)


# --- Battle flow ---------------------------------------------------------------

func _run_battle() -> void:
	message.text = "%s appeared!" % " and ".join(foes.map(func(f): return f["name"]))
	await _wait(1.0)
	if Game.pending_battle.get("first_strike", false):
		message.text = "First strike!"
		for f in foes:
			_damage(f, allies[0]["pow"])
		await _wait(0.8)
		if _alive(foes).is_empty():
			await _win()
			return
	while true:
		for a in allies:
			if _hp(a) <= 0:
				continue
			var result: String = await _ally_turn(a)
			_set_turn({})
			if result == "fled":
				message.text = "Got away safely!"
				await _wait(1.0)
				_leave("fled")
				return
			if _alive(foes).is_empty():
				await _win()
				return
		for f in _alive(foes):
			await _foe_turn(f)
			if _alive(allies).is_empty():
				await _lose()
				return
			if _alive(foes).is_empty():
				await _win()
				return


## The command blocks for this ally: {id, label, icon, enabled, info}.
func _commands_for(a: Dictionary) -> Array:
	var p: Dictionary = Game.player
	if not _is_player(a):
		var move: Dictionary = Game.MOVES[_move_id(a)]
		return [
			{"id": "attack", "label": move["name"], "icon": "hammer", "info": move["info"]},
			_items_command(),
			{"id": "run", "label": "Run", "icon": "run", "info": "Try to escape."},
		]
	var sp: Dictionary = Game.SPECIALS[Game.CHARACTERS[p["character"]]["special"]]
	return [
		{"id": "jump", "label": "Jump", "icon": "jump", "info": "Stomp! Press {a} as you land for a 2nd hit."},
		{"id": "special", "label": "%s (%d SP)" % [sp["name"], sp["sp"]], "icon": "burst",
			"enabled": p["sp"] >= sp["sp"], "info": sp["info"]},
		_items_command(),
		{"id": "ask", "label": "Ask to join", "icon": "hand", "enabled": p["side"] == "evil" and Game.can_recruit(),
			"info": "Evil only: ask an enemy to join your party." if p["side"] == "good" else "Weaker enemies say yes more often."},
		{"id": "run", "label": "Run", "icon": "run", "info": "Try to escape."},
	]


func _ally_turn(a: Dictionary) -> String:
	if a.get("veil", 0) > 0:
		await _end_veil(a)  # nobody attacked the shadows: the fire comes out anyway
		if _alive(foes).is_empty():
			return ""
	if await _ally_status(a):
		return ""
	var commands := _commands_for(a)
	_set_turn(a)
	while true:
		var choice: String = commands[await blocks.choose(commands, a["node"], not _is_player(a))]["id"]
		message.text = ""
		if choice == "run":
			if randf() < 0.6:
				return "fled"
			message.text = "Couldn't get away!"
			await _wait(0.8)
			return ""
		if choice == "items":
			if not await _item_turn(a):
				continue  # X backs out to the blocks
			return ""
		var target = await _pick_foe()
		if target == null:
			continue
		match choice:
			"jump":
				await _jump_attack(a, target)
			"attack":
				await _partner_move(a, target, _move_id(a))
			"ask":
				await _ask(target)
			"special":
				await _special(a, target)
		return ""
	return ""


## Returns the foe to hit, or null if the player backed out with X.
func _pick_foe():
	var alive := _alive(foes)
	if alive.size() == 1:
		return alive[0]
	return await _pick(alive, "Pick a target.", func(f): return f["name"])


## Points at one of `list` with the target pointer; label(t) names each.
func _pick(list: Array, prompt: String, label: Callable):
	list.sort_custom(func(x, y): return x["node"].position.x < y["node"].position.x)
	message.text = prompt
	var i := await targets.choose(list.map(func(t): return {"node": t["node"], "label": label.call(t)}))
	message.text = ""
	return list[i] if i >= 0 else null


# --- Items ---------------------------------------------------------------------

## The Items block: greyed out when nothing you carry can be used right now.
func _items_command() -> Dictionary:
	var any := Game.owned_items().any(func(id): return not _item_targets(id).is_empty())
	return {"id": "items", "label": "Items", "icon": "mushroom", "enabled": any,
		"info": "Use an item. It takes this turn."}


## Who item `id` could be used on right now (see Game.ITEMS).
func _item_targets(id: String) -> Array:
	var item: Dictionary = Game.ITEMS[id]
	if item.has("sp"):
		var p: Dictionary = Game.player
		return allies.filter(func(a): return _is_player(a) and _hp(a) > 0 and p["sp"] < p["max_sp"])
	if item.has("revive"):
		# Someone who left a co-op battle is hidden, and can't come back.
		return allies.filter(func(a): return _hp(a) <= 0 and a["node"].visible)
	if item.get("cure", false):
		return _alive(allies).filter(func(a): return a.get("burn", 0) > 0 or a.get("dizzy", false))
	if item.has("hp"):
		return _alive(allies).filter(func(a): return _hp(a) < a["member"]["max_hp"])
	return _alive(allies)  # peppers


## Picks an item from the list and who it's for, and uses it. False if the
## player backed out (the turn isn't used up).
func _item_turn(a: Dictionary) -> bool:
	while true:
		var ids := Game.owned_items()
		var labels := []
		var enabled := []
		var infos := []
		var icons := []
		for id in ids:
			var item: Dictionary = Game.ITEMS[id]
			labels.append("%s x%d" % [item["name"], Game.item_count(id)])
			enabled.append(not _item_targets(id).is_empty())
			infos.append(item["info"])
			icons.append(load("res://assets/items/%s.png" % id))
		menu.max_rows = 5
		menu.info_width = 150.0
		_say("Which item? {b} to go back.")
		var i := await menu.choose(labels, "Items", true, enabled, infos, icons)
		message.text = ""
		if i < 0:
			return false
		var id: String = ids[i]
		var list := _item_targets(id)
		var who = list[0]
		if list.size() > 1:
			who = await _pick(list, "Use the %s on who?" % Game.ITEMS[id]["name"],
				func(t): return "%s %d/%d" % [t["name"], _hp(t), t["member"]["max_hp"]])
			if who == null:
				continue  # back to the item list
		await _use_item(a, id, who)
		return true
	return false


## Uses one of item `id` from your bag on ally `who` (`a` is whose turn it is).
func _use_item(a: Dictionary, id: String, who: Dictionary) -> void:
	var item: Dictionary = Game.ITEMS[id]
	var p: Dictionary = Game.player
	Game.add_item(id, -1)
	message.text = "%s used the %s!" % [a["name"], item["name"]]
	await _item_pop(who, id)
	var text := ""
	if item.has("hp"):
		var before := _hp(who)
		_set_hp(who, before + int(item["hp"]))
		text = "+%d HP" % (_hp(who) - before)
	elif item.has("sp"):
		var before: int = p["sp"]
		p["sp"] = mini(p["max_sp"], p["sp"] + int(item["sp"]))
		text = "+%d SP" % (p["sp"] - before)
	elif item.has("revive"):
		var max_hp: int = who["member"]["max_hp"]
		_set_hp(who, maxi(1, int(max_hp * float(item["revive"]))))
		message.text = "%s is back on their feet!" % who["name"]
		text = "+%d HP" % _hp(who)
	elif item.get("cure", false):
		who["burn"] = 0
		who["dizzy"] = false
		message.text = "%s feels refreshed!" % who["name"]
		text = "Cured!"
	elif item.has("pow"):
		who["pow"] += int(item["pow"])
		text = "POW +%d" % int(item["pow"])
	elif item.has("def"):
		who["def"] += int(item["def"])
		text = "DEF +%d" % int(item["def"])
	_refresh()
	_show_rating(text)
	await _wait(0.9)


## The item's picture pops up over whoever gets it and fades out.
func _item_pop(who: Dictionary, id: String) -> void:
	var node: CharacterSprite = who["node"]
	var pic := Sprite2D.new()
	pic.texture = load("res://assets/items/%s.png" % id)
	pic.position = node.position + Vector2(0, -node.height() * SCALE - 6)
	pic.scale = Vector2(SCALE, SCALE)
	stage.add_child(pic)
	var tw := create_tween()
	tw.tween_property(pic, "position:y", pic.position.y - 10, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.15)
	tw.tween_property(pic, "modulate:a", 0.0, 0.2)
	await tw.finished
	pic.queue_free()


## At the start of an ally's turn: a dizzy ally loses the turn, a burning one
## gets hurt. True if the turn is over.
func _ally_status(a: Dictionary) -> bool:
	if a.get("dizzy", false):
		a["dizzy"] = false
		message.text = "%s is dizzy and can't move!" % a["name"]
		await _wait(0.8)
		return true
	if a.get("burn", 0) > 0:
		a["burn"] -= 1
		message.text = "%s is hurt by the burn!" % a["name"]
		_damage(a, 2 + int(a["def"]))
		await _wait(0.7)
		message.text = ""
		return _hp(a) <= 0
	return false


## After an enemy's hit lands on an ally: maybe a burn or dizziness.
func _foe_status(f: Dictionary, target: Dictionary) -> void:
	var st: Array = FOE_STATUS.get(f.get("type", ""), [])
	if st.is_empty() or _hp(target) <= 0 or randf() >= float(st[1]):
		return
	if st[0] == "burn":
		target["burn"] = 2
		message.text = "%s is burning!" % target["name"]
	else:
		target["dizzy"] = true
		message.text = "%s is dizzy!" % target["name"]


# --- Attacks -------------------------------------------------------------------

func _jump_attack(a: Dictionary, target: Dictionary, burn := 0) -> String:
	var node: CharacterSprite = a["node"]
	var stand: Vector2 = target["node"].position + Vector2(-40, 0)
	var top: Vector2 = target["node"].position + Vector2(0, -target["node"].height() * SCALE * 0.8)
	_say("Press {a} just as you land!")
	await _walk(node, stand, 160.0)
	var badge := _show_badge(a, "jump")
	var timing := await _arc(node, node.position, top, 50.0, 0.55, true)
	badge.queue_free()
	_damage(target, a["pow"])
	var result := _rate_landing(timing)
	_show_rating(result)
	if result != "Miss":
		await _arc(node, top, top, 38.0, 0.45, false)
		_damage(target, a["pow"] + (1 if result == "Excellent" else 0))
	if burn > 0 and _hp(target) > 0:
		target["burn"] = burn + (1 if result == "Excellent" else 0)
		message.text = "%s is burning!" % target["name"]
		_refresh()
	await _arc(node, node.position, stand, 28.0, 0.35, false)
	await _walk(node, a["home"], 160.0)
	node.facing = Vector2.RIGHT
	return result


## move: an entry of Game.MOVES (bonus, ignore_def and the Excellent extras).
func _tackle(a: Dictionary, target: Dictionary, move: Dictionary = {}) -> String:
	var node: CharacterSprite = a["node"]
	var result := await _timing_bar(1.0, "hammer_green")
	await _walk(node, target["node"].position + Vector2(-22, 0), 220.0)
	var extra: int = move.get("bonus", 0) + (int(target["def"]) if move.get("ignore_def", false) else 0)
	_damage(target, a["pow"] + extra + {"Excellent": 2, "Good": 1, "Miss": 0}[result])
	_show_rating(result)
	_move_extras(move, result, [target])
	await _walk(node, a["home"], 160.0)
	node.facing = Vector2.RIGHT
	return result


func _special(a: Dictionary, target: Dictionary) -> void:
	var p: Dictionary = Game.player
	var id: String = Game.CHARACTERS[p["character"]]["special"]
	p["sp"] -= Game.SPECIALS[id]["sp"]
	_refresh()
	message.text = Game.SPECIALS[id]["name"] + "!"
	match id:
		"fire_jump":
			await _jump_attack(a, target, 3)
		"thunderhand", "goop_paint":
			var result := await _timing_bar(1.2)
			await _walk(a["node"], target["node"].position + Vector2(-22, 0), 220.0)
			_damage(target, a["pow"] + 2 + (2 if result == "Excellent" else 0))
			_show_rating(result)
			if _hp(target) > 0 and (result == "Excellent" or (result == "Good" and randf() < 0.5)):
				target["stun"] = true
				message.text = "%s is stunned!" % target["name"]
				_refresh()
			await _walk(a["node"], a["home"], 160.0)
			a["node"].facing = Vector2.RIGHT
		"peach_heart":
			var result := await _timing_bar(1.0)
			var heal: int = {"Excellent": 14, "Good": 10, "Miss": 6}[result]
			for ally in _alive(allies):
				_set_hp(ally, _hp(ally) + heal)
			_refresh()
			_show_rating("%s  +%d HP" % [result, heal])
		"fire_breath", "wicked_whirl":
			var result := await _timing_bar(1.0)
			var bonus: int = {"Excellent": 3, "Good": 1, "Miss": -1}[result]
			_show_rating(result)
			for f in _alive(foes):
				_damage(f, a["pow"] + bonus)
				if id == "wicked_whirl" and result == "Excellent" and f["hp"] > 0:
					f["stun"] = true
			_refresh()
		"star_spin":
			var result := await _timing_bar(1.0)
			var bonus: int = {"Excellent": 3, "Good": 1, "Miss": 0}[result]
			_damage(target, a["pow"] + 1 + bonus)
			var heal: int = {"Excellent": 6, "Good": 4, "Miss": 2}[result]
			for ally in _alive(allies):
				_set_hp(ally, _hp(ally) + heal)
			_refresh()
			_show_rating("%s  +%d HP" % [result, heal])
		"pickaxe_pound":
			var result := await _timing_bar(1.1)
			await _walk(a["node"], target["node"].position + Vector2(-22, 0), 220.0)
			var bonus: int = {"Excellent": 4, "Good": 2, "Miss": 0}[result]
			_damage(target, a["pow"] + bonus + int(target["def"]))
			_show_rating(result)
			await _walk(a["node"], a["home"], 160.0)
			a["node"].facing = Vector2.RIGHT
		"shadow_drain":
			var result := await _timing_bar(1.0)
			var bonus: int = {"Excellent": 3, "Good": 1, "Miss": 0}[result]
			var dealt := _damage(target, a["pow"] + bonus)
			_set_hp(a, _hp(a) + dealt)
			_refresh()
			_show_rating("%s  +%d HP" % [result, dealt])
		"poltergust_pull":
			await _poltergust_pull(a, target)
		"shade_veil":
			await _shade_veil(a)
		"rookie_rush":
			await _rookie_rush(a, target)
		"grodus_bolt":
			await _grodus_bolt(a)
		"mimic":
			await _mimic(a, target)
		"bros_tower":
			await _bros_tower(a, target)
	_refresh()
	await _wait(0.6)


func _ask(target: Dictionary) -> void:
	var e: Dictionary = Game.ENEMIES[target["type"]]
	var hurt: float = 1.0 - float(target["hp"]) / target["max_hp"]
	var chance := minf(0.95, e["recruit"] * (1.0 + hurt * 1.5))
	message.text = "You ask %s to join you..." % target["name"]
	await _wait(1.0)
	if randf() < chance:
		Game.player["party"].append(Game.make_member("enemy", target["type"]))
		message.text = "%s joined your party!" % target["name"]
		_show_rating("Lucky!")
		xp_earned += e["xp"] / 2
		target["hp"] = 0
		_refresh()
		var t := create_tween()
		t.tween_property(target["node"], "position", target["node"].position + Vector2(-40, 0), 0.4)
		t.tween_property(target["node"], "modulate:a", 0.0, 0.3)
		await t.finished
	else:
		message.text = "%s refuses!" % target["name"]
		await _wait(0.8)


func _damage(target: Dictionary, amount: int) -> int:
	var dmg := maxi(1, amount - int(target["def"]))
	_set_hp(target, _hp(target) - dmg)
	_flash(target["node"])
	var node: CharacterSprite = target["node"]
	var recoil_dir := 6.0 if target["ally"] else -6.0
	var rtw := create_tween()
	rtw.tween_property(node, "position:x", node.position.x + recoil_dir, 0.05)
	rtw.tween_property(node, "position:x", node.position.x, 0.07)
	_shake(2.5, 0.12)
	_popup(target["node"].position + Vector2(0, -50), str(dmg))
	if not target["ally"] and target["hp"] <= 0:
		var e: Dictionary = Game.ENEMIES[target["type"]]
		xp_earned += e["xp"]
		coins_earned += e["coins"]
		var t := create_tween()
		t.tween_interval(0.3)
		t.tween_property(target["node"], "modulate:a", 0.0, 0.4)
	_refresh()
	return dmg


# --- Partner and recruit moves ---------------------------------------------------

func _move_id(a: Dictionary) -> String:
	return Game.move_of(a["member"].get("kind", "partner"), a["member"]["id"])


## Runs a Game.MOVES move for `a` (a partner, a recruit, or Mimi copying one)
## and returns the rating.
func _partner_move(a: Dictionary, target: Dictionary, id: String) -> String:
	var move: Dictionary = Game.MOVES[id]
	var node: CharacterSprite = a["node"]
	var power: int = a["pow"] + move.get("bonus", 0)
	var result := "Miss"
	message.text = move["name"] + "!"
	match move["kind"]:
		"stomp":
			result = await _jump_attack(a, target)
			_move_extras(move, result, [target])
		"tackle":
			result = await _tackle(a, target, move)
		"throw":
			result = await _timing_bar(1.0)
			var hit: Array = [target]
			if move.get("pierce", false) and result == "Excellent":
				hit += _alive(foes).filter(func(f): return not is_same(f, target)).slice(0, 1)
			for f in hit:
				await _projectile(_middle(a) + Vector2(10, 0), _middle(f), move.get("color", Color.WHITE))
				var extra: int = int(f["def"]) if move.get("ignore_def", false) else 0
				_damage(f, power + extra + {"Excellent": 2, "Good": 1, "Miss": 0}[result])
			_show_rating(result)
			_move_extras(move, result, hit)
		"blast":
			result = await _timing_bar(1.0)
			var hit := _alive(foes)
			for f in hit:
				_burst(_middle(f), Color(1.0, 0.6, 0.15), 22.0)
				_damage(f, power + {"Excellent": 2, "Good": 0, "Miss": -1}[result])
			_show_rating(result)
			_move_extras(move, result, hit)
		"multi":
			await _walk(node, target["node"].position + Vector2(-22, 0), 220.0)
			for i in move.get("hits", 2):
				result = await _timing_bar(0.8)
				_damage(target, power - 1 + {"Excellent": 2, "Good": 1, "Miss": 0}[result])
				if result == "Miss" or _hp(target) <= 0:
					break
			_move_extras(move, result, [target])
			await _walk(node, a["home"], 160.0)
			node.facing = Vector2.RIGHT
	_refresh()
	await _wait(0.4)
	return result


## What an Excellent adds on top of the damage (see Game.MOVES).
func _move_extras(move: Dictionary, result: String, targets: Array) -> void:
	if result != "Excellent" or move.is_empty():
		return
	var notes: Array = []
	for f in targets:
		if f["ally"] or f["hp"] <= 0:
			continue
		if move.get("stun", false):
			f["stun"] = true
			notes.append("%s is stunned!" % f["name"])
		if move.get("burn", 0) > 0:
			f["burn"] = maxi(f["burn"], move["burn"])
			notes.append("%s is burning!" % f["name"])
		if move.get("def_down", 0) > 0 and _lower_def(f, move["def_down"]) > 0:
			notes.append("%s's DEF went down!" % f["name"])
	if move.get("heal", 0) > 0:
		for ally in _alive(allies):
			_set_hp(ally, _hp(ally) + move["heal"])
		notes.append("The party heals %d HP!" % move["heal"])
	if not notes.is_empty():
		message.text = "  ".join(notes)
	_refresh()


## Lowers a foe's DEF for the rest of the battle; returns how much it went down.
func _lower_def(f: Dictionary, amount: int) -> int:
	var drop := mini(amount, int(f["def"]))
	f["def"] -= drop
	f["def_down"] = f.get("def_down", 0) + drop
	return drop


## The enemy has picked who to attack: remember its move for Mimic, and a
## veiled Vivian dodges and hits back. True when the veil took the attack.
func _foe_attack_taken(f: Dictionary, target: Dictionary) -> bool:
	f["last_move"] = Game.move_of("enemy", f["type"])
	if target.get("veil", 0) > 0:
		await _veil_counter(f, target)
		return true
	return false


# --- Signature moves (the design roster) ----------------------------------------

const VEIL_TINT := Color(0.35, 0.2, 0.5, 0.45)
const BROS := ["green", "yellow", "black"]   # who climbs onto the Koopa Bros. tower


## Poltergust Pull (E. Gadd): drags HP out of the target into E. Gadd. An
## Excellent pull also steals what the enemy carries: a Mushroom, then coins.
func _poltergust_pull(a: Dictionary, target: Dictionary) -> void:
	var result := await _timing_bar(1.1)
	var tnode: CharacterSprite = target["node"]
	var stream := _suction(a["node"], tnode)
	var tug := create_tween()
	for i in 3:
		tug.tween_property(tnode, "position", target["home"] + Vector2(-10, 0), 0.12)
		tug.tween_property(tnode, "position", target["home"], 0.12)
	await tug.finished
	stream.queue_free()
	var dealt := _damage(target, a["pow"] + {"Excellent": 3, "Good": 1, "Miss": 0}[result])
	_set_hp(a, _hp(a) + dealt)
	_show_rating("%s  +%d HP" % [result, dealt])
	if result == "Excellent":
		message.text = _steal(target)


func _steal(target: Dictionary) -> String:
	var p: Dictionary = Game.player
	if not target.get("robbed", false):
		target["robbed"] = true
		Game.add_item("mushroom")
		return "Stole a Mushroom from %s!" % target["name"]
	var coins: int = Game.ENEMIES[target["type"]]["coins"]
	p["coins"] += coins
	return "Stole %d coins from %s!" % [coins, target["name"]]


## Shade Veil (Vivian): she sinks into the shadows. The next attack on her
## misses and she hits back with fire (_veil_counter); if nobody attacks
## before her next turn, the fire comes out then (_end_veil).
func _shade_veil(a: Dictionary) -> void:
	var result := await _timing_bar(1.0)
	a["veil"] = a["pow"] + {"Excellent": 3, "Good": 1, "Miss": 0}[result]
	a["veil_burn"] = 2 if result == "Excellent" else 0
	var t := create_tween()
	t.tween_property(a["node"], "modulate", VEIL_TINT, 0.3)
	await t.finished
	message.text = "%s hides in the shadows!" % a["name"]


func _veil_counter(f: Dictionary, target: Dictionary) -> void:
	var fnode: CharacterSprite = f["node"]
	var node: CharacterSprite = target["node"]
	message.text = "%s charges at the shadows..." % f["name"]
	var contact := Vector2(node.position.x + 8, node.position.y)
	fnode.move_velocity = Vector2.LEFT * 100
	await _slide(fnode, contact, 0.5)
	await _slide(fnode, contact + Vector2(-40, 0), 0.2)  # straight through her
	_show_rating("Dodged!")
	await _wait(0.2)
	await _end_veil(target, f)
	fnode.move_velocity = Vector2.RIGHT * 100
	await _slide(fnode, f["home"], 0.4)
	fnode.move_velocity = Vector2.ZERO
	fnode.facing = Vector2.LEFT
	await _wait(0.3)


## Brings `a` out of the shadows with a fireball at `foe` (or any enemy).
func _end_veil(a: Dictionary, foe: Dictionary = {}) -> void:
	var power: int = a["veil"]
	var burn: int = a.get("veil_burn", 0)
	a["veil"] = 0
	var t := create_tween()
	t.tween_property(a["node"], "modulate", Color(1, 1, 1, 1.0 if _hp(a) > 0 else 0.4), 0.2)
	await t.finished
	if foe.is_empty() or _hp(foe) <= 0:
		var alive := _alive(foes)
		if alive.is_empty():
			return
		foe = alive.pick_random()
	message.text = "%s strikes back with fire!" % a["name"]
	await _projectile(_middle(a), _middle(foe), Color(1.0, 0.45, 0.1))
	_burst(_middle(foe), Color(1.0, 0.5, 0.1), 16.0)
	_damage(foe, power)
	if burn > 0 and foe["hp"] > 0:
		foe["burn"] = maxi(foe["burn"], burn)
	_refresh()
	await _wait(0.6)


## Rookie Rush (Rookie Bowser): up to 3 shell bashes, Z as each one hits.
## Every Excellent in a row adds 2 damage; a miss ends the rush.
func _rookie_rush(a: Dictionary, target: Dictionary) -> void:
	var node: CharacterSprite = a["node"]
	var tpos: Vector2 = target["node"].position
	var back := tpos + Vector2(-60, 0)
	var contact := tpos + Vector2(-16, 0)
	await _walk(node, back, 220.0)
	_say("Press {a} as each shell bash hits!")
	var streak := 0
	for i in 3:
		var result := _rate_landing(await _arc(node, back, contact, 6.0, 0.3, true))
		streak = streak + 1 if result == "Excellent" else 0
		_damage(target, a["pow"] - 2 + 2 * streak)
		_show_rating(result + (" x%d" % streak if streak > 1 else ""))
		if result == "Miss" or _hp(target) <= 0 or i == 2:
			break
		await _arc(node, contact, back, 14.0, 0.3, false)
	await _walk(node, a["home"], 200.0)
	node.facing = Vector2.RIGHT


## Grodus Bolt (Grodus): lightning on every enemy. Good lowers DEF by 1,
## Excellent by 2, for the rest of the battle.
func _grodus_bolt(a: Dictionary) -> void:
	var result := await _timing_bar(1.0)
	var bonus: int = {"Excellent": 2, "Good": 1, "Miss": -1}[result]
	var lower: int = {"Excellent": 2, "Good": 1, "Miss": 0}[result]
	var lowered: Array = []
	for f in _alive(foes):
		_bolt(f["node"])
		_damage(f, a["pow"] + bonus)
		if lower > 0 and f["hp"] > 0 and _lower_def(f, lower) > 0:
			lowered.append(f["name"])
	_show_rating(result)
	if not lowered.is_empty():
		message.text = "DEF down: %s" % ", ".join(lowered)


## Mimic (Mimi): copies the last move the target used (what it is known for
## if it hasn't acted yet) and uses it with Mimi's own power and timing.
func _mimic(a: Dictionary, target: Dictionary) -> void:
	var id: String = target.get("last_move", "")
	if id == "" or not Game.MOVES.has(id):
		id = Game.move_of("enemy", target["type"])
	var t := create_tween()
	t.tween_property(a["node"], "modulate", Color(0.75, 0.5, 1.0), 0.15)
	t.tween_property(a["node"], "modulate", Color.WHITE, 0.3)
	message.text = "%s copies %s's %s!" % [a["name"], target["name"], Game.MOVES[id]["name"]]
	await _wait(0.8)
	await _partner_move(a, target, id)


## Bros. Tower (Koopa Bros.): the other three brothers jump onto the stack,
## Z as each one lands (a miss knocks him off), then the tower spins into
## the target. Every brother on it adds damage, more for Excellent.
func _bros_tower(a: Dictionary, target: Dictionary) -> void:
	var node: CharacterSprite = a["node"]
	var base: Vector2 = node.position
	var rise := 20.0 * SCALE
	var tower: Array = []
	var bonus := 1
	_say("Press {a} as each brother lands on the stack!")
	for color in BROS:
		var bro := _make_bro(color, tower.size() + 1)
		var from := base + Vector2(-80, 0)
		var top := base + Vector2(0, -rise * (tower.size() + 1))
		bro.position = from
		var result := _rate_landing(await _arc(bro, from, top, 50.0, 0.5, true))
		_show_rating(result)
		if result == "Miss":
			var fall := create_tween()
			fall.tween_property(bro, "position", Vector2(top.x - 30, base.y), 0.35)
			fall.parallel().tween_property(bro, "modulate:a", 0.0, 0.35)
			fall.tween_callback(bro.queue_free)
		else:
			tower.append(bro)
			bonus += 2 if result == "Excellent" else 1
		await _wait(0.2)
	message.text = "Bros. Tower x%d!" % (tower.size() + 1)
	var dest: Vector2 = target["node"].position + Vector2(-24, 0)
	var t := 0.0
	var spin := 0.0
	while t < 0.6:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t = minf(t + dt, 0.6)
		node.position = base.lerp(dest, t / 0.6)
		for i in tower.size():
			tower[i].position = node.position + Vector2(0, -rise * (i + 1))
		spin += dt
		if spin > 0.05:  # spinning: everyone flips back and forth
			spin = 0.0
			node.facing = Vector2(-signf(node.facing.x) if node.facing.x != 0.0 else 1.0, 0)
			for bro in tower:
				bro.flip_h = not bro.flip_h
	_damage(target, a["pow"] + bonus)
	_show_rating("Bros. Tower!")
	for bro in tower:
		var fade := create_tween()
		fade.tween_property(bro, "modulate:a", 0.0, 0.3)
		fade.tween_callback(bro.queue_free)
	await _walk(node, a["home"], 180.0)
	node.facing = Vector2.RIGHT


## One of the other Koopa Bros. (a palette swap of the koopa_bros sheet),
## standing in the side pose.
func _make_bro(color: String, layer: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load("res://assets/characters/koopa_bros_%s.png" % color)
	s.hframes = Game.CHARACTERS["koopa_bros"]["frames"]
	s.vframes = 3
	s.frame = s.hframes  # first cell of the side row
	s.offset = Vector2(0, -s.texture.get_height() / 6.0)
	s.scale = Vector2(SCALE, SCALE)
	s.z_index = layer
	stage.add_child(s)
	return s


# --- Move effects (simple shapes) --------------------------------------------------

func _middle(actor: Dictionary) -> Vector2:
	var node: CharacterSprite = actor["node"]
	return node.position + Vector2(0, -node.height() * SCALE * 0.5)


func _circle(radius: float, color: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	var points := PackedVector2Array()
	for i in 16:
		points.append(Vector2.from_angle(TAU * i / 16.0) * radius)
	poly.polygon = points
	poly.color = color
	return poly


## Something thrown (a shell, a rose, a fireball) arcs from `from` to `to`.
func _projectile(from: Vector2, to: Vector2, color: Color) -> void:
	var ball := _circle(5.0, color.darkened(0.55))
	ball.add_child(_circle(3.5, color))
	ball.z_index = 10
	stage.add_child(ball)
	await _arc(ball, from, to, 24.0, 0.35, false)
	ball.queue_free()


## A flash that grows and fades: explosions, fire.
func _burst(pos: Vector2, color: Color, radius: float) -> void:
	var b := _circle(radius, color)
	b.position = pos
	b.scale = Vector2(0.2, 0.2)
	b.z_index = 10
	stage.add_child(b)
	var t := create_tween()
	t.tween_property(b, "scale", Vector2.ONE, 0.2)
	t.parallel().tween_property(b, "modulate:a", 0.0, 0.4)
	t.tween_callback(b.queue_free)


## A lightning bolt from the top of the screen down onto `node`.
func _bolt(node: CharacterSprite) -> void:
	var line := Line2D.new()
	line.width = 2.0
	line.default_color = Color(1.0, 0.95, 0.45)
	var bottom := node.position + Vector2(0, -node.height() * SCALE * 0.4)
	var y := 0.0
	while y < bottom.y:
		line.add_point(Vector2(bottom.x + randf_range(-6.0, 6.0), y))
		y += 14.0
	line.add_point(bottom)
	line.z_index = 10
	stage.add_child(line)
	var t := create_tween()
	t.tween_property(line, "modulate:a", 0.0, 0.45)
	t.tween_callback(line.queue_free)


## The Poltergust's stream between E. Gadd and the target.
func _suction(from: CharacterSprite, to: CharacterSprite) -> Node2D:
	var group := Node2D.new()
	group.z_index = 10
	for i in 3:
		var line := Line2D.new()
		line.width = 1.0
		line.default_color = Color(0.7, 0.9, 1.0, 0.85)
		var p0 := from.position + Vector2(12, -from.height() * SCALE * 0.35 + (i - 1) * 3)
		var p1 := to.position + Vector2(0, -to.height() * SCALE * 0.5 + (i - 1) * 8)
		line.points = PackedVector2Array([p0, p0.lerp(p1, 0.5) + Vector2(0, randf_range(-6.0, 6.0)), p1])
		group.add_child(line)
	stage.add_child(group)
	return group


# --- Enemy turn ----------------------------------------------------------------

func _foe_turn(f: Dictionary) -> void:
	if f["burn"] > 0:
		f["burn"] -= 1
		message.text = "%s is hurt by the burn!" % f["name"]
		_damage(f, 2 + int(f["def"]))
		await _wait(0.7)
		if f["hp"] <= 0:
			return
	if f["stun"]:
		f["stun"] = false
		message.text = "%s is stunned and can't move!" % f["name"]
		await _wait(0.8)
		_refresh()
		return
	var target: Dictionary = _alive(allies).pick_random()
	if await _foe_attack_taken(f, target):
		return
	var node: CharacterSprite = target["node"]
	_say("%s charges at %s! Press {a} to jump!", [f["name"], target["name"]])
	var badge := _show_badge(target, "jump")
	var fnode: CharacterSprite = f["node"]
	for i in 6:
		fnode.position.x = f["home"].x + (2.0 if i % 2 == 0 else -2.0)
		await _wait(0.07)
	fnode.position = f["home"]
	# Whether the target is in the air at contact decides the dodge, so
	# pressing too early or too late both fail.
	var start := fnode.position
	var contact := Vector2(node.position.x + 8, node.position.y)
	var t := 0.0
	var duration := randf_range(0.55, 0.85)
	while t < duration:
		await get_tree().process_frame
		t = minf(t + get_process_delta_time(), duration)
		fnode.position = start.lerp(contact, t / duration)
		fnode.move_velocity = Vector2.LEFT * 100
		if Input.is_action_just_pressed("action"):
			node.jump()
	badge.queue_free()
	if node.jump_height > 8.0:
		_show_rating("Dodged!")
		await _slide(fnode, contact + Vector2(-60, 0), 0.25)
	else:
		_damage(target, f["pow"])
		_foe_status(f, target)
		await _slide(fnode, contact + Vector2(20, 0), 0.15)
	await _wait(0.2)
	fnode.move_velocity = Vector2.RIGHT * 100
	await _slide(fnode, f["home"], 0.4)
	fnode.move_velocity = Vector2.ZERO
	fnode.facing = Vector2.LEFT
	await _wait(0.3)


# --- Endings -------------------------------------------------------------------

func _win() -> void:
	var p: Dictionary = Game.player
	p["coins"] += coins_earned
	p["wins"] += 1
	p["hp"] = maxi(1, p["hp"])
	for m in p["party"]:
		m["hp"] = maxi(1, m["hp"])
	var levels := Game.gain_xp(xp_earned)
	message.text = "You won! +%d XP  +%d coins" % [xp_earned, coins_earned]
	_refresh()
	await _wait(1.6)
	await _show_drops(Game.roll_drops(foes.map(func(f): return f["type"])))
	if levels > 0:
		message.text = "Level up! %s is now level %d!" % [Game.character_name(), p["level"]]
		_show_rating("LEVEL UP!")
		_refresh()
		await _wait(1.8)
	_leave("won")


## "Got a Mushroom!" for each item the enemies left behind.
func _show_drops(drops: Array) -> void:
	for id in drops:
		message.text = "Found %s!" % Game.with_article(Game.ITEMS[id]["name"])
		var who: Dictionary = allies[0]
		await _item_pop(who, id)
		await _wait(0.8)


func _lose() -> void:
	message.text = "Your party was defeated... Back to town, a few coins lighter."
	await _wait(2.0)
	_leave("lost")


func _leave(result: String) -> void:
	BattleTransition.out_of_battle(get_tree(), Game.end_battle.bind(result))


# --- Helpers -------------------------------------------------------------------

func _rate_landing(timing: float) -> String:
	if timing >= -LAND_EXCELLENT and timing <= LAND_LATE * 0.5:
		return "Excellent"
	if timing >= -LAND_EARLY and timing <= LAND_LATE:
		return "Good"
	return "Miss"


## A marker sweeps across a bar; press Z while it is in the gold zone.
## badge: which A-button badge to show beside it (see BADGES).
func _timing_bar(duration: float, badge := "burst_red") -> String:
	bar.visible = true
	bar_badge.texture = BADGES[badge]
	bar_badge.visible = true
	var w: float = bar.size.x
	bar_zone.position.x = w * 0.72
	bar_zone.size.x = w * 0.16
	bar_best.position.x = w * 0.77
	bar_best.size.x = w * 0.06
	_say("Press {a} in the gold zone!")
	var t := 0.0
	var result := "Miss"
	await get_tree().process_frame
	while t < duration:
		await get_tree().process_frame
		t += get_process_delta_time()
		var x := w * t / duration
		bar_marker.position.x = x
		if Input.is_action_just_pressed("action"):
			if x >= bar_best.position.x and x <= bar_best.position.x + bar_best.size.x:
				result = "Excellent"
			elif x >= bar_zone.position.x and x <= bar_zone.position.x + bar_zone.size.x:
				result = "Good"
			break
	_show_rating(result)
	await _wait(0.3)
	bar.visible = false
	bar_badge.visible = false
	return result


## Moves a node along a jump arc. When `timed`, returns when Z was pressed
## relative to landing (negative = early), or INF if never pressed.
func _arc(node: Node2D, from: Vector2, to: Vector2, height: float, duration: float, timed: bool) -> float:
	var t := 0.0
	var pressed_at := -1.0
	while t < duration:
		await get_tree().process_frame
		t = minf(t + get_process_delta_time(), duration)
		var k := t / duration
		node.position = from.lerp(to, k) + Vector2(0, -4.0 * height * k * (1.0 - k))
		if timed and pressed_at < 0.0 and Input.is_action_just_pressed("action"):
			pressed_at = t
	if timed and pressed_at < 0.0:
		var g := 0.0
		while g < LAND_LATE:
			await get_tree().process_frame
			g += get_process_delta_time()
			if Input.is_action_just_pressed("action"):
				pressed_at = duration + g
				break
	return pressed_at - duration if pressed_at >= 0.0 else INF


func _walk(node: CharacterSprite, target: Vector2, speed: float) -> void:
	while node.position.distance_to(target) > 0.5:
		await get_tree().process_frame
		var delta := get_process_delta_time()
		var before := node.position
		node.position = node.position.move_toward(target, speed * delta)
		node.move_velocity = (node.position - before) / maxf(delta, 0.0001)
	node.position = target
	node.move_velocity = Vector2.ZERO


func _slide(node: Node2D, target: Vector2, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(node, "position", target, duration)
	await tween.finished


func _flash(node: CanvasItem) -> void:
	var tween := create_tween()
	for i in 3:
		tween.tween_property(node, "self_modulate", Color(1, 0.3, 0.3), 0.06)
		tween.tween_property(node, "self_modulate", Color.WHITE, 0.06)


func _shake(strength := 3.0, duration := 0.14) -> void:
	var tw := create_tween()
	var steps := 4
	for i in steps:
		var off := Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		tw.tween_property(stage, "position", off, duration / float(steps))
	tw.tween_property(stage, "position", Vector2.ZERO, 0.03)


func _popup(pos: Vector2, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"OutlineLabel"
	l.add_theme_font_size_override("font_size", 24)
	l.position = pos - Vector2(10, 0)
	l.pivot_offset = Vector2(10, 12)
	l.scale = Vector2(1.4, 1.4)
	stage.add_child(l)
	var t := create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.08)
	t.parallel().tween_property(l, "position:y", pos.y - 24.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "position:y", pos.y - 16.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(l, "modulate:a", 0.0, 0.22)
	t.tween_callback(l.queue_free)


## Pops up a rating: word art for Excellent / Good / Miss / Dodged! / Lucky!
## (text after two spaces goes under it, e.g. "Good  +10 HP"), gold text
## for anything else.
func _show_rating(text: String) -> void:
	var parts := text.split("  ", false, 1)
	var art: Texture2D = RATING_ART.get(parts[0])
	rating_art.texture = art
	rating_art.visible = art != null
	if art == null:
		rating.text = text
		rating.add_theme_font_size_override("font_size", 24)
		rating.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	else:
		var under: String = parts[1] if parts.size() > 1 else ""
		rating.text = under
		rating.add_theme_font_size_override("font_size", 12)
		rating.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		# Centred in the box, or above the line of text under it.
		var middle := Vector2(rating.size.x / 2.0, rating.size.y / 2.0 if under == "" else 2.0)
		rating_art.position = (middle - art.get_size() / 2.0).floor()
	if _rating_tween:
		_rating_tween.kill()
	rating.pivot_offset = rating.size / 2.0
	rating.modulate.a = 1.0
	rating.scale = Vector2(0.4, 0.4)
	if parts[0] == "Excellent":
		_shake(4.5, 0.16)
	_rating_tween = create_tween()
	_rating_tween.tween_property(rating, "scale", Vector2(1.24, 1.24), 0.08)
	_rating_tween.tween_property(rating, "scale", Vector2.ONE, 0.06)
	_rating_tween.tween_interval(0.55)
	_rating_tween.tween_property(rating, "modulate:a", 0.0, 0.3)


## The red (you) or green (partner) A-button badge by a character's head while
## a timed press is on. It sits on the UI layer so the boxes up top never hide
## it at the top of a jump. Free it when the press is over.
func _show_badge(a: Dictionary, icon: String) -> Sprite2D:
	var badge := Sprite2D.new()
	badge.texture = BADGES["%s_%s" % [icon, "red" if _is_player(a) else "green"]]
	$UI.add_child(badge)
	_badges.append([badge, a["node"]])
	_place_badges()
	return badge


func _place_badges() -> void:
	_badges = _badges.filter(func(b): return is_instance_valid(b[0]) and not b[0].is_queued_for_deletion())
	for b in _badges:
		var node: CharacterSprite = b[1]
		b[0].position = (node.position + Vector2(-20, -node.height() * node.scale.y * 0.75)).round()


## A star that circles stunned foes and a flame by burning ones.
func _status_marks(node: CharacterSprite) -> Node2D:
	var marks := Node2D.new()
	marks.scale = Vector2.ONE / node.scale
	marks.position = Vector2(0, -node.height())
	for tex in [STATUS_STUN, STATUS_BURN]:
		var s := Sprite2D.new()
		s.texture = tex
		s.visible = false
		marks.add_child(s)
	node.add_child(marks)
	return marks


## Message and enemy boxes only show while they have something to say.
func _process(delta: float) -> void:
	if not _presented:
		_setup_presentation(Game.player.get("map", ""))
	_time += delta
	message.get_parent().visible = message.text != ""
	bar_frame.visible = bar.visible
	_place_badges()
	foe_box.visible = foe_list.get_child_count() > 0
	foe_box.reset_size()
	foe_box.position.x = 376.0 - foe_box.size.x
	for f in foes:
		if not f.has("marks"):
			f["marks"] = _status_marks(f["node"])
		var star: Sprite2D = f["marks"].get_child(0)
		var flame: Sprite2D = f["marks"].get_child(1)
		star.visible = f["stun"] and f["hp"] > 0
		flame.visible = f["burn"] > 0 and f["hp"] > 0
		star.position = Vector2(cos(_time * 5.0) * 12.0, -6.0 + sin(_time * 5.0) * 3.0).round()
		flame.position = Vector2(-14, 10 + roundf(sin(_time * 9.0)))
	for a in allies:
		var dizzy: bool = a.get("dizzy", false) and _hp(a) > 0
		var burning: bool = a.get("burn", 0) > 0 and _hp(a) > 0
		if not a.has("marks"):
			if not dizzy and not burning:
				continue
			a["marks"] = _status_marks(a["node"])
		var star: Sprite2D = a["marks"].get_child(0)
		var flame: Sprite2D = a["marks"].get_child(1)
		star.visible = dizzy
		flame.visible = burning
		star.position = Vector2(cos(_time * 5.0) * 12.0, -6.0 + sin(_time * 5.0) * 3.0).round()
		flame.position = Vector2(14, 10 + roundf(sin(_time * 9.0)))


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# --- Status display --------------------------------------------------------------

## One navy box per ally on the bottom bar: face, heart and HP (SP for you).
## Adds an HP box for every ally that doesn't have one yet (allies can join
## after the start, e.g. a co-op partner). _refresh() calls it.
func _build_party_bar() -> void:
	if not _presented:
		return
	for a in allies:
		if a.has("panel"):
			continue
		var panel := PanelContainer.new()
		panel.theme_type_variation = &"NavyPanel"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(row)
		row.add_child(_icon(_face(a["node"].character_id)))
		row.add_child(_icon(ICON_HEART))
		a["hp_label"] = _light_label()
		row.add_child(a["hp_label"])
		if _is_player(a) or a.get("you", false):
			row.add_child(_icon(ICON_BEAN))
			a["sp_label"] = _light_label()
			row.add_child(a["sp_label"])
		party_bar.add_child(panel)
		a["panel"] = panel


## Lights up the box of whoever is choosing; {} lights them all.
func _set_turn(who: Dictionary) -> void:
	for a in allies:
		if a.has("panel"):
			a["panel"].modulate = Color.WHITE if who.is_empty() or is_same(a, who) else Color(0.6, 0.6, 0.65)


func _refresh() -> void:
	var p: Dictionary = Game.player
	_build_party_bar()
	for a in allies:
		if not a.has("hp_label"):
			continue
		var hp := _hp(a)
		var max_hp: int = a["member"]["max_hp"]
		a["hp_label"].text = "%d/%d" % [hp, max_hp]
		a["hp_label"].modulate = Color(1, 0.55, 0.5) if hp * 4 <= max_hp else Color.WHITE
		if a.has("sp_label"):
			a["sp_label"].text = "%d/%d" % [p["sp"], p["max_sp"]]
	for row in foe_list.get_children():
		foe_list.remove_child(row)
		row.queue_free()
	for f in _alive(foes):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var name_label := Label.new()
		name_label.text = f["name"]
		row.add_child(name_label)
		row.add_child(_icon(ICON_HEART))
		var hp := Label.new()
		hp.text = "%d/%d" % [f["hp"], f["max_hp"]]
		row.add_child(hp)
		if f["burn"] > 0:
			row.add_child(_icon(STATUS_BURN))
		if f["stun"]:
			row.add_child(_icon(STATUS_STUN))
		var tags: Array = []
		if f.get("def_down", 0) > 0:
			tags.append("DEF-%d" % f["def_down"])
		if not tags.is_empty():
			var tag_label := Label.new()
			tag_label.text = " ".join(tags)
			tag_label.modulate = Color(0.75, 0.6, 1.0)
			row.add_child(tag_label)
		foe_list.add_child(row)


func _icon(tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _light_label() -> Label:
	var l := Label.new()
	l.theme_type_variation = &"LightLabel"
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## The top of a character's front-facing frame (their head), for the HP boxes.
func _face(id: String) -> Texture2D:
	var tex: Texture2D = load("res://assets/characters/%s.png" % id)
	var info: Dictionary = Game.CHARACTERS.get(id, Game.PARTNERS.get(id, Game.ENEMIES.get(id, {})))
	var cell := Vector2i(tex.get_width() / int(info.get("frames", 8)), tex.get_height() / 3)
	var used := tex.get_image().get_region(Rect2i(Vector2i.ZERO, cell)).get_used_rect()
	var face := AtlasTexture.new()
	face.atlas = tex
	face.region = Rect2(used.position.x, used.position.y, used.size.x, mini(used.size.y, 15))
	return face
