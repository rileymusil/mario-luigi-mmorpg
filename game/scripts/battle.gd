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

## Battle actors: {name, node, hp, max_hp, pow, def, ally, member, type, burn, stun}
var allies: Array = []
var foes: Array = []
var xp_earned := 0
var coins_earned := 0
var _rating_tween: Tween
var _time := 0.0
var _badges: Array = []  # [badge sprite, character it follows]
var _presented := false

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
	blocks.highlighted.connect(func(info: String): message.text = info)
	_build_party_bar()
	_refresh()


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
		return [
			{"id": "attack", "label": "Attack", "icon": "hammer", "info": "Tackle! Press Z in the gold zone."},
			{"id": "run", "label": "Run", "icon": "run", "info": "Try to escape."},
		]
	var sp: Dictionary = Game.SPECIALS[Game.CHARACTERS[p["character"]]["special"]]
	return [
		{"id": "jump", "label": "Jump", "icon": "jump", "info": "Stomp! Press Z as you land for a 2nd hit."},
		{"id": "special", "label": "%s (%d SP)" % [sp["name"], sp["sp"]], "icon": "burst",
			"enabled": p["sp"] >= sp["sp"], "info": sp["info"]},
		{"id": "mushroom", "label": "Mushroom (%d)" % p["mushrooms"], "icon": "mushroom",
			"enabled": p["mushrooms"] > 0, "info": "Heal 10 HP."},
		{"id": "ask", "label": "Ask to join", "icon": "hand", "enabled": p["side"] == "evil" and Game.can_recruit(),
			"info": "Evil only: ask an enemy to join your party." if p["side"] == "good" else "Weaker enemies say yes more often."},
		{"id": "run", "label": "Run", "icon": "run", "info": "Try to escape."},
	]


func _ally_turn(a: Dictionary) -> String:
	var p: Dictionary = Game.player
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
		if choice == "mushroom":
			var who = await _pick_ally()
			if who == null:
				continue  # X backs out to the blocks
			p["mushrooms"] -= 1
			_set_hp(who, _hp(who) + 10)
			_refresh()
			_show_rating("+10 HP")
			await _wait(0.8)
			return ""
		var target = await _pick_foe()
		if target == null:
			continue
		match choice:
			"jump":
				await _jump_attack(a, target)
			"attack":
				await _tackle(a, target)
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


func _pick_ally():
	var alive := _alive(allies)
	if alive.size() == 1:
		return alive[0]
	return await _pick(alive, "Who gets the Mushroom?",
		func(a): return "%s %d/%d" % [a["name"], _hp(a), a["member"]["max_hp"]])


## Points at one of `list` with the target pointer; label(t) names each.
func _pick(list: Array, prompt: String, label: Callable):
	list.sort_custom(func(x, y): return x["node"].position.x < y["node"].position.x)
	message.text = prompt
	var i := await targets.choose(list.map(func(t): return {"node": t["node"], "label": label.call(t)}))
	message.text = ""
	return list[i] if i >= 0 else null


# --- Attacks -------------------------------------------------------------------

func _jump_attack(a: Dictionary, target: Dictionary, burn := 0) -> String:
	var node: CharacterSprite = a["node"]
	var stand: Vector2 = target["node"].position + Vector2(-40, 0)
	var top: Vector2 = target["node"].position + Vector2(0, -target["node"].height() * SCALE * 0.8)
	message.text = "Press Z just as you land!"
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


func _tackle(a: Dictionary, target: Dictionary) -> void:
	var node: CharacterSprite = a["node"]
	var result := await _timing_bar(1.0, "hammer_green")
	await _walk(node, target["node"].position + Vector2(-22, 0), 220.0)
	_damage(target, a["pow"] + {"Excellent": 2, "Good": 1, "Miss": 0}[result])
	_show_rating(result)
	await _walk(node, a["home"], 160.0)
	node.facing = Vector2.RIGHT


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
	var node: CharacterSprite = target["node"]
	message.text = "%s charges at %s! Press Z to jump!" % [f["name"], target["name"]]
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
	if levels > 0:
		message.text = "Level up! %s is now level %d!" % [Game.character_name(), p["level"]]
		_show_rating("LEVEL UP!")
		_refresh()
		await _wait(1.8)
	_leave("won")


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
	message.text = "Press Z in the gold zone!"
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


func _popup(pos: Vector2, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"OutlineLabel"
	l.add_theme_font_size_override("font_size", 24)
	l.position = pos - Vector2(10, 0)
	stage.add_child(l)
	var t := create_tween()
	t.tween_property(l, "position:y", pos.y - 20, 0.5)
	t.tween_property(l, "modulate:a", 0.0, 0.3)
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
	_rating_tween = create_tween()
	_rating_tween.tween_property(rating, "scale", Vector2(1.2, 1.2), 0.08)
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


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# --- Status display --------------------------------------------------------------

## One navy box per ally on the bottom bar: face, heart and HP (SP for you).
func _build_party_bar() -> void:
	for a in allies:
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
		if _is_player(a):
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
