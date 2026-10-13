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
	if a.get("veil", 0) > 0:
		await _end_veil(a)  # nobody attacked the shadows: the fire comes out anyway
		if _alive(foes).is_empty():
			return ""
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
		var move: Dictionary = Game.MOVES[_move_id(a)]
		options = [move["name"], "Run"]
		enabled = [true, true]
		infos = [move["info"], "Try to escape."]
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
	elif not is_player:
		await _partner_move(a, target, _move_id(a))
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


## move: an entry of Game.MOVES (bonus, ignore_def and the Excellent extras).
func _tackle(a: Dictionary, target: Dictionary, move: Dictionary = {}) -> String:
	var node: CharacterSprite = a["node"]
	var result := await _timing_bar(1.0)
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
		"poltergust_pull":
			await _poltergust_pull(a, target)
		"shade_veil":
			await _shade_veil(a)
		"rookie_rush":
			await _rookie_rush(a, target)
		"magic_cube":
			await _magic_cube(a, target)
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


func _status_tags(f: Dictionary) -> String:
	var tags: Array = []
	if f["burn"] > 0:
		tags.append("burn")
	if f["stun"]:
		tags.append("stun")
	if f.get("cube", 0) > 0:
		tags.append("cube")
	if f.get("def_down", 0) > 0:
		tags.append("DEF-%d" % f["def_down"])
	return " (%s)" % ", ".join(tags) if not tags.is_empty() else ""


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
		p["mushrooms"] += 1
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
	message.text = "Press Z as each shell bash hits!"
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


## Magic Cube (Dimentio): traps the target; on its next turn the cube
## explodes instead of it acting (_cube_explode). A miss only fizzles.
func _magic_cube(a: Dictionary, target: Dictionary) -> void:
	var result := await _timing_bar(1.0)
	if result == "Miss":
		message.text = "The cube fizzles!"
		_damage(target, a["pow"] - 1)
		return
	target["cube"] = a["pow"] + (6 if result == "Excellent" else 3)
	target["cube_node"] = _make_cube(target["node"])
	message.text = "%s is trapped in a Magic Cube!" % target["name"]


func _cube_explode(f: Dictionary) -> void:
	message.text = "The Magic Cube around %s explodes!" % f["name"]
	var box: Variant = f.get("cube_node")
	if box != null and is_instance_valid(box):
		box.queue_free()
	f["cube_node"] = null
	var power: int = f["cube"]
	f["cube"] = 0
	f["stun"] = false  # being stuck in the cube already cost it this turn
	_burst(_middle(f), Color(1.0, 0.85, 0.3), 30.0)
	_damage(f, power)
	await _wait(0.9)


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
	message.text = "Press Z as each brother lands on the stack!"
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


## A see-through box around a trapped enemy (a child of its sprite).
func _make_cube(node: CharacterSprite) -> Node2D:
	var h := node.height() + 6.0
	var w := h * 0.8
	var corners := PackedVector2Array([Vector2(-w / 2, -h), Vector2(w / 2, -h), Vector2(w / 2, 3), Vector2(-w / 2, 3)])
	var box := Node2D.new()
	var fill := Polygon2D.new()
	fill.polygon = corners
	fill.color = Color(0.75, 0.4, 1.0, 0.35)
	box.add_child(fill)
	var edge := Line2D.new()
	edge.points = corners
	edge.closed = true
	edge.width = 1.0
	edge.default_color = Color(1.0, 0.85, 0.3)
	box.add_child(edge)
	node.add_child(box)
	box.scale = Vector2.ZERO
	create_tween().tween_property(box, "scale", Vector2.ONE, 0.25)
	return box


# --- Enemy turn ----------------------------------------------------------------

func _foe_turn(f: Dictionary) -> void:
	if f["burn"] > 0:
		f["burn"] -= 1
		message.text = "%s is hurt by the burn!" % f["name"]
		_damage(f, 2 + int(f["def"]))
		await _wait(0.7)
		if f["hp"] <= 0:
			return
	if f.get("cube", 0) > 0:
		await _cube_explode(f)  # trapped: the turn goes to the explosion
		return
	if f["stun"]:
		f["stun"] = false
		message.text = "%s is stunned and can't move!" % f["name"]
		await _wait(0.8)
		return
	var target: Dictionary = _alive(allies).pick_random()
	f["last_move"] = Game.move_of("enemy", f["type"])  # what Mimi copies
	if target.get("veil", 0) > 0:
		await _veil_counter(f, target)
		return
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
	foe_status.text = "\n".join(_alive(foes).map(func(f): return "%s HP %d/%d%s" % [f["name"], f["hp"], f["max_hp"], _status_tags(f)]))
