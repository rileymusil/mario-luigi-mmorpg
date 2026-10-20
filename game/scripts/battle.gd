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
const ENEMY_SPOTS := [Vector2(280, 168), Vector2(320, 145), Vector2(250, 140)]  # the 3rd: a boss's helper
const BOSS_SPOT := Vector2(296, 172)
## Phones held upright: the battle is drawn PORTRAIT_WIDTH game pixels wide
## instead of 384 (so everything is bigger; Game._process reads
## portrait_width), and the two sides stand PORTRAIT_SQUEEZE closer together
## so they still fit (see _spot).
const PORTRAIT_WIDTH := 288
const PORTRAIT_SQUEEZE := 0.75
var portrait_width := PORTRAIT_WIDTH
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
	"hammer_red": preload("res://assets/battle/prompt_hammer_red.png"),
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
var xp_bonus := 0  # part of xp_earned that's a bonus (fighting with your party partner)
var coins_earned := 0
var _rating_tween: Tween
var _time := 0.0
var _badges: Array = []  # [badge sprite, character it follows]
var _presented := false
var _hint := ""         # the hint in the message box, before key names went in
var _hint_args: Array = []
var _hint_shown := ""

## Combo meter: each Excellent and each dodge adds one; a Miss or a hit taken
## ends it. From x2 your hits do COMBO_STEP more damage per step (up to
## COMBO_MAX steps) and every COMBO_SP_EVERY-th step gives you 1 SP back.
## The grade at the end of a won battle (S, A, B, C, see _grade) pays
## GRADE_BONUS more XP and coins. Normal and co-op battles only (_extras).
const COMBO_STEP := 0.1
const COMBO_MAX := 5
const COMBO_SP_EVERY := 3
const GRADE_BONUS := {"S": 0.5, "A": 0.25, "B": 0.1, "C": 0.0}
var combo := 0
var best_combo := 0
var presses := {"Excellent": 0, "Good": 0, "Miss": 0}
var hurt := 0           # damage your side took
var grade := ""         # set once the battle is won (see _grade)
var _combo_label: Label
var _flash_rect: ColorRect

@onready var background: TextureRect = $Background
@onready var stage: Node2D = $Stage
@onready var message: Label = $UI/MessageBox/Message
@onready var party_bar: HFlowContainer = $UI/PartyBar  # wraps onto a 2nd row when it must (co-op)
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
	get_tree().root.size_changed.connect(_layout_battle)
	party_bar.sort_children.connect(_party_bar_to_bottom)
	if _extras():
		_combo_label = Label.new()
		_combo_label.theme_type_variation = &"OutlineLabel"
		_combo_label.add_theme_font_size_override("font_size", 16)
		_combo_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		_combo_label.visible = false
		$UI.add_child(_combo_label)
	_layout_battle()
	_refresh()


func _layout_battle() -> void:
	var vp := get_viewport_rect().size
	var safe := Game.get_safe_rect()

	var backdrop: ColorRect = $Backdrop
	backdrop.position = Vector2.ZERO
	backdrop.size = vp
	background.position = Vector2.ZERO
	background.size = vp
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE

	var center_offset := ((vp - Vector2(384, 216)) / 2.0).round()
	stage.position = center_offset

	var msg_box: Control = message.get_parent()
	msg_box.size.x = minf(safe.size.x - 16.0, 368.0)
	msg_box.position = Vector2(roundf(safe.position.x + (safe.size.x - msg_box.size.x) / 2.0), safe.position.y + 4.0)

	_place_party_bar()

	foe_box.reset_size()
	foe_box.position = Vector2(safe.end.x - foe_box.size.x - 8.0, safe.position.y + 30.0)

	var frame_x := roundf((vp.x - bar_frame.size.x) / 2.0)
	var frame_y := roundf((vp.y - bar_frame.size.y) / 2.0)
	bar_frame.position = Vector2(frame_x, frame_y)
	bar.position = Vector2(frame_x + 8.0, frame_y + 6.0)
	bar_badge.position = Vector2(frame_x - 24.0, frame_y - 4.0)

	rating.position.x = roundf((vp.x - rating.size.x) / 2.0)
	rating.position.y = roundf(vp.y * 0.28)
	if _combo_label:
		_combo_label.position = Vector2(msg_box.position.x + 4.0, msg_box.position.y + msg_box.size.y + 2.0)

	blocks.size = vp
	targets.size = vp
	menu.position = Vector2(safe.position.x + 8.0, safe.position.y + 30.0)


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
	node.position = _spot(ALLY_SPOTS[allies.size()])
	stage.add_child(node)
	var m: Dictionary = info["member"]
	allies.append({"name": info["name"], "node": node, "member": m, "ally": true, "home": node.position,
		"pow": m["pow"], "def": m["def"]})


## Where someone stands: a spot from ALLY_SPOTS / ENEMY_SPOTS, pulled in
## towards the middle on a phone held upright.
func _spot(p: Vector2) -> Vector2:
	if not Game.is_portrait():
		return p
	return Vector2(roundf(192.0 + (p.x - 192.0) * PORTRAIT_SQUEEZE), p.y)


func _add_foe(type: String) -> void:
	var e: Dictionary = Game.foe_info(type)
	var boss := Game.BOSSES.has(type)
	var node := CharacterSprite.new()
	node.character_id = type
	node.facing = Vector2.LEFT
	node.scale = Vector2(SCALE, SCALE)
	node.position = _spot(BOSS_SPOT if boss and foes.is_empty() else ENEMY_SPOTS[foes.size()])
	stage.add_child(node)
	if boss or Game.BOSS_MINIONS.has(type):
		node.scale = Vector2.ONE * node.battle_scale(SCALE)  # the biggest bosses would fill the screen
	var count := foes.filter(func(f): return f["type"] == type).size()
	foes.append({"name": e["name"] + (" B" if count > 0 else ""), "type": type, "node": node, "ally": false,
		"hp": e["hp"], "max_hp": e["hp"], "pow": e["pow"], "def": e["def"], "burn": 0, "stun": false,
		"home": node.position, "scale": node.scale.x, "minion": Game.BOSS_MINIONS.has(type)})
	if boss:
		# A rematch (beaten before) pays half the XP and coins.
		foes.back().merge({"boss": true, "phase": 1, "speed": 1.0, "stolen": 0, "rematch": Game.boss_wins(type) > 0})


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
	for f in foes:
		if f.get("boss", false):
			message.text = Game.BOSSES[f["type"]]["battle_line"]
			await _wait(1.4)
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
	var reserve: Array = p["party"].filter(func(m):
		for ally in allies:
			if ally.get("member") == m:
				return false
		return true
	)
	var can_switch: bool = not reserve.is_empty() and allies.size() > 1

	if not _is_player(a):
		var commands := []
		for id in Game.member_moves(a["member"]):
			var move: Dictionary = Game.MOVES[id]
			commands.append({"id": "move:" + id, "label": move["name"], "icon": "hammer" if commands.is_empty() else "burst",
				"info": move["info"]})
		commands.append({"id": "guard", "label": "Guard", "icon": "guard",
			"info": "Take a defensive stance: halve damage taken & restore 4 SP."})
		commands.append(_items_command())
		if can_switch:
			commands.append({"id": "switch", "label": "Switch", "icon": "switch",
				"info": "Tag in another partner from reserve."})
		commands.append(_run_command())
		return commands

	var sp: Dictionary = Game.SPECIALS[Game.CHARACTERS[p["character"]]["special"]]
	var has_partner: bool = allies.size() > 1 and _alive(allies).size() > 1
	var commands: Array = [
		{"id": "jump", "label": "Jump", "icon": "jump", "info": "Stomp! Press {a} as you land for a 2nd hit."},
		{"id": "special", "label": "%s (%d SP)" % [sp["name"], sp["sp"]], "icon": "burst",
			"enabled": p["sp"] >= sp["sp"], "info": sp["info"]},
	]
	if has_partner:
		commands.append({
			"id": "team", "label": "Bros. Strike (8 SP)", "icon": "burst",
			"enabled": p["sp"] >= 8,
			"info": "Dual team attack with your partner! Massive damage & combo boost."
		})
	commands.append({"id": "guard", "label": "Guard", "icon": "guard",
		"info": "Take a defensive stance: halve incoming damage & restore 4 SP."})
	commands.append({"id": "scan", "label": "Scan", "icon": "scan",
		"info": "Analyze enemy HP meter, vulnerabilities, and attacks."})
	commands.append(_items_command())
	if can_switch:
		commands.append({"id": "switch", "label": "Switch", "icon": "switch",
			"info": "Tag in another partner from reserve."})
	if p["side"] == "evil" and Game.can_recruit():
		commands.append({"id": "ask", "label": "Ask to join", "icon": "hand",
			"info": "Ask an enemy to join your evil army."})
	commands.append(_run_command())
	return commands


## No running from a boss.
func _run_command() -> Dictionary:
	if _boss_fight():
		return {"id": "run", "label": "Run", "icon": "run", "enabled": false, "info": "You can't run from a boss!"}
	return {"id": "run", "label": "Run", "icon": "run", "info": "Try to escape."}


func _boss_fight() -> bool:
	return foes.any(func(f): return f.get("boss", false))


func _ally_turn(a: Dictionary) -> String:
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
		if choice == "guard":
			a["guarding"] = true
			var p_ref: Dictionary = Game.player
			p_ref["sp"] = mini(p_ref["max_sp"], p_ref["sp"] + 4)
			_refresh()
			message.text = "%s guards! (+4 SP, damage halved)" % a["name"]
			_show_rating("Guarded! +4 SP")
			_burst(_middle(a), Color(0.4, 0.7, 1.0), 10.0)
			await _wait(0.9)
			return ""
		if choice == "switch":
			if not await _switch_partner_turn(a):
				continue
			return ""
		if choice == "scan":
			var target = await _pick_foe()
			if target == null:
				continue
			var info: Dictionary = Game.foe_info(target["type"])
			target["scanned"] = true
			var atk_str := ", ".join(info.get("attacks", ["charge"]))
			var desc := "%s: HP %d/%d | DEF %d, POW %d | Moves: %s" % [target["name"], _hp(target), target["max_hp"], target["def"], target["pow"], atk_str]
			message.text = desc
			_show_rating("Scanned!")
			_refresh()
			await _wait(2.2)
			return ""
		var target = await _pick_foe()
		if target == null:
			continue
		match choice:
			"jump":
				await _jump_attack(a, target)
			_ when choice.begins_with("move:"):
				await _partner_move(a, target, choice.trim_prefix("move:"))
			"ask":
				await _ask(target)
			"special":
				await _special(a, target)
			"team":
				await _team_attack(a, target)
		return ""
	return ""


## A co-op Team Attack (coop_battle.gd); nothing in a normal battle.
func _team_attack(a: Dictionary, target: Dictionary) -> void:
	var p: Dictionary = Game.player
	p["sp"] -= 8
	_refresh()
	message.text = "Bros. Strike!"
	var partner: Dictionary = allies[1] if allies.size() > 1 else a
	var anode: CharacterSprite = a["node"]
	var pnode: CharacterSprite = partner["node"]
	var fnode: CharacterSprite = target["node"]
	var target_pos: Vector2 = fnode.position + Vector2(-32, 0)
	await _walk(anode, target_pos + Vector2(-16, 0), 200.0)
	if partner != a:
		await _walk(pnode, target_pos + Vector2(16, 0), 200.0)

	var timing1 := await _arc(anode, anode.position, fnode.position + Vector2(0, -28), 42.0, 0.45, true)
	var r1 := _rate_landing(timing1)
	_damage(target, a["pow"] + (3 if r1 == "Excellent" else 1))
	_show_rating(r1)
	_shake(3.0, 0.12)

	if partner != a and _hp(target) > 0:
		var timing2 := await _arc(pnode, pnode.position, fnode.position + Vector2(0, -32), 48.0, 0.45, true)
		var r2 := _rate_landing(timing2)
		_damage(target, partner["pow"] + (4 if r2 == "Excellent" else 1))
		_show_rating("BROS FINISH!" if r2 == "Excellent" else r2)
		_shake(4.2, 0.16)
		_combo_hit()
		_combo_hit()

	await _walk(anode, a["home"], 180.0)
	if partner != a:
		await _walk(pnode, partner["home"], 180.0)
		pnode.facing = Vector2.RIGHT
	anode.facing = Vector2.RIGHT


func _switch_partner_turn(_a: Dictionary) -> bool:
	var p: Dictionary = Game.player
	var reserve: Array = p["party"].filter(func(m):
		for ally in allies:
			if ally.get("member") == m:
				return false
		return true
	)
	if reserve.is_empty():
		message.text = "No partners in reserve to switch with!"
		await _wait(0.8)
		return false
	var labels := []
	for m in reserve:
		labels.append("%s (Lv.%d, %d/%d HP)" % [m["name"], m.get("level", 1), m["hp"], m["max_hp"]])
	menu.max_rows = 4
	_say("Switch which partner in? {b} to cancel.")
	var i := await menu.choose(labels, "Switch", true)
	message.text = ""
	if i < 0:
		return false
	var new_member: Dictionary = reserve[i]

	if allies.size() > 1:
		var old_partner: Dictionary = allies[1]
		message.text = "%s tags out!" % old_partner["name"]
		var tw := create_tween()
		tw.tween_property(old_partner["node"], "position:x", old_partner["node"].position.x - 60.0, 0.35)
		tw.tween_property(old_partner["node"], "modulate:a", 0.0, 0.2)
		await tw.finished
		old_partner["node"].queue_free()

		var node := CharacterSprite.new()
		node.character_id = new_member.get("character", "toad")
		node.facing = Vector2.RIGHT
		node.scale = Vector2(SCALE, SCALE)
		node.position = old_partner["home"] + Vector2(-60, 0)
		node.modulate.a = 0.0
		stage.add_child(node)

		var tw_in := create_tween()
		tw_in.tween_property(node, "position:x", old_partner["home"].x, 0.35)
		tw_in.parallel().tween_property(node, "modulate:a", 1.0, 0.2)
		await tw_in.finished

		allies[1] = {
			"name": new_member["name"], "node": node, "member": new_member, "ally": true,
			"home": old_partner["home"], "pow": new_member["pow"], "def": new_member["def"]
		}
		message.text = "%s enters the battle!" % new_member["name"]
		_show_rating("Tag In!")
		_shake(2.0, 0.1)
		await _wait(0.8)
		_refresh()
		return true
	return false


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
	if item.has("damage") or item.get("target_all", false):
		return _alive(foes)
	if item.get("party_all", false):
		return [allies[0]]
	if item.has("sp") or item.get("sp_max", false):
		var p: Dictionary = Game.player
		return allies.filter(func(a): return _is_player(a) and _hp(a) > 0 and p["sp"] < p["max_sp"])
	if item.has("revive"):
		return allies.filter(func(a): return _hp(a) <= 0 and a["node"].visible)
	if item.get("cure", false):
		return _alive(allies).filter(func(a): return a.get("burn", 0) > 0 or a.get("dizzy", false))
	if item.has("hp") or item.get("hp_max", false):
		return _alive(allies).filter(func(a): return _hp(a) < a["member"]["max_hp"])
	return _alive(allies)


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
		if list.size() > 1 and not item.get("party_all", false) and not item.get("target_all", false):
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
	if item.get("party_all", false):
		var heal: int = int(item.get("hp", 0))
		for ally in _alive(allies):
			var before := _hp(ally)
			_set_hp(ally, before + heal)
		text = "Party +%d HP!" % heal
	elif item.has("damage"):
		var dmg: int = int(item["damage"])
		if item.get("target_all", false):
			for foe in _alive(foes):
				_damage(foe, dmg)
				if item.get("burn", 0) > 0:
					foe["burn"] = int(item["burn"])
				if item.get("stun", false):
					foe["stun"] = true
			text = "%d DMG to all!" % dmg
		else:
			_damage(who, dmg)
			text = "%d DMG!" % dmg
	elif item.get("hp_max", false):
		var before := _hp(who)
		_set_hp(who, who["member"]["max_hp"])
		text = "HP Max! (+%d)" % (_hp(who) - before)
	elif item.get("sp_max", false):
		var before: int = p["sp"]
		p["sp"] = p["max_sp"]
		text = "SP Max! (+%d)" % (p["sp"] - before)
	elif item.has("hp") and item.has("sp"):
		var before_hp := _hp(who)
		_set_hp(who, before_hp + int(item["hp"]))
		var before_sp: int = p["sp"]
		p["sp"] = mini(p["max_sp"], p["sp"] + int(item["sp"]))
		text = "+%d HP, +%d SP" % [int(item["hp"]), int(item["sp"])]
	elif item.has("hp"):
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
	elif item.has("spd"):
		who["spd"] = int(who.get("spd", 10)) + int(item["spd"])
		text = "SPD +%d" % int(item["spd"])
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
	a["guarding"] = false
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
		"thunderhand":
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
		"rookie_rush":
			await _rookie_rush(a, target)
		"grodus_bolt":
			await _grodus_bolt(a)
		"bros_tower":
			await _bros_tower(a, target)
	_refresh()
	await _wait(0.6)


func _ask(target: Dictionary) -> void:
	var e: Dictionary = Game.foe_info(target["type"])
	var boss: bool = target.get("boss", false)
	var hurt: float = 1.0 - float(target["hp"]) / target["max_hp"]
	var chance := minf(0.95, e["recruit"] * (1.0 + hurt * 1.5))
	message.text = "You ask %s to join you..." % target["name"]
	await _wait(1.0)
	if target.get("minion", false):
		message.text = "%s only listens to its boss!" % target["name"]
		await _wait(1.0)
		return
	if boss and Game.has_boss_partner():
		message.text = "%s won't share a party with another boss!" % target["name"]
		await _wait(1.0)
		return
	if randf() < chance:
		var to := Game.add_member(Game.make_member("boss" if boss else "enemy", target["type"]))
		target["joined"] = true
		message.text = "%s joined your party!" % target["name"] if to == "party" \
			else "%s joined! It waits at %s." % [target["name"], Game.home_name()]
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
	if target.get("guarding", false):
		dmg = maxi(1, int(dmg * 0.5))
	var boosted := false
	if _extras() and not target["ally"] and combo >= 2:
		dmg += ceili(dmg * COMBO_STEP * mini(combo, COMBO_MAX))
		boosted = true
	if _extras() and not target["ally"] and randf() < 0.14:
		dmg = int(dmg * 1.5) + 1
		boosted = true
		_show_rating("Lucky!")
	var was_up := _hp(target) > 0
	_set_hp(target, _hp(target) - dmg)
	_flash(target["node"])
	var node: CharacterSprite = target["node"]
	var recoil_dir := 6.0 if target["ally"] else -6.0
	var rtw := create_tween()
	rtw.tween_property(node, "position:x", node.position.x + recoil_dir, 0.05)
	rtw.tween_property(node, "position:x", node.position.x, 0.07)
	var ko: bool = was_up and _hp(target) <= 0
	_shake(4.0 if target["ally"] or ko else 2.5, 0.18 if ko else 0.12)
	# A ! makes the number gold and bigger (see _popup): combo hits and finishing blows.
	_popup(target["node"].position + Vector2(0, -50), str(dmg) + ("!" if boosted or (ko and not target["ally"]) else ""))
	if _extras():
		_burst(_middle(target), Color(1.0, 0.95, 0.6), 9.0 if dmg < 10 else 14.0)
		if target["ally"]:
			hurt += dmg
			_combo_break()
		elif ko:
			_ko_flash()
	if not target["ally"] and target["hp"] <= 0 and was_up:  # rewards once, not per extra hit
		var e: Dictionary = Game.foe_info(target["type"])
		var share := 2 if target.get("rematch", false) else 1
		xp_earned += e["xp"] / share
		coins_earned += e["coins"] / share
		var t := create_tween()
		t.tween_interval(0.3)
		t.tween_property(target["node"], "modulate:a", 0.0, 0.4)
	_refresh()
	return dmg


# --- Partner and recruit moves ---------------------------------------------------

func _move_id(a: Dictionary) -> String:
	return Game.move_of(a["member"].get("kind", "partner"), a["member"]["id"])


## Runs a Game.MOVES move for `a` (a partner or a recruit)
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


# --- Signature moves (the design roster) ----------------------------------------

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
	var coins: int = mini(int(Game.foe_info(target["type"])["coins"]), 10)
	p["coins"] += coins
	return "Stole %d coins from %s!" % [coins, target["name"]]


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
	if f.get("boss", false):
		await _boss_turn(f)
		return
	await _foe_attack(f, _alive(allies).pick_random())


# --- Enemy attacks ---------------------------------------------------------------
# An enemy picks one of its "attacks" (Game.ENEMIES) each turn. All of them are
# dodged the same way, by being in the air when the hit lands (so pressing too
# early or too late both fail), but each has its own rhythm to read.

const THROW_COLORS := {"shell_toss": Color(0.35, 0.8, 0.35), "shell_spin": Color(0.4, 0.6, 1.0),
	"bone_toss": Color(0.95, 0.95, 0.9)}


func _foe_attack(f: Dictionary, target: Dictionary) -> void:
	var kinds: Array = Game.foe_info(f["type"]).get("attacks", ["charge"])
	match kinds.pick_random():
		"feint":
			await _foe_feint(f, target)
		"double":
			await _foe_double(f, target)
		"throw":
			await _foe_throw(f, target)
		_:
			await _foe_charge(f, target)


## The foe shakes in place before it moves.
func _wind_up(f: Dictionary, times: int) -> void:
	var fnode: CharacterSprite = f["node"]
	for i in times:
		fnode.position.x = f["home"].x + (2.0 if i % 2 == 0 else -2.0)
		await _wait(0.07)
	fnode.position = f["home"]


## The foe runs to `to` in `duration` while {a} jumps the target. True if the
## target was in the air when it got there.
func _rush(f: Dictionary, target: Dictionary, to: Vector2, duration: float) -> bool:
	var node: CharacterSprite = target["node"]
	var fnode: CharacterSprite = f["node"]
	var start := fnode.position
	hit_at = Time.get_ticks_msec() + int(duration * 1000.0)
	await _dodge_window(duration, node, func(k: float):
		fnode.position = start.lerp(to, k)
		fnode.move_velocity = Vector2.LEFT * 100)
	hit_at = -1
	return node.jump_height > 8.0


## A dodge or a hit at the end of a rush.
func _land(f: Dictionary, target: Dictionary, dodged: bool, power: int) -> void:
	if dodged:
		var node: CharacterSprite = target["node"]
		if node.jump_height > 10.0:
			var counter_dmg: int = maxi(2, int(target.get("pow", 5) * 0.8))
			_damage(f, counter_dmg)
			_combo_hit()
			_show_rating("Counter! %d" % counter_dmg)
			_shake(2.5, 0.12)
		else:
			_show_rating("Dodged!")
	else:
		_damage(target, power)
		_foe_status(f, target)


## Back home after an attack.
func _foe_home(f: Dictionary) -> void:
	var fnode: CharacterSprite = f["node"]
	await _wait(0.2)
	fnode.move_velocity = Vector2.RIGHT * 100
	await _slide(fnode, f["home"], 0.4)
	fnode.move_velocity = Vector2.ZERO
	fnode.facing = Vector2.LEFT
	await _wait(0.3)


func _contact(target: Dictionary) -> Vector2:
	return Vector2(target["node"].position.x + 8, target["node"].position.y)


## Runs straight in.
func _foe_charge(f: Dictionary, target: Dictionary) -> void:
	_say("%s charges at %s! Press {a} to jump!", [f["name"], target["name"]])
	var badge := _show_badge(target, "jump")
	await _wind_up(f, 6)
	var contact := _contact(target)
	var dodged := await _rush(f, target, contact, randf_range(0.55, 0.85))
	badge.queue_free()
	_land(f, target, dodged, f["pow"])
	await _slide(f["node"], contact + (Vector2(-60, 0) if dodged else Vector2(20, 0)), 0.25 if dodged else 0.15)
	await _foe_home(f)


## Creeps halfway, stops for a moment, then dashes: jump for the dash, not the creep.
func _foe_feint(f: Dictionary, target: Dictionary) -> void:
	_say("%s creeps toward %s... Wait for it, then {a}!", [f["name"], target["name"]])
	var badge := _show_badge(target, "jump")
	await _wind_up(f, 4)
	var contact := _contact(target)
	var fnode: CharacterSprite = f["node"]
	var halfway: Vector2 = fnode.position.lerp(contact, 0.45)
	await _dodge_window(0.4, target["node"], func(k: float):
		fnode.position = f["home"].lerp(halfway, k)
		fnode.move_velocity = Vector2.LEFT * 40)
	fnode.move_velocity = Vector2.ZERO
	await _dodge_window(randf_range(0.35, 0.8), target["node"])  # the pause
	var dodged := await _rush(f, target, contact, randf_range(0.28, 0.4))
	badge.queue_free()
	_land(f, target, dodged, f["pow"])
	await _slide(fnode, contact + (Vector2(-60, 0) if dodged else Vector2(20, 0)), 0.25 if dodged else 0.15)
	await _foe_home(f)


## Hits, hops back and hits again at once: jump each one.
func _foe_double(f: Dictionary, target: Dictionary) -> void:
	_say("%s attacks twice! Press {a} for each hit!", [f["name"]])
	var badge := _show_badge(target, "jump")
	await _wind_up(f, 6)
	var contact := _contact(target)
	var fnode: CharacterSprite = f["node"]
	var power := ceili(f["pow"] * 0.7)
	var dodged := await _rush(f, target, contact, randf_range(0.5, 0.7))
	_land(f, target, dodged, power)
	await _slide(fnode, contact + Vector2(48, 0), 0.22)
	if _hp(target) > 0:
		dodged = await _rush(f, target, contact, randf_range(0.3, 0.45))
		_land(f, target, dodged, power)
	badge.queue_free()
	await _slide(fnode, contact + (Vector2(-60, 0) if dodged else Vector2(20, 0)), 0.25 if dodged else 0.15)
	await _foe_home(f)


## Sends something rolling along the ground: jump over it as it reaches you.
func _foe_throw(f: Dictionary, target: Dictionary) -> void:
	_say("%s throws something at %s! Press {a} to jump over it!", [f["name"], target["name"]])
	var badge := _show_badge(target, "jump")
	await _wind_up(f, 6)
	var color: Color = THROW_COLORS.get(Game.foe_info(f["type"]).get("move", ""), Color(1.0, 0.55, 0.2))
	var ball := _circle(6.0, color.darkened(0.55))
	ball.add_child(_circle(4.5, color))
	ball.z_index = 10
	stage.add_child(ball)
	var from: Vector2 = f["node"].position + Vector2(-14, -7)
	var to: Vector2 = target["node"].position + Vector2(2, -7)
	var duration := randf_range(0.6, 1.0)
	_mirror_fx(["proj", roundi(from.x), roundi(from.y), roundi(to.x), roundi(to.y), color.to_html(false)])
	hit_at = Time.get_ticks_msec() + int(duration * 1000.0)
	await _dodge_window(duration, target["node"], func(k: float):
		ball.position = from.lerp(to, k)
		ball.rotation = -k * TAU * 3.0)
	hit_at = -1
	var dodged: bool = target["node"].jump_height > 8.0
	badge.queue_free()
	_land(f, target, dodged, f["pow"])
	var t := create_tween()
	t.tween_property(ball, "position", to + Vector2(-80, 0) if dodged else to + Vector2(10, -10), 0.25)
	t.parallel().tween_property(ball, "modulate:a", 0.0, 0.25)
	t.tween_callback(ball.queue_free)
	await _wait(0.5)


# --- Combo, grade and hit effects --------------------------------------------------

## Combo, grade and the extra hit effects are on in normal and co-op battles,
## not in PvP (pvp_battle.gd) or on a co-op partner's screen (coop_guest.gd,
## which only shows the host's battle).
func _extras() -> bool:
	var path: String = get_script().resource_path
	return not path.ends_with("pvp_battle.gd") and not path.ends_with("coop_guest.gd")


func _count_rating(word: String) -> void:
	if presses.has(word):
		presses[word] += 1
	if word == "Excellent" or word == "Dodged!":
		_combo_up()
	elif word == "Miss":
		_combo_break()


func _combo_up() -> void:
	combo += 1
	best_combo = maxi(best_combo, combo)
	if combo % COMBO_SP_EVERY == 0 and Game.player["sp"] < Game.player["max_sp"]:
		Game.player["sp"] += 1
		_refresh()
	_show_combo()


func _combo_break() -> void:
	if combo == 0:
		return
	combo = 0
	_show_combo()


func _show_combo() -> void:
	if _combo_label == null:
		return
	_combo_label.visible = combo >= 2
	_combo_label.text = "Combo x%d  +%d%% damage" % [combo, roundi(COMBO_STEP * 100.0 * mini(combo, COMBO_MAX))]
	_combo_label.pivot_offset = Vector2(0, _combo_label.size.y / 2.0)
	_combo_label.scale = Vector2(1.3, 1.3)
	create_tween().tween_property(_combo_label, "scale", Vector2.ONE, 0.15)


## The grade for a won battle: S for taking no damage and missing nothing,
## A for barely a scratch, B for under 40% of your side's HP, C otherwise.
func grade_for(hurt_share: float, misses: int) -> String:
	if hurt_share <= 0.0 and misses == 0:
		return "S"
	if hurt_share <= 0.15 and misses <= 1:
		return "A"
	if hurt_share <= 0.4:
		return "B"
	return "C"


## Grades the win and adds its bonus to the XP and coins (once).
func _grade() -> void:
	if grade != "":
		return
	var total := 0
	for a in allies:
		total += int(a["member"]["max_hp"])
	grade = grade_for(float(hurt) / maxf(1.0, total), presses["Miss"])
	var bonus: float = GRADE_BONUS[grade]
	var xp_more := roundi(xp_earned * bonus)
	var coins_more := roundi(coins_earned * bonus)
	xp_earned += xp_more
	coins_earned += coins_more
	_show_rating("Rank %s!" % grade)
	message.text = "Rank %s! Best combo x%d." % [grade, best_combo]
	if xp_more > 0 or coins_more > 0:
		message.text += " Bonus +%d XP +%d coins" % [xp_more, coins_more]
	await _wait(1.6)


## Time slows for a moment (an Excellent).
func _slowmo(scale: float, seconds: float) -> void:
	Engine.time_scale = scale
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0


## A white flash over the screen when an enemy goes down.
func _ko_flash() -> void:
	if _flash_rect == null:
		_flash_rect = ColorRect.new()
		_flash_rect.color = Color(1, 1, 1)
		_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		$UI.add_child(_flash_rect)
		$UI.move_child(_flash_rect, 0)
	_flash_rect.size = get_viewport_rect().size
	_flash_rect.modulate.a = 0.55
	create_tween().tween_property(_flash_rect, "modulate:a", 0.0, 0.25)
	_slowmo(0.4, 0.12)


# --- Bosses ----------------------------------------------------------------------
# Bosses (Game.BOSSES) attack with patterns from Game.BOSS_ATTACKS, each with
# its own timed press: jump over a dash, a slam, a swoop or things rolling
# along the ground, jump as a burrowing boss bursts out under you, hammer
# thrown things back just before they hit, jump each thing that falls. Some
# call helpers in. Below half HP they change phase: stronger, faster, and a
# third attack joins in.

const BOSS_TINT := Color(1.0, 0.8, 0.8)
const HAMMER_EARLY := 0.22   # how long before a hit {a} still hammers it back
const HAMMER_LATE := 0.05
const HAMMER_BEST := 0.1     # this close is an Excellent counter
const DIRT := Color(0.55, 0.4, 0.25)

## When (Time.get_ticks_msec) the boss attack under way lands, -1 between
## hits. Only scripted tests read it, to time their presses.
var hit_at := -1


func _boss_turn(f: Dictionary) -> void:
	var b: Dictionary = Game.BOSSES[f["type"]]
	if f["phase"] == 1 and f["hp"] * 2 <= f["max_hp"]:
		await _boss_phase(f, b)
	var pool: Array = b["attacks"].duplicate()
	if f["phase"] >= 2:
		pool.append(b["phase2"])
	if not _can_summon():
		pool = pool.filter(func(a): return Game.BOSS_ATTACKS[a]["kind"] != "summon")
	# Not the same attack three times running.
	if pool.size() > 1 and f.get("last_attack", "") == f.get("before_last", ""):
		pool.erase(f.get("last_attack", ""))
	var id: String = pool.pick_random()
	f["before_last"] = f.get("last_attack", "")
	f["last_attack"] = id
	var atk: Dictionary = Game.BOSS_ATTACKS[id]
	var power: int = f["pow"] + int(atk.get("power", 0))
	var fnode: CharacterSprite = f["node"]
	message.text = "%s uses %s!" % [f["name"], atk["name"]]
	if atk["kind"] != "burrow" and atk["kind"] != "swoop":
		fnode.play_attack()
	await _wait(0.7)
	if atk["kind"] == "rain":
		await _boss_rain(f, atk, power)
		return
	if atk["kind"] == "summon":
		if await _boss_summon(f, atk):
			return
		atk = {"name": atk["name"], "kind": "dash"}  # no room for another helper
	var target: Dictionary = _alive(allies).pick_random()
	if target.get("remote", false):
		await _boss_remote(f, target)
		return
	match atk["kind"]:
		"dash":
			for i in int(atk.get("count", 1)):
				if _hp(target) <= 0 or _hp(f) <= 0:
					break
				await _boss_dash(f, target, atk, power)
		"slam":
			await _boss_slam(f, target, power)
		"volley":
			await _boss_volley(f, target, atk, power)
		"barrage":
			await _boss_barrage(f, target, atk, power)
		"burrow":
			await _boss_burrow(f, target, power)
		"swoop":
			await _boss_swoop(f, target, power)
	hit_at = -1


## Half HP: the boss gets stronger and faster, and its third attack joins in.
## Some change shape too (BOSSES "phase2_form").
func _boss_phase(f: Dictionary, b: Dictionary) -> void:
	f["phase"] = 2
	f["pow"] += 2
	f["speed"] = 0.8
	message.text = b["phase_line"]
	var node: CharacterSprite = f["node"]
	var form: String = b.get("phase2_form", "")
	if form != "":
		node.character_id = form
		node.scale = Vector2.ONE * node.battle_scale(SCALE)
		f["scale"] = node.scale.x
		_burst(_middle(f), Color(1.0, 0.9, 0.5), 30.0)
	var t := create_tween()
	for i in 3:
		t.tween_property(node, "modulate", Color(1.0, 0.45, 0.45), 0.12)
		t.tween_property(node, "modulate", Color.WHITE, 0.12)
	t.tween_property(node, "modulate", BOSS_TINT, 0.2)
	_shake(4.0, 0.4)
	_show_rating("Phase 2!")
	await t.finished
	await _wait(1.0)


## Whether a boss may call a helper in (not in co-op: the partner's screen
## only knows the foes the battle started with).
func _can_summon() -> bool:
	return true


## In a co-op battle, an attack on the partner (who dodges on their own
## screen). coop_battle.gd plays it as an ordinary charge.
func _boss_remote(f: Dictionary, target: Dictionary) -> void:
	await _boss_dash(f, target, {}, f["pow"])


## Waits `seconds`, jumping `node` whenever {a} is pressed. each(k), if
## given, runs every frame with k going from 0 to 1.
func _dodge_window(seconds: float, node: CharacterSprite, each := Callable()) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t = minf(t + get_process_delta_time(), seconds)
		if each.is_valid():
			each.call(t / seconds)
		if Input.is_action_just_pressed("action"):
			node.jump()


## The boss runs at the target: {a} so they are in the air when it hits.
func _boss_dash(f: Dictionary, target: Dictionary, atk: Dictionary, power: int) -> void:
	var node: CharacterSprite = target["node"]
	var fnode: CharacterSprite = f["node"]
	_say("%s charges at %s! Press {a} to jump!", [f["name"], target["name"]])
	var badge := _show_badge(target, "jump")
	for i in 8:
		fnode.position.x = f["home"].x + (3.0 if i % 2 == 0 else -3.0)
		await _wait(0.06)
	fnode.position = f["home"]
	var start := fnode.position
	var contact := Vector2(node.position.x + 12, node.position.y)
	var duration: float = randf_range(0.5, 0.8) * f["speed"]
	hit_at = Time.get_ticks_msec() + int(duration * 1000.0)
	await _dodge_window(duration, node, func(k: float):
		fnode.position = start.lerp(contact, k)
		fnode.move_velocity = Vector2.LEFT * 100)
	badge.queue_free()
	if node.jump_height > 8.0:
		_show_rating("Dodged!")
		await _slide(fnode, contact + Vector2(-60, 0), 0.25)
	else:
		_damage(target, power)
		var steal: int = mini(int(atk.get("steal", 0)), int(Game.player["coins"]))
		if steal > 0:
			Game.player["coins"] -= steal
			f["stolen"] += steal
			message.text = "%s swiped %d coins!" % [f["name"], steal]
		await _slide(fnode, contact + Vector2(24, 0), 0.15)
	await _wait(0.2)
	fnode.move_velocity = Vector2.RIGHT * 100
	await _slide(fnode, f["home"], 0.4)
	fnode.move_velocity = Vector2.ZERO
	fnode.facing = Vector2.LEFT
	await _wait(0.3)


## The boss leaps high and comes down on the target: {a} to jump clear just
## before it lands.
func _boss_slam(f: Dictionary, target: Dictionary, power: int) -> void:
	var node: CharacterSprite = target["node"]
	var fnode: CharacterSprite = f["node"]
	var k0: float = f.get("scale", SCALE)
	_say("%s leaps at %s! Press {a} to jump as it lands!", [f["name"], target["name"]])
	var badge := _show_badge(target, "jump")
	var squat := create_tween()
	squat.tween_property(fnode, "scale", Vector2(k0 * 1.15, k0 * 0.85), 0.25)
	squat.tween_property(fnode, "scale", Vector2(k0, k0), 0.08)
	await squat.finished
	var land := Vector2(node.position.x + 6, node.position.y)
	var duration: float = randf_range(0.75, 1.0) * f["speed"]
	var from: Vector2 = fnode.position
	hit_at = Time.get_ticks_msec() + int(duration * 1000.0)
	await _dodge_window(duration, node, func(k: float):
		fnode.position = from.lerp(land, k) + Vector2(0, -4.0 * 90.0 * k * (1.0 - k)))
	badge.queue_free()
	_shake(5.0, 0.2)
	_burst(land, Color(0.95, 0.85, 0.6), 26.0)
	if node.jump_height > 8.0:
		_show_rating("Dodged!")
	else:
		_damage(target, power)
	await _wait(0.35)
	await _arc(fnode, fnode.position, f["home"], 40.0, 0.45, false)
	fnode.facing = Vector2.LEFT
	await _wait(0.3)


## Things thrown one after another at the target: {a} just before each one
## hits swings a hammer that sends it back at the boss.
func _boss_volley(f: Dictionary, target: Dictionary, atk: Dictionary, power: int) -> void:
	var count: int = int(atk.get("count", 1)) + (1 if f["phase"] >= 2 else 0)
	var color: Color = atk.get("color", Color.WHITE)
	for i in count:
		if _hp(target) <= 0 or _hp(f) <= 0:
			break
		_say("%s! Press {a} just before it hits to hammer it back!", [atk["name"]])
		var badge := _show_badge(target, "hammer")
		var from := _middle(f) + Vector2(-14, 0)
		var to := _middle(target) + Vector2(8, 0)
		var duration: float = randf_range(0.6, 0.9) * f["speed"]
		var ball := _circle(6.0, color.darkened(0.55))
		ball.add_child(_circle(4.5, color))
		ball.z_index = 10
		stage.add_child(ball)
		_mirror_fx(["proj", roundi(from.x), roundi(from.y), roundi(to.x), roundi(to.y), color.to_html(false)])
		hit_at = Time.get_ticks_msec() + int(duration * 1000.0)
		var pressed := INF
		var t := 0.0
		while t < duration:
			await get_tree().process_frame
			t = minf(t + get_process_delta_time(), duration)
			var k := t / duration
			ball.position = from.lerp(to, k) + Vector2(0, -4.0 * 20.0 * k * (1.0 - k))
			if pressed == INF and Input.is_action_just_pressed("action"):
				pressed = t - duration
		if pressed == INF:  # a moment's grace after it reaches you
			var g := 0.0
			while g < HAMMER_LATE:
				await get_tree().process_frame
				g += get_process_delta_time()
				if Input.is_action_just_pressed("action"):
					pressed = g
					break
		badge.queue_free()
		if pressed >= -HAMMER_EARLY and pressed <= HAMMER_LATE:
			var best := absf(pressed) <= HAMMER_BEST
			_show_rating("%s  Counter!" % ("Excellent" if best else "Good"))
			_swing(target)
			await _arc(ball, ball.position, _middle(f), 30.0, 0.3, false)
			ball.queue_free()
			_burst(_middle(f), color, 18.0)
			_damage(f, int(target["pow"]) + (3 if best else 1))
		else:
			ball.queue_free()
			_burst(to, color, 14.0)
			_damage(target, power)
			_maybe_burn(target, atk)
		await _wait(0.35)


func _maybe_burn(target: Dictionary, atk: Dictionary) -> void:
	if randf() < float(atk.get("burn", 0.0)) and _hp(target) > 0:
		target["burn"] = 2
		message.text = "%s is burning!" % target["name"]


## A quick hammer swing in front of whoever hits something back.
func _swing(a: Dictionary) -> void:
	var node: CharacterSprite = a["node"]
	var t := create_tween()
	t.tween_property(node, "position:x", a["home"].x + 10.0, 0.06)
	t.tween_property(node, "position:x", a["home"].x, 0.12)


## Things bounce along the ground at the target one after another, some
## quick, some slow: {a} to jump each one.
func _boss_barrage(f: Dictionary, target: Dictionary, atk: Dictionary, power: int) -> void:
	var count: int = int(atk.get("count", 3)) + (1 if f["phase"] >= 2 else 0)
	var color: Color = atk.get("color", Color.WHITE)
	var node: CharacterSprite = target["node"]
	_say("%s! Press {a} to jump each one!", [atk["name"]])
	var badge := _show_badge(target, "jump")
	for i in count:
		if _hp(target) <= 0 or _hp(f) <= 0:
			break
		var from := Vector2(f["node"].position.x - 20.0, node.position.y - 5.0)
		var to := Vector2(node.position.x - 2.0, node.position.y - 5.0)
		var ball := _circle(5.0, color.darkened(0.5))
		ball.add_child(_circle(3.5, color))
		ball.z_index = 10
		ball.position = from
		stage.add_child(ball)
		_mirror_fx(["proj", roundi(from.x), roundi(from.y), roundi(to.x), roundi(to.y), color.to_html(false)])
		var duration: float = randf_range(0.45, 0.8) * f["speed"]
		hit_at = Time.get_ticks_msec() + int(duration * 1000.0)
		await _dodge_window(duration, node, func(k: float):
			ball.position = from.lerp(to, k) + Vector2(0, -absf(sin(k * 9.0)) * 4.0))
		if node.jump_height > 8.0:
			_show_rating("Dodged!")
			var away := create_tween()
			away.tween_property(ball, "position", to + Vector2(-70, 0), 0.25)
			away.tween_callback(ball.queue_free)
		else:
			ball.queue_free()
			_burst(to, color, 12.0)
			_damage(target, power)
			_maybe_burn(target, atk)
		# The next one comes sooner or later: watch, don't count.
		await _dodge_window(randf_range(0.05, 0.4), node)
	hit_at = -1
	badge.queue_free()
	await _wait(0.4)


## The boss digs in, a mound of dirt runs under the target, rumbles (once
## for nothing, sometimes) and the boss bursts out: {a} as it bursts.
func _boss_burrow(f: Dictionary, target: Dictionary, power: int) -> void:
	var fnode: CharacterSprite = f["node"]
	var node: CharacterSprite = target["node"]
	var k0: float = f.get("scale", SCALE)
	_say("%s digs underground! Press {a} to jump as it bursts out!", [f["name"]])
	var badge := _show_badge(target, "jump")
	fnode.play_attack(true)
	var sink := create_tween()
	sink.tween_property(fnode, "scale", Vector2(k0 * 1.2, 0.05), 0.4)
	await sink.finished
	fnode.visible = false
	fnode.end_attack()
	var mound := _circle(7.0, DIRT)
	mound.scale = Vector2(1.8, 0.6)
	mound.z_index = 9
	mound.position = f["home"]
	stage.add_child(mound)
	var spot: Vector2 = node.position + Vector2(4, 1)
	var from: Vector2 = f["home"]
	await _dodge_window(0.7 * f["speed"], node, func(k: float):
		mound.position = from.lerp(spot, k) + Vector2(0, sin(k * 20.0)))
	if randf() < 0.5:  # a fake rumble
		await _dodge_window(0.18, node, func(k: float): mound.position.x = spot.x + sin(k * 40.0) * 2.0)
		await _dodge_window(randf_range(0.35, 0.7), node)
	else:
		await _dodge_window(randf_range(0.1, 0.4), node)
	var rumble: float = 0.3 * f["speed"]
	hit_at = Time.get_ticks_msec() + int(rumble * 1000.0)
	await _dodge_window(rumble, node, func(k: float):
		mound.position.x = spot.x + sin(k * 60.0) * 3.0
		mound.scale = Vector2(1.8, 0.6) * (1.0 + k * 0.5))
	mound.queue_free()
	badge.queue_free()
	_burst(spot, DIRT, 20.0)
	_shake(4.0, 0.2)
	fnode.position = spot
	fnode.scale = Vector2(k0, 0.1)
	fnode.visible = true
	var pop := create_tween()
	pop.tween_property(fnode, "scale", Vector2(k0, k0), 0.12)
	if node.jump_height > 8.0:
		_show_rating("Dodged!")
	else:
		_damage(target, power)
	await _wait(0.45)
	await _arc(fnode, fnode.position, f["home"], 40.0, 0.45, false)
	fnode.facing = Vector2.LEFT
	await _wait(0.3)


## The boss flies off the top of the screen, its shadow finds the target,
## sometimes it drops halfway and pulls back up (a feint), then it dives:
## {a} as it lands.
func _boss_swoop(f: Dictionary, target: Dictionary, power: int) -> void:
	var fnode: CharacterSprite = f["node"]
	var node: CharacterSprite = target["node"]
	_say("%s flies up! Press {a} to jump as it dives!", [f["name"]])
	var badge := _show_badge(target, "jump")
	fnode.play_attack(true)
	var up := create_tween()
	up.tween_property(fnode, "position", f["home"] + Vector2(-40, -280), 0.45 * f["speed"])
	await up.finished
	var shadow := _circle(9.0, Color(0, 0, 0, 0.35))
	shadow.scale = Vector2(1.5, 0.45)
	shadow.z_index = 9
	shadow.position = node.position + Vector2(6, 1)
	stage.add_child(shadow)
	var land := Vector2(node.position.x + 6, node.position.y)
	var top := Vector2(land.x + 30, -70)
	fnode.position = top
	await _dodge_window(randf_range(0.25, 0.55), node)
	if randf() < 0.5:  # the feint
		var half := top.lerp(land, 0.45)
		await _dodge_window(0.2 * f["speed"], node, func(k: float): fnode.position = top.lerp(half, k))
		await _dodge_window(0.25, node, func(k: float): fnode.position = half.lerp(top, k))
		await _dodge_window(randf_range(0.15, 0.4), node)
	var duration: float = 0.45 * f["speed"]
	hit_at = Time.get_ticks_msec() + int(duration * 1000.0)
	await _dodge_window(duration, node, func(k: float): fnode.position = top.lerp(land, k * k))
	shadow.queue_free()
	badge.queue_free()
	fnode.end_attack()
	_shake(4.0, 0.2)
	_burst(land, Color(0.9, 0.9, 1.0), 22.0)
	if node.jump_height > 8.0:
		_show_rating("Dodged!")
	else:
		_damage(target, power)
	await _wait(0.35)
	await _arc(fnode, fnode.position, f["home"], 40.0, 0.45, false)
	fnode.facing = Vector2.LEFT
	await _wait(0.3)


## Calls a helper (the attack's `minion`) into the battle. Returns false if
## there's no room for one (the boss attacks instead).
func _boss_summon(f: Dictionary, atk: Dictionary) -> bool:
	if foes.size() >= ENEMY_SPOTS.size() or _alive(foes).size() >= 3:
		return false
	_add_foe(str(atk.get("minion", "goomba")))
	var helper: Dictionary = foes.back()
	var hnode: CharacterSprite = helper["node"]
	hnode.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(hnode, "modulate:a", 1.0, 0.4)
	_burst(_middle(helper), Color(0.85, 0.75, 1.0), 18.0)
	message.text = "%s called %s into the battle!" % [f["name"], helper["name"]]
	_refresh()
	_layout_battle()
	await _wait(1.0)
	return true


## Something falls on every ally in turn: {a} to jump it (you jump for your
## partners too). A partner in co-op dodges on their own screen.
func _boss_rain(f: Dictionary, atk: Dictionary, power: int) -> void:
	var color: Color = atk.get("color", Color.WHITE)
	for a in _alive(allies):
		if _alive(foes).is_empty():
			return
		if a.get("remote", false):
			await _boss_remote(f, a)
			continue
		var node: CharacterSprite = a["node"]
		_say("%s! Press {a} to jump before it lands on %s!", [atk["name"], a["name"]])
		var badge := _show_badge(a, "jump")
		var land := node.position + Vector2(0, -6)
		var from := Vector2(land.x + 30, -20)
		var rock := _circle(7.0, color.darkened(0.5))
		rock.add_child(_circle(5.0, color))
		rock.z_index = 10
		stage.add_child(rock)
		_mirror_fx(["proj", roundi(from.x), roundi(from.y), roundi(land.x), roundi(land.y), color.to_html(false)])
		var duration: float = randf_range(0.7, 1.0) * f["speed"]
		hit_at = Time.get_ticks_msec() + int(duration * 1000.0)
		await _dodge_window(duration, node, func(k: float): rock.position = from.lerp(land, k))
		badge.queue_free()
		rock.queue_free()
		_burst(land, color, 20.0)
		if node.jump_height > 8.0:
			_show_rating("Dodged!")
		else:
			_damage(a, power)
		await _wait(0.4)
	hit_at = -1


## Extra effects for a co-op partner's screen (coop_battle.gd sends them).
func _mirror_fx(_fx_entry: Array) -> void:
	pass


## After beating a boss: its item, the coins it swiped, the win in the save,
## and an evil player can ask it to join.
func _boss_won(f: Dictionary) -> void:
	var id: String = f["type"]
	var b: Dictionary = Game.BOSSES[id]
	var first: bool = not f.get("rematch", false)
	message.text = b["won_line"]
	await _wait(1.4)
	if f["stolen"] > 0:
		Game.player["coins"] += f["stolen"]
		message.text = "Got back the %d coins %s swiped!" % [f["stolen"], f["name"]]
		f["stolen"] = 0
		await _wait(1.0)
	var rewards: Array = b["reward"] if first else b["rematch_reward"]
	if not rewards.is_empty() and typeof(rewards[0]) != TYPE_ARRAY:
		rewards = [rewards]  # a single [item, count]
	for reward in rewards:
		var got := Game.add_item(reward[0], int(reward[1]))
		if got > 0:
			var item_name: String = Game.ITEMS[reward[0]]["name"]
			message.text = "%s dropped %s!" % [f["name"], Game.with_article(item_name) if got == 1 else "%d %ss" % [got, item_name]]
			await _item_pop(allies[0], reward[0])
			await _wait(0.9)
	Game.mark_boss_beaten(id)
	if first:
		message.text = "%s is beaten! (You can fight again for smaller rewards.)" % f["name"]
		_show_rating("Boss beaten!")
		await _wait(1.6)
	await _boss_join(f)


## Evil players can ask a boss they just beat to join (one boss per party).
func _boss_join(f: Dictionary) -> void:
	var p: Dictionary = Game.player
	if p["side"] != "evil" or not Game.can_recruit() or Game.has_boss_partner() or _hp(f) > 0:
		return
	if f.get("joined", false):
		return
	var node: CharacterSprite = f["node"]
	var t := create_tween()
	t.tween_property(node, "modulate", Color.WHITE, 0.4)
	await t.finished
	_say("%s gets back up... Ask %s to join your party?" % [f["name"], f["name"]])
	menu.max_rows = 0
	var i := await menu.choose(["Ask to join", "Leave it"], "", true)
	if i != 0:
		message.text = ""
		return
	message.text = "You ask %s to join you..." % f["name"]
	await _wait(1.0)
	if randf() < Game.BOSS_JOIN_CHANCE:
		var to := Game.add_member(Game.make_member("boss", f["type"]))
		message.text = "%s joined your party!" % f["name"] if to == "party" \
			else "%s joined! It waits at %s." % [f["name"], Game.home_name()]
		_show_rating("Lucky!")
	else:
		message.text = "%s refuses! (Beat it again and ask again.)" % f["name"]
		var fade := create_tween()
		fade.tween_property(node, "modulate:a", 0.0, 0.4)
	await _wait(1.4)


# --- Endings -------------------------------------------------------------------

func _win() -> void:
	if _extras():
		await _grade()
	var p: Dictionary = Game.player
	p["coins"] += coins_earned
	p["wins"] += 1
	p["hp"] = maxi(1, p["hp"])
	for m in p["party"]:
		m["hp"] = maxi(1, m["hp"])
	var levels := Game.gain_xp(xp_earned)
	var grown := Game.party_gain_xp(xp_earned)
	message.text = "You won! +%d XP  +%d coins" % [xp_earned, coins_earned]
	if xp_bonus > 0:
		message.text = "You won! +%d XP (party +%d)  +%d coins" % [xp_earned, xp_bonus, coins_earned]
	_refresh()
	await _wait(1.6)
	await _show_drops(Game.roll_drops(foes.map(func(f): return f["type"])))
	for f in foes:
		if f.get("boss", false):
			await _boss_won(f)
	if levels > 0:
		message.text = "Level up! %s is now level %d!" % [Game.character_name(), p["level"]]
		_show_rating("LEVEL UP!")
		_refresh()
		await _wait(1.8)
	await _party_level_lines(grown)
	_leave("won")


## Shows the party's level-ups after a win (Game.party_gain_xp).
func _party_level_lines(lines: Array) -> void:
	for line in lines:
		message.text = line
		_refresh()
		await _wait(1.3)


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
	Engine.time_scale = 1.0
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
	var base := ((get_viewport_rect().size - Vector2(384, 216)) / 2.0).round()
	var steps := 4
	for i in steps:
		var off := Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		tw.tween_property(stage, "position", base + off, duration / float(steps))
	tw.tween_property(stage, "position", base, 0.03)


func _popup(pos: Vector2, text: String) -> void:
	var l := Label.new()
	var big := text.ends_with("!") and text.length() > 1 and text.left(1).is_valid_int()
	l.text = text.trim_suffix("!") if big else text
	l.theme_type_variation = &"OutlineLabel"
	l.add_theme_font_size_override("font_size", 32 if big else 24)
	if big:
		l.add_theme_color_override("font_color", Color(1.0, 0.82, 0.2))
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
	if _extras():
		_count_rating(parts[0])
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
		if _extras():
			_slowmo(0.35, 0.14)
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
		var origin := node.get_global_transform_with_canvas().origin
		b[0].position = (origin + Vector2(-20, -node.height() * node.scale.y * 0.75)).round()


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
	foe_box.position.x = Game.get_safe_rect().end.x - 8.0 - foe_box.size.x
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

## The HP boxes along the bottom of the safe area. Called again whenever they
## change (they are empty when the layout first runs, so their height was 0).
func _place_party_bar() -> void:
	var safe := Game.get_safe_rect()
	# Narrow screens (a phone held upright): drop the hearts so the boxes fit.
	# Still too wide (a co-op battle with both parties): two rows.
	var width := 0.0
	for squeeze in [false, true]:
		for a in allies:
			if a.has("heart"):
				a["heart"].visible = not squeeze
		width = _party_bar_width()
		if width <= safe.size.x - 4.0:
			break
	if width > safe.size.x - 4.0:
		var widest := 0.0
		for box in party_bar.get_children():
			widest = maxf(widest, box.get_combined_minimum_size().x)
		width = ceilf(width / 2.0) + widest  # half of them on each row
	party_bar.size.x = minf(width, safe.size.x - 4.0)
	party_bar.position.x = roundf(safe.position.x + (safe.size.x - party_bar.size.x) / 2.0)
	_party_bar_to_bottom()


## Sits the bar on the bottom edge. Again each time it re-flows (its height
## is only known once the boxes are laid out at the new width).
func _party_bar_to_bottom() -> void:
	party_bar.size.y = 0.0  # as short as its rows allow
	party_bar.position.y = Game.get_safe_rect().end.y - party_bar.size.y - 2.0


## How wide the HP boxes are side by side, in one row.
func _party_bar_width() -> float:
	var width := 0.0
	var boxes := party_bar.get_children()
	for box in boxes:
		width += box.get_combined_minimum_size().x
	return width + 4.0 * maxi(0, boxes.size() - 1)


## One navy box per ally on the bottom bar: face, heart and HP (SP for you).
## Adds an HP box for every ally that doesn't have one yet (allies can join
## after the start, e.g. a co-op partner). _refresh() calls it.
func _build_party_bar() -> void:
	if not _presented:
		return
	for a in allies:
		if a.has("panel") or a.get("no_box", false):
			continue
		var panel := PanelContainer.new()
		panel.theme_type_variation = &"NavyPanel"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(row)
		row.add_child(_icon(_face(a["node"].character_id)))
		a["heart"] = _icon(ICON_HEART)
		row.add_child(a["heart"])
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
	_place_party_bar.call_deferred()
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
	var info: Dictionary = Game.CHARACTERS.get(id, Game.PARTNERS.get(id, Game.foe_info(id)))
	var cell := Vector2i(tex.get_width() / int(info.get("frames", 8)), tex.get_height() / Game.sheet_rows(info))
	var used := tex.get_image().get_region(Rect2i(Vector2i.ZERO, cell)).get_used_rect()
	var face := AtlasTexture.new()
	face.atlas = tex
	face.region = Rect2(used.position.x, used.position.y, used.size.x, mini(used.size.y, 15))
	return face
