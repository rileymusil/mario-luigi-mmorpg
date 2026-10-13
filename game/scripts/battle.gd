extends Node2D
## Turn-based battle with Superstar Saga style timed presses (Z).
##
## Jump: press Z just as you land on the enemy for a second stomp.
## Specials and partner attacks: press Z when the marker is in the gold zone.
## Enemy turns: press Z so whoever is attacked is in the air when it hits.

const LAND_EARLY := 0.15     # seconds before landing that still count
const LAND_LATE := 0.08
const LAND_EXCELLENT := 0.06
const ALLY_SPOTS := [Vector2(125, 176), Vector2(62, 146), Vector2(52, 192)]
const ENEMY_SPOTS := [Vector2(280, 168), Vector2(320, 145)]
const SCALE := 1.5

## Battle actors: {name, node, hp, max_hp, pow, def, ally, member, type, burn, stun}
var allies: Array = []
var foes: Array = []
var xp_earned := 0
var coins_earned := 0

@onready var stage: Node2D = $Stage
@onready var message: Label = $UI/MessageBox/Message
@onready var status: Label = $UI/StatusBox/Status
@onready var foe_status: Label = $UI/FoeBox/FoeStatus
@onready var rating: Label = $UI/Rating
@onready var menu: ChoiceMenu = $UI/Menu
@onready var bar: Control = $UI/TimingBar
@onready var bar_zone: ColorRect = $UI/TimingBar/Zone
@onready var bar_best: ColorRect = $UI/TimingBar/Best
@onready var bar_marker: ColorRect = $UI/TimingBar/Marker


func _ready() -> void:
	if Game.player.is_empty():
		Game.new_player("mario")
		Game.pending_battle = {"enemies": ["goomba"], "key": "test"}
	var p: Dictionary = Game.player
	if p["map"] == "bowser_castle":
		$Ground.color = Color(0.55, 0.2, 0.1)
	_add_ally({"name": Game.character_name(), "id": p["character"], "member": p})
	for m in p["party"]:
		_add_ally({"name": m["name"], "id": m["id"], "member": m})
	for type in Game.pending_battle.get("enemies", ["goomba"]):
		_add_foe(type)
	bar.visible = false
	rating.text = ""
	_refresh()
	_run_battle()


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
			if result == "fled":
				message.text = "Got away safely!"
				await _wait(1.0)
				Game.end_battle("fled")
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


func _ally_turn(a: Dictionary) -> String:
	var is_player := is_same(a["member"], Game.player)
	var p: Dictionary = Game.player
	var options: Array = []
	var enabled: Array = []
	var infos: Array = []
	if is_player:
		var sp: Dictionary = Game.SPECIALS[Game.CHARACTERS[p["character"]]["special"]]
		options = ["Jump", "%s (%d SP)" % [sp["name"], sp["sp"]], "Mushroom (%d)" % p["mushrooms"], "Ask to join", "Run"]
		enabled = [true, p["sp"] >= sp["sp"], p["mushrooms"] > 0, p["side"] == "evil" and Game.can_recruit(), true]
		infos = ["Stomp! Press Z as you land for a 2nd hit.", sp["info"], "Heal 10 HP.",
			"Evil only: ask an enemy to join your party." if p["side"] == "good" else "Weaker enemies say yes more often.",
			"Try to escape."]
	else:
		options = ["Attack", "Run"]
		enabled = [true, true]
		infos = ["Tackle! Press Z in the gold zone.", "Try to escape."]
	message.text = "%s's turn" % a["name"]
	var choice: String = options[await menu.choose(options, a["name"], false, enabled, infos)]
	message.text = ""
	if choice == "Run":
		if randf() < 0.6:
			return "fled"
		message.text = "Couldn't get away!"
		await _wait(0.8)
		return ""
	if choice.begins_with("Mushroom"):
		p["mushrooms"] -= 1
		var target = await _pick_ally()
		_set_hp(target, _hp(target) + 10)
		_show_rating("+10 HP")
		await _wait(0.8)
		return ""
	var target = await _pick_foe()
	if choice == "Jump":
		await _jump_attack(a, target)
	elif choice == "Attack":
		await _tackle(a, target)
	elif choice == "Ask to join":
		await _ask(target)
	else:
		await _special(a, target)
	return ""


func _pick_foe() -> Dictionary:
	var alive := _alive(foes)
	if alive.size() == 1:
		return alive[0]
	var i := await menu.choose(alive.map(func(f): return "%s  HP %d" % [f["name"], f["hp"]]), "Target")
	return alive[i]


func _pick_ally() -> Dictionary:
	var alive := _alive(allies)
	if alive.size() == 1:
		return alive[0]
	var i := await menu.choose(alive.map(func(a): return "%s  HP %d/%d" % [a["name"], _hp(a), a["member"]["max_hp"]]), "Who?")
	return alive[i]


# --- Attacks -------------------------------------------------------------------

func _jump_attack(a: Dictionary, target: Dictionary, burn := 0) -> String:
	var node: CharacterSprite = a["node"]
	var stand: Vector2 = target["node"].position + Vector2(-40, 0)
	var top: Vector2 = target["node"].position + Vector2(0, -target["node"].height() * SCALE * 0.8)
	message.text = "Press Z just as you land!"
	await _walk(node, stand, 160.0)
	var timing := await _arc(node, node.position, top, 50.0, 0.55, true)
	_damage(target, a["pow"])
	var result := _rate_landing(timing)
	_show_rating(result)
	if result != "Miss":
		await _arc(node, top, top, 38.0, 0.45, false)
		_damage(target, a["pow"] + (1 if result == "Excellent" else 0))
	if burn > 0 and _hp(target) > 0:
		target["burn"] = burn + (1 if result == "Excellent" else 0)
		message.text = "%s is burning!" % target["name"]
	await _arc(node, node.position, stand, 28.0, 0.35, false)
	await _walk(node, a["home"], 160.0)
	node.facing = Vector2.RIGHT
	return result


func _tackle(a: Dictionary, target: Dictionary) -> void:
	var node: CharacterSprite = a["node"]
	var result := await _timing_bar(1.0)
	await _walk(node, target["node"].position + Vector2(-22, 0), 220.0)
	_damage(target, a["pow"] + {"Excellent": 2, "Good": 1, "Miss": 0}[result])
	_show_rating(result)
	await _walk(node, a["home"], 160.0)
	node.facing = Vector2.RIGHT


func _special(a: Dictionary, target: Dictionary) -> void:
	var p: Dictionary = Game.player
	var id: String = Game.CHARACTERS[p["character"]]["special"]
	p["sp"] -= Game.SPECIALS[id]["sp"]
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
			await _walk(a["node"], a["home"], 160.0)
			a["node"].facing = Vector2.RIGHT
		"peach_heart":
			var result := await _timing_bar(1.0)
			var heal: int = {"Excellent": 14, "Good": 10, "Miss": 6}[result]
			for ally in _alive(allies):
				_set_hp(ally, _hp(ally) + heal)
			_show_rating("%s  +%d HP" % [result, heal])
		"fire_breath", "wicked_whirl":
			var result := await _timing_bar(1.0)
			var bonus: int = {"Excellent": 3, "Good": 1, "Miss": -1}[result]
			_show_rating(result)
			for f in _alive(foes):
				_damage(f, a["pow"] + bonus)
				if id == "wicked_whirl" and result == "Excellent" and f["hp"] > 0:
					f["stun"] = true
		"star_spin":
			var result := await _timing_bar(1.0)
			var bonus: int = {"Excellent": 3, "Good": 1, "Miss": 0}[result]
			_damage(target, a["pow"] + 1 + bonus)
			var heal: int = {"Excellent": 6, "Good": 4, "Miss": 2}[result]
			for ally in _alive(allies):
				_set_hp(ally, _hp(ally) + heal)
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
		xp_earned += e["xp"] / 2
		target["hp"] = 0
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
		return
	var target: Dictionary = _alive(allies).pick_random()
	var node: CharacterSprite = target["node"]
	message.text = "%s charges at %s! Press Z to jump!" % [f["name"], target["name"]]
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
	Game.end_battle("won")


func _lose() -> void:
	message.text = "Your party was defeated... Back to town, a few coins lighter."
	await _wait(2.0)
	Game.end_battle("lost")


# --- Helpers -------------------------------------------------------------------

func _rate_landing(timing: float) -> String:
	if timing >= -LAND_EXCELLENT and timing <= LAND_LATE * 0.5:
		return "Excellent"
	if timing >= -LAND_EARLY and timing <= LAND_LATE:
		return "Good"
	return "Miss"


## A marker sweeps across a bar; press Z while it is in the gold zone.
func _timing_bar(duration: float) -> String:
	bar.visible = true
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


func _show_rating(text: String) -> void:
	rating.text = text
	rating.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(0.6)
	tween.tween_property(rating, "modulate:a", 0.0, 0.3)


## Message and enemy boxes only show while they have something to say.
func _process(_delta: float) -> void:
	message.get_parent().visible = message.text != ""
	foe_status.get_parent().visible = foe_status.text != ""
	var box: Control = foe_status.get_parent()
	box.reset_size()
	box.position.x = 376.0 - box.size.x


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _refresh() -> void:
	var lines: Array = []
	for a in allies:
		lines.append("%s %d/%d" % [a["name"], _hp(a), a["member"]["max_hp"]])
	var p: Dictionary = Game.player
	status.text = "  ".join(lines) + "   SP %d/%d" % [p["sp"], p["max_sp"]]
	foe_status.text = "\n".join(_alive(foes).map(func(f): return "%s HP %d/%d%s" % [f["name"], f["hp"], f["max_hp"], " (burn)" if f["burn"] > 0 else ""]))
