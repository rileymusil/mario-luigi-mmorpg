extends "res://scripts/battle.gd"
## Your partner's battle, from your side (the other half of coop_battle.gd).
## Their game runs the fight and streams what's happening (sync: HP, status,
## the message line, where everyone stands, damage numbers, ratings and
## effects); you pick your own moves and dodge your own hits here. Shares the
## look and timing helpers of battle.gd.

const SETUP_WAIT := 6.0
const FACES := [Vector2.DOWN, Vector2.RIGHT, Vector2.UP, Vector2.LEFT]

var me_index := -1
var mine: Array = []    # where your party members are in `allies` (same order as your party)
var over := false
var _queue: Array = []  # turn / dodge requests, handled one at a time
var _setup := {}
var _pow_bonus := 0     # a Red Pepper's POW, for the rest of this battle
## Items you can use on yourself in your partner's battle. The rest (1-Up,
## Refreshing Herb, Green Pepper) need their game to change things it keeps
## (partners, statuses, DEF), so they're greyed out here.
const GUEST_ITEMS := ["hp", "sp", "pow"]
var _pose: Array = []   # latest positions from the host, one per ally then foe
var _local := false     # playing your own move or dodge: your screen leads
var _local_foe := -1    # the foe charging at you while you dodge
var _local_ally := -1   # who is dodging it (you or one of your party members)


func _ready() -> void:
	# The host's positions arrive as they are (not pulled in, see battle.gd
	# _spot), so the guest's screen stays wide enough for a landscape host.
	portrait_width = 320
	_setup_presentation(Game.player.get("map", ""))  # backdrop, HP boxes (battle.gd)
	message.text = "Joining %s's battle..." % Net.party_name
	Net.party_message.connect(_on_party_message)
	# Their setup (and first sync) can come in while this scene was loading.
	var early: Array = Net.party_inbox.duplicate()
	Net.party_inbox.clear()
	Net.hold_party = false
	for d in early:
		_on_party_message(d)
	Net.party_changed.connect(func():
		if not Net.party_here and not over:
			_finish({"result": "fled"}))
	var waited := 0.0
	while _setup.is_empty() and not over and waited < SETUP_WAIT:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if over:
		return
	if _setup.is_empty():
		_finish({"result": "fled"})
		return
	_build(_setup)
	for d in _queue.duplicate():
		if d["kind"] in ["sync", "state"]:
			_queue.erase(d)
			_apply_sync(d)
	_loop()


func _on_party_message(d: Dictionary) -> void:
	if over:
		return
	match d.get("kind"):
		"setup":
			_setup = d
		"sync", "state":
			if allies.is_empty():
				_queue.append(d)  # before the setup is built: apply it then
			else:
				_apply_sync(d)
		"turn", "dodge":
			_queue.append(d)
		"end":
			_finish(d)


func _build(d: Dictionary) -> void:
	if d.has("bg"):
		_load_background(str(d["bg"]))
	me_index = int(d.get("me", -1))
	mine = d.get("mine", []).map(func(i): return int(i)) if typeof(d.get("mine")) == TYPE_ARRAY else []
	for a in d.get("allies", []):
		var node := _sprite(str(a[1]), Vector2(a[2], a[3]), Vector2.RIGHT)
		# "you": your own box shows your SP too.
		allies.append({"name": str(a[0]), "node": node, "ally": true, "home": node.position,
			"member": {"hp": 1, "max_hp": 1}, "pow": 0, "def": 0, "you": allies.size() == me_index})
	for f in d.get("foes", []):
		var node := _sprite(str(f[1]), Vector2(f[2], f[3]), Vector2.LEFT)
		foes.append({"name": str(f[0]), "type": str(f[1]), "node": node, "ally": false, "home": node.position,
			"hp": 1, "max_hp": 1, "burn": 0, "stun": false, "pow": 0, "def": 0})
	for f in foes:
		var info := Game.foe_info(f["type"])
		if not info.is_empty():
			f["max_hp"] = info["hp"]
			f["hp"] = f["max_hp"]
			f["def"] = info["def"]
	_refresh()


func _sprite(id: String, pos: Vector2, facing: Vector2) -> CharacterSprite:
	var node := CharacterSprite.new()
	node.character_id = id if (Game.CHARACTERS.has(id) or Game.PARTNERS.has(id) or not Game.foe_info(id).is_empty()) else "mario"
	node.facing = facing
	node.scale = Vector2(SCALE, SCALE)
	node.position = pos
	stage.add_child(node)
	if Game.BOSSES.has(id) or Game.BOSS_MINIONS.has(id):
		node.scale = Vector2.ONE * node.battle_scale(SCALE)  # as the host draws them
	return node


## The host's view of the battle: HP, status, message, poses and effects.
func _apply_sync(d: Dictionary) -> void:
	# Their timing prompts ("Press Z ..." / "Press A ...") are for them, and
	# during your own move your screen has its own hints.
	var msg := str(d.get("msg", "")).get_slice(" Press ", 0)
	if not _local:
		message.text = "" if msg.begins_with("Press ") else msg
	var a_hp: Array = d.get("allies", [])
	for i in mini(a_hp.size(), allies.size()):
		var m: Dictionary = allies[i]["member"]
		m["hp"] = int(a_hp[i][0])
		m["max_hp"] = int(a_hp[i][1])
	var f_hp: Array = d.get("foes", [])
	for i in mini(f_hp.size(), foes.size()):
		var f: Dictionary = foes[i]
		var row = f_hp[i]
		if row is Array:
			f["hp"] = int(row[0])
			f["max_hp"] = int(row[1])
			f["burn"] = int(row[2])
			f["stun"] = int(row[3]) == 1
			f["def_down"] = int(row[4])
			f["def"] = int(row[5])
		else:  # an older host: HP only
			f["hp"] = int(row)
			f["max_hp"] = maxi(f["max_hp"], f["hp"])
	if d.has("pose"):
		_pose = d["pose"]
	var turn := int(d.get("turn", -1))
	if not _local:
		_set_turn(allies[turn] if turn >= 0 and turn < allies.size() else {})
	for fx in d.get("fx", []):
		if fx is Array:
			_play_fx(fx)
	_refresh()


func _node_for(ref: String) -> CharacterSprite:
	if ref.length() < 2:
		return null
	var i := int(ref.substr(1))
	var list := allies if ref[0] == "a" else foes
	return list[i]["node"] if i >= 0 and i < list.size() else null


## One effect from the host's screen (see coop_battle.gd _fx).
func _play_fx(fx: Array) -> void:
	if fx.is_empty():
		return
	match str(fx[0]):
		"pop":
			_popup(Vector2(fx[1], fx[2]), str(fx[3]))
		"rate":
			_show_rating(str(fx[1]))
		"flash":
			var node := _node_for(str(fx[1]))
			if node:
				_flash(node)
		"shake":
			_shake(float(fx[1]))
		"burst":
			_burst(Vector2(fx[1], fx[2]), Color.html(str(fx[3])), float(fx[4]))
		"bolt":
			var node := _node_for(str(fx[1]))
			if node:
				_bolt(node)
		"proj":
			_projectile(Vector2(fx[1], fx[2]), Vector2(fx[3], fx[4]), Color.html(str(fx[5])))


## Everyone moves toward where the host last saw them. Your own character is
## always yours to move (your moves and dodges play here first).
func _process(delta: float) -> void:
	super(delta)
	var actors := allies + foes
	for i in mini(_pose.size(), actors.size()):
		var p: Array = _pose[i]
		var node: CharacterSprite = actors[i]["node"]
		node.visible = int(p[5]) == 1
		node.modulate = Color.html(str(p[4]))
		if p.size() > 7 and Game.BOSS_FORMS.has(str(p[7])) and node.character_id != str(p[7]):
			node.character_id = str(p[7])  # the boss changed shape (BOSSES "phase2_form")
			node.scale = Vector2.ONE * node.battle_scale(SCALE)
		if i == me_index or (_local and (i == allies.size() + _local_foe or i == _local_ally)):
			continue
		var target := Vector2(p[0], p[1])
		var to := target - node.position
		node.position = target if to.length() > 120.0 else node.position.lerp(target, minf(1.0, delta * 14.0))
		var face: Vector2 = FACES[clampi(int(p[3]), 0, 3)]
		node.move_velocity = face * 60.0 if int(p[6]) == 1 else Vector2.ZERO
		node.facing = face
		if int(p[2]) > 8 and not node.is_airborne():
			node.jump()


func _loop() -> void:
	while not over:
		if _queue.is_empty():
			await get_tree().process_frame
			continue
		var d: Dictionary = _queue.pop_front()
		_local = true
		var who := int(d.get("who", me_index))
		if d["kind"] == "turn" and who != me_index and who in mine:
			await _member_turn(who)
		elif d["kind"] == "turn":
			await _my_turn()
		elif d["kind"] == "dodge":
			await _dodge(d)
		_local = false
		_local_foe = -1
		_local_ally = -1


# --- Your turn -------------------------------------------------------------------

func _my_turn() -> void:
	var me: Dictionary = allies[me_index]
	var p: Dictionary = Game.player
	var sp_id: String = Game.CHARACTERS[p["character"]]["special"]
	var sp: Dictionary = Game.SPECIALS[sp_id]
	# Command blocks over you (as in battle.gd), then the target pointer;
	# X / B in the pointer goes back to the blocks.
	var commands := [
		{"label": "Jump", "icon": "jump", "info": "Stomp! Press {a} as you land for a 2nd hit."},
		{"label": "%s (%d SP)" % [sp["name"], sp["sp"]], "icon": "burst", "enabled": p["sp"] >= sp["sp"], "info": sp["info"]},
		{"label": "Items", "icon": "mushroom", "enabled": Game.owned_items().any(_guest_usable),
			"info": "Use an item. It takes this turn."},
	]
	_set_turn(me)
	var choice := -1
	var target_i := -1
	while true:
		choice = await blocks.choose(commands, me["node"])
		if over:
			return
		target_i = -1
		if choice == 2:
			if await _guest_item(me):
				return
			continue
		var alive := []
		for i in foes.size():
			if foes[i]["hp"] > 0:
				alive.append(i)
		alive.sort_custom(func(x, y): return foes[x]["node"].position.x < foes[y]["node"].position.x)
		if alive.size() <= 1:
			target_i = alive[0] if alive.size() == 1 else -1
			break
		message.text = "Pick a target."
		var pick := await targets.choose(alive.map(func(i): return {"node": foes[i]["node"], "label": foes[i]["name"]}))
		if over:
			return
		if pick >= 0:
			target_i = alive[pick]
			break
	_set_turn({})
	message.text = ""
	var hp: int = me["member"]["hp"]
	var max_hp: int = me["member"]["max_hp"]
	if target_i < 0:
		Net.send_party({"kind": "act", "move": "wait"})
		return
	var target: Dictionary = foes[target_i]
	var node: CharacterSprite = me["node"]
	if choice == 0:  # Jump
		var stand: Vector2 = target["node"].position + Vector2(-40, 0)
		var top: Vector2 = target["node"].position + Vector2(0, -target["node"].height() * SCALE * 0.8)
		_say("Press {a} just as you land!")
		await _walk(node, stand, 160.0)
		var badge := _show_badge(me, "jump")
		var result := _rate_landing(await _arc(node, node.position, top, 50.0, 0.55, true))
		badge.queue_free()
		var pow: int = p["pow"] + _pow_bonus
		var hits := [pow]
		if result != "Miss":
			hits.append(pow + (1 if result == "Excellent" else 0))
		# The host deals the damage when it plays this move back; send it now
		# and show the same numbers here straight away.
		Net.send_party({"kind": "act", "move": "jump", "target": target_i, "hits": hits, "rating": result})
		_hit(target, hits[0])
		_show_rating(result)
		if result != "Miss":
			await _arc(node, top, top, 38.0, 0.45, false)
			_hit(target, hits[1])
		await _arc(node, node.position, stand, 28.0, 0.35, false)
	else:
		p["sp"] -= sp["sp"]
		message.text = sp["name"] + "!"
		var result := await _timing_bar(1.0)
		if sp_id == "peach_heart":
			var heal: int = {"Excellent": 14, "Good": 10, "Miss": 6}[result]
			Net.send_party({"kind": "act", "move": "heal", "hp": mini(max_hp, hp + heal)})
			_show_rating("%s  +%d HP" % [result, heal])
			return
		var bonus: int = {"Excellent": 3, "Good": 1, "Miss": 0}[result]
		var hit: int = p["pow"] + _pow_bonus + 2 + bonus
		Net.send_party({"kind": "act", "move": "special", "target": target_i, "hits": [hit],
			"rating": result, "name": sp["name"]})
		await _walk(node, target["node"].position + Vector2(-22, 0), 220.0)
		_hit(target, hit)
	await _walk(node, me["home"], 160.0)
	node.facing = Vector2.RIGHT


## One of your party members' turns: their move, a target, and the timing
## here; their game plays it back and deals the damage.
func _member_turn(who: int) -> void:
	var k := mine.find(who)
	var party: Array = Game.player["party"]
	var member: Dictionary = party[k] if k >= 0 and k < party.size() else {}
	var move: Dictionary = Game.MOVES.get(Game.move_of(member.get("kind", "partner"), str(member.get("id", ""))), {})
	var a: Dictionary = allies[who]
	if move.is_empty():
		Net.send_party({"kind": "act", "move": "wait"})
		return
	var commands := [{"label": move["name"], "icon": "hammer", "info": move.get("info", "")}]
	_set_turn(a)
	var target_i := -1
	while true:
		await blocks.choose(commands, a["node"], true)
		if over:
			return
		var alive := []
		for i in foes.size():
			if foes[i]["hp"] > 0:
				alive.append(i)
		alive.sort_custom(func(x, y): return foes[x]["node"].position.x < foes[y]["node"].position.x)
		if alive.size() <= 1:
			target_i = alive[0] if alive.size() == 1 else -1
			break
		message.text = "Pick a target."
		var pick := await targets.choose(alive.map(func(i): return {"node": foes[i]["node"], "label": foes[i]["name"]}))
		if over:
			return
		if pick >= 0:
			target_i = alive[pick]
			break
	_set_turn({})
	message.text = move["name"] + "!"
	if target_i < 0:
		Net.send_party({"kind": "act", "move": "wait"})
		return
	var result: String = await member_hits(move, int(member.get("pow", 1)), int(foes[target_i]["def"]),
		func(): return await _timing_bar(1.0, "hammer_green"))
	Net.send_party({"kind": "act", "move": "partner", "target": target_i, "hits": _last_hits, "rating": result})
	_show_rating(result)


var _last_hits: Array = []


## Rates a party member's move with timing bars and works out its hits
## (into _last_hits) the way battle.gd's _partner_move does; returns the
## rating. `bar` plays one timing bar.
func member_hits(move: Dictionary, pow: int, target_def: int, bar: Callable) -> String:
	var power: int = pow + int(move.get("bonus", 0))
	var extra: int = target_def if move.get("ignore_def", false) else 0
	_last_hits = []
	var result: String = await bar.call()
	match move["kind"]:
		"blast":
			_last_hits = [maxi(0, power + {"Excellent": 2, "Good": 0, "Miss": -1}[result])]
		"multi":
			_last_hits = [maxi(0, power - 1 + {"Excellent": 2, "Good": 1, "Miss": 0}[result])]
			while result != "Miss" and _last_hits.size() < int(move.get("hits", 2)):
				result = await bar.call()
				_last_hits.append(maxi(0, power - 1 + {"Excellent": 2, "Good": 1, "Miss": 0}[result]))
		"stomp":
			_last_hits = [power]
			if result != "Miss":
				_last_hits.append(power + (1 if result == "Excellent" else 0))
		_:  # tackle, throw
			_last_hits = [power + extra + {"Excellent": 2, "Good": 1, "Miss": 0}[result]]
	return result


## Can you use item `id` on yourself right now, in your partner's battle?
func _guest_usable(id: String) -> bool:
	var item: Dictionary = Game.ITEMS[id]
	var me: Dictionary = allies[me_index]["member"]
	var p: Dictionary = Game.player
	if item.has("hp"):
		return me["hp"] < me["max_hp"]
	if item.has("sp"):
		return p["sp"] < p["max_sp"]
	return item.has("pow")


## The item list. Uses the pick on yourself and tells their game; false if
## you backed out.
func _guest_item(me: Dictionary) -> bool:
	var ids := Game.owned_items()
	var labels := []
	var enabled := []
	var infos := []
	var icons := []
	for id in ids:
		var item: Dictionary = Game.ITEMS[id]
		labels.append("%s x%d" % [item["name"], Game.item_count(id)])
		enabled.append(_guest_usable(id))
		var usable_here: bool = GUEST_ITEMS.any(func(k): return item.has(k))
		infos.append(item["info"] if usable_here else "Can't be used in a partner's battle.")
		icons.append(load("res://assets/items/%s.png" % id))
	menu.max_rows = 5
	_say("Which item? {b} to go back.")
	var i := await menu.choose(labels, "Items", true, enabled, infos, icons)
	message.text = ""
	if i < 0 or over:
		return false
	_set_turn({})
	var id: String = ids[i]
	var item: Dictionary = Game.ITEMS[id]
	var p: Dictionary = Game.player
	Game.add_item(id, -1)
	await _item_pop(me, id)
	if item.has("hp"):
		var m: Dictionary = me["member"]
		var hp := mini(m["max_hp"], m["hp"] + int(item["hp"]))
		_show_rating("+%d HP" % (hp - m["hp"]))
		Net.send_party({"kind": "act", "move": "heal", "hp": hp})
		return true
	if item.has("sp"):
		var before: int = p["sp"]
		p["sp"] = mini(p["max_sp"], p["sp"] + int(item["sp"]))
		_show_rating("+%d SP" % (p["sp"] - before))
	else:
		_pow_bonus += int(item["pow"])
		_show_rating("POW +%d" % int(item["pow"]))
	_refresh()
	Net.send_party({"kind": "act", "move": "wait"})
	return true


## The number and flash your hit will make (the host works out the same
## damage with the same rule and sends the new HP).
func _hit(target: Dictionary, amount: int) -> void:
	var dmg := maxi(1, clampi(amount, 0, 99) - int(target["def"]))
	_flash(target["node"])
	_shake(2.5, 0.12)
	_popup(target["node"].position + Vector2(0, -50), str(dmg))


# --- An enemy charges at you -----------------------------------------------------

func _dodge(d: Dictionary) -> void:
	var i := int(d.get("foe", 0))
	if i < 0 or i >= foes.size() or me_index < 0:
		Net.send_party({"kind": "dodged", "ok": false})
		return
	_local_foe = i
	# "who": you, or one of your party members (you jump for them, as in
	# your own battles).
	var who := int(d.get("who", me_index))
	if not (who == me_index or who in mine):
		who = me_index
	_local_ally = who
	var fnode: CharacterSprite = foes[i]["node"]
	var node: CharacterSprite = allies[who]["node"]
	var start: Vector2 = foes[i]["home"]
	var contact := Vector2(node.position.x + 8, node.position.y)
	var duration := clampf(float(d.get("time", 0.7)), 0.3, 1.2)
	if who == me_index:
		_say("%s charges at you! Press {a} to jump!", [foes[i]["name"]])
	else:
		_say("%s charges at %s! Press {a} to jump!", [foes[i]["name"], allies[who]["name"]])
	var badge := _show_badge(allies[who], "jump")
	var t := 0.0
	while t < duration:
		await get_tree().process_frame
		t = minf(t + get_process_delta_time(), duration)
		fnode.position = start.lerp(contact, t / duration)
		fnode.move_velocity = Vector2.LEFT * 100
		if Input.is_action_just_pressed("action"):
			node.jump()
	badge.queue_free()
	var ok: bool = node.jump_height > 8.0
	Net.send_party({"kind": "dodged", "ok": ok})
	if ok:
		_show_rating("Dodged!")
	# The host plays the rest (the hit, the number, the way back).
	await _slide(fnode, contact + (Vector2(-60, 0) if ok else Vector2(20, 0)), 0.2)
	fnode.move_velocity = Vector2.ZERO


# --- The end ---------------------------------------------------------------------

func _finish(d: Dictionary) -> void:
	if over:
		return
	over = true
	_local = true
	menu.visible = false
	blocks.visible = false
	targets.visible = false
	var p: Dictionary = Game.player
	match str(d.get("result", "fled")):
		"won":
			var xp := clampi(int(d.get("xp", 0)), 0, 1999)
			var coins := clampi(int(d.get("coins", 0)), 0, 999)
			p["coins"] += coins
			p["wins"] += 1
			p["hp"] = clampi(int(d.get("hp", p["hp"])), 1, p["max_hp"])
			var levels := Game.gain_xp(xp)
			Quests.on_defeat(foes.map(func(f): return f["type"]), str(p.get("map", "")))
			var party_hp = d.get("party_hp", [])
			if typeof(party_hp) == TYPE_ARRAY:  # your party members' HP after the fight
				for k in mini(party_hp.size(), p["party"].size()):
					p["party"][k]["hp"] = clampi(int(party_hp[k]), 1, int(p["party"][k]["max_hp"]))
			if me_index >= 0:  # your box shows your HP and SP after the win
				allies[me_index]["member"]["hp"] = p["hp"]
				allies[me_index]["member"]["max_hp"] = p["max_hp"]
			_refresh()
			message.text = "You won! +%d XP  +%d coins" % [xp, coins]
			var bonus := clampi(int(d.get("bonus", 0)), 0, xp)
			if bonus > 0:
				message.text = "You won! +%d XP (party +%d)  +%d coins" % [xp, bonus, coins]
			await _wait(1.6)
			await _show_drops(Game.roll_drops(foes.map(func(f): return f["type"])))
			if levels > 0:
				message.text = "Level up! %s is now level %d!" % [Game.character_name(), p["level"]]
				_show_rating("LEVEL UP!")
				await _wait(1.8)
			_leave("won")
		"lost":
			message.text = "Your party was defeated... Back to town, a few coins lighter."
			await _wait(2.0)
			_leave("lost")
		_:
			message.text = "The battle is over."
			await _wait(1.0)
			_leave("fled")
