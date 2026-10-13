extends "res://scripts/battle.gd"
## Your partner's battle, from your side (the other half of coop_battle.gd).
## Their game runs the fight and sends what's happening; you pick your own
## moves and dodge your own hits here. Shares the look and timing helpers of
## battle.gd.

const SETUP_WAIT := 6.0

var me_index := -1
var over := false
var _queue: Array = []  # turn / dodge requests, handled one at a time
var _setup := {}


func _ready() -> void:
	_setup_presentation(Game.player.get("map", ""))  # backdrop, HP boxes (battle.gd)
	message.text = "Joining %s's battle..." % Net.party_name
	Net.party_message.connect(_on_party_message)
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
	_loop()


func _on_party_message(d: Dictionary) -> void:
	if over:
		return
	match d.get("kind"):
		"setup":
			_setup = d
		"state":
			_apply_state(d)
		"turn", "dodge":
			_queue.append(d)
		"end":
			_finish(d)


func _build(d: Dictionary) -> void:
	me_index = int(d.get("me", -1))
	for a in d.get("allies", []):
		var node := _sprite(str(a[1]), Vector2(a[2], a[3]), Vector2.RIGHT)
		# "you": your own box shows your SP too.
		allies.append({"name": str(a[0]), "node": node, "ally": true, "home": node.position,
			"member": {"hp": 1, "max_hp": 1}, "pow": 0, "def": 0, "you": allies.size() == me_index})
	for f in d.get("foes", []):
		var node := _sprite(str(f[1]), Vector2(f[2], f[3]), Vector2.LEFT)
		foes.append({"name": str(f[0]), "type": str(f[1]), "node": node, "ally": false, "home": node.position,
			"hp": 1, "max_hp": 1, "burn": 0, "stun": false, "pow": 0, "def": 0})
	if Game.ENEMIES.size() > 0:
		for f in foes:
			if Game.ENEMIES.has(f["type"]):
				f["max_hp"] = Game.ENEMIES[f["type"]]["hp"]
	_refresh()


func _sprite(id: String, pos: Vector2, facing: Vector2) -> CharacterSprite:
	var node := CharacterSprite.new()
	node.character_id = id if (Game.CHARACTERS.has(id) or Game.ENEMIES.has(id) or Game.PARTNERS.has(id)) else "mario"
	node.facing = facing
	node.scale = Vector2(SCALE, SCALE)
	node.position = pos
	stage.add_child(node)
	return node


func _apply_state(d: Dictionary) -> void:
	# Their timing prompts ("Press Z ..." / "Press A ...") are for them.
	var msg := str(d.get("msg", "")).get_slice(" Press ", 0)
	if not msg.begins_with("Press "):
		message.text = msg
	var a_hp: Array = d.get("allies", [])
	for i in mini(a_hp.size(), allies.size()):
		var m: Dictionary = allies[i]["member"]
		var before: int = m["hp"]
		m["hp"] = int(a_hp[i][0])
		m["max_hp"] = int(a_hp[i][1])
		if m["hp"] < before:
			_flash(allies[i]["node"])
			_popup(allies[i]["node"].position + Vector2(0, -50), str(before - m["hp"]))
		allies[i]["node"].modulate.a = 1.0 if m["hp"] > 0 else 0.4
	var f_hp: Array = d.get("foes", [])
	for i in mini(f_hp.size(), foes.size()):
		var f: Dictionary = foes[i]
		var before: int = f["hp"]
		f["hp"] = int(f_hp[i])
		f["max_hp"] = maxi(f["max_hp"], f["hp"])
		if f["hp"] < before:
			_flash(f["node"])
			_popup(f["node"].position + Vector2(0, -50), str(before - f["hp"]))
		if f["hp"] <= 0 and f["node"].modulate.a > 0.0:
			create_tween().tween_property(f["node"], "modulate:a", 0.0, 0.4)
	_refresh()


func _loop() -> void:
	while not over:
		if _queue.is_empty():
			await get_tree().process_frame
			continue
		var d: Dictionary = _queue.pop_front()
		if d["kind"] == "turn":
			await _my_turn()
		else:
			await _dodge(d)


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
		{"label": "Mushroom (%d)" % p["mushrooms"], "icon": "mushroom", "enabled": p["mushrooms"] > 0, "info": "Heal 10 HP."},
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
			break
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
	if choice == 2:  # Mushroom
		p["mushrooms"] -= 1
		_show_rating("+10 HP")
		Net.send_party({"kind": "act", "move": "heal", "hp": mini(max_hp, hp + 10)})
		return
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
		_show_rating(result)
		var hits := [p["pow"]]
		if result != "Miss":
			hits.append(p["pow"] + (1 if result == "Excellent" else 0))
		Net.send_party({"kind": "act", "move": "jump", "target": target_i, "hits": hits, "rating": result})
		if result != "Miss":
			await _arc(node, top, top, 38.0, 0.45, false)
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
		Net.send_party({"kind": "act", "move": "special", "target": target_i, "hits": [p["pow"] + 2 + bonus],
			"rating": result, "name": sp["name"]})
		await _walk(node, target["node"].position + Vector2(-22, 0), 220.0)
	await _walk(node, me["home"], 160.0)
	node.facing = Vector2.RIGHT


# --- An enemy charges at you -----------------------------------------------------

func _dodge(d: Dictionary) -> void:
	var i := int(d.get("foe", 0))
	if i < 0 or i >= foes.size() or me_index < 0:
		Net.send_party({"kind": "dodged", "ok": false})
		return
	var fnode: CharacterSprite = foes[i]["node"]
	var node: CharacterSprite = allies[me_index]["node"]
	var start := fnode.position
	var contact := Vector2(node.position.x + 8, node.position.y)
	var duration := clampf(float(d.get("time", 0.7)), 0.3, 1.2)
	_say("%s charges at you! Press {a} to jump!", [foes[i]["name"]])
	var badge := _show_badge(allies[me_index], "jump")
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
	await _slide(fnode, contact + (Vector2(-60, 0) if ok else Vector2(20, 0)), 0.2)
	fnode.move_velocity = Vector2.RIGHT * 100
	await _slide(fnode, foes[i]["home"], 0.4)
	fnode.move_velocity = Vector2.ZERO
	fnode.facing = Vector2.LEFT


# --- The end ---------------------------------------------------------------------

func _finish(d: Dictionary) -> void:
	if over:
		return
	over = true
	menu.visible = false
	blocks.visible = false
	targets.visible = false
	var p: Dictionary = Game.player
	match str(d.get("result", "fled")):
		"won":
			var xp := clampi(int(d.get("xp", 0)), 0, 999)
			var coins := clampi(int(d.get("coins", 0)), 0, 999)
			p["coins"] += coins
			p["wins"] += 1
			p["hp"] = clampi(int(d.get("hp", p["hp"])), 1, p["max_hp"])
			var levels := Game.gain_xp(xp)
			message.text = "You won! +%d XP  +%d coins" % [xp, coins]
			await _wait(1.6)
			if levels > 0:
				message.text = "Level up! %s is now level %d!" % [Game.character_name(), p["level"]]
				_show_rating("LEVEL UP!")
				await _wait(1.8)
			Game.end_battle("won")
		"lost":
			message.text = "Your party was defeated... Back to town, a few coins lighter."
			await _wait(2.0)
			Game.end_battle("lost")
		_:
			message.text = "The battle is over."
			await _wait(1.0)
			Game.end_battle("fled")

