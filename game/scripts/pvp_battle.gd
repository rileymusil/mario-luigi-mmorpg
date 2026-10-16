extends "res://scripts/battle.gd"
## Online duel between an evil player and a good player (1 on 1, no partners).
## Both games run this scene and take turns through the server, with the same
## look as other battles (the map's background, command blocks, A-button
## badges, word-art ratings):
##   your turn: pick a block and do its timed press here, then send the move
##     (duel_act) with how hard it hits.
##   their turn: their move plays out on your screen the same way it did on
##     theirs. A Jump stomps on you: press {a} as they land to guard (half
##     damage). A special charges at you: press {a} to jump over it. Then you
##     send back what it did (duel_hit) and they see the same numbers.
## Each game keeps its own HP and sends it with every move, so both screens
## show the same HP. The loser drops 10% of their coins, which the winner
## picks up along with XP. Leaving or losing the connection mid-duel counts
## as losing. Shares the look and timing helpers of battle.gd.

const TURN_TIMEOUT := 45.0  # waiting this long for the foe's move wins the duel
const HIT_TIMEOUT := 20.0

var foe := {}        # battle actor like battle.gd's foes, plus "stats"
var me := {}
var over := false


func _ready() -> void:
	var pvp: Dictionary = Game.pending_battle.get("pvp", {})
	_add_ally({"name": Game.username(), "id": Game.player["character"], "member": Game.player})
	me = allies[0]
	var stats: Dictionary = pvp.get("stats", {})
	var character: String = pvp.get("character", "mario")
	var node := CharacterSprite.new()
	node.character_id = character if Game.CHARACTERS.has(character) else "mario"
	node.facing = Vector2.LEFT
	node.scale = Vector2(SCALE, SCALE)
	node.position = _spot(ENEMY_SPOTS[0])
	stage.add_child(node)
	foe = {"name": str(pvp.get("name", "???")), "type": node.character_id, "node": node, "ally": false,
		"hp": int(stats.get("hp", 1)), "max_hp": maxi(1, int(stats.get("max_hp", 1))), "pow": int(stats.get("pow", 1)),
		"def": int(stats.get("def", 0)), "burn": 0, "stun": false, "home": node.position, "stats": stats}
	foes.append(foe)
	_setup_presentation(Game.player.get("map", ""))  # backdrop, party bar (battle.gd)
	_refresh()
	_run_duel(Game.pending_battle.get("first", false))


func _run_duel(mine: bool) -> void:
	message.text = ("You attack %s!" if mine else "%s attacks you!") % foe["name"]
	await _wait(1.2)
	while not over:
		if mine:
			await _my_turn()
		else:
			await _their_turn()
		mine = not mine


## Ends the duel when the foe's game says so, or the connection drops.
func _process(delta: float) -> void:
	super(delta)
	if over:
		return
	for i in Net.duel_inbox.size():
		if Net.duel_inbox[i].get("t") == "duel_over":
			_on_duel_over(str(Net.duel_inbox.pop_at(i).get("result", "cancel")))
			return
	if not Net.is_online():
		_connection_lost()


# --- Your turn -------------------------------------------------------------------

func _my_turn() -> void:
	var p: Dictionary = Game.player
	var sp_id: String = Game.CHARACTERS[p["character"]]["special"]
	var sp: Dictionary = Game.SPECIALS[sp_id]
	var commands := [
		{"id": "jump", "label": "Jump", "icon": "jump", "info": "Stomp! Press {a} as you land for a 2nd hit."},
		{"id": "special", "label": "%s (%d SP)" % [sp["name"], sp["sp"]], "icon": "burst",
			"enabled": p["sp"] >= sp["sp"], "info": sp["info"]},
		{"id": "mushroom", "label": "Mushroom (%d)" % Game.item_count("mushroom"), "icon": "mushroom",
			"enabled": Game.item_count("mushroom") > 0, "info": "Heal 10 HP."},
		{"id": "run", "label": "Run", "icon": "run", "info": "Try to escape."},
	]
	_set_turn(me)
	message.text = "Your turn!"
	var choice: String = commands[await blocks.choose(commands, me["node"])]["id"]
	_set_turn({})
	if over:
		return
	message.text = ""
	if choice == "run":
		if randf() < 0.5:
			over = true
			Net.end_duel("fled")
			message.text = "Got away safely!"
			await _wait(1.0)
			_leave("fled")
			return
		message.text = "Couldn't get away!"
		Net.duel_send({"t": "duel_act", "move": "wait", "hp": _hp(me)})
		await _wait(0.8)
		return
	if choice == "mushroom":
		Game.add_item("mushroom", -1)
		_heal(me, 10)
		Net.duel_send({"t": "duel_act", "move": "heal", "hp": _hp(me), "name": "Mushroom"})
		await _wait(0.8)
		return
	if choice == "jump":
		await _jump_at_foe()
	else:
		await _special_at_foe(sp_id, sp)
	if over:
		return
	message.text = "..."
	var hit := await _await_message("duel_hit", HIT_TIMEOUT)
	if over:
		return
	if hit.is_empty():
		Net.end_duel("timeout")
		await _foe_gone("timeout")
		return
	_show_hit(hit)
	await _walk(me["node"], me["home"], 160.0)
	me["node"].facing = Vector2.RIGHT
	await _wait(0.4)


## battle.gd's jump, without dealing damage (the foe's game works that out
## and sends it back). The move goes out as soon as the first landing is
## rated, so the foe's screen plays it while yours finishes.
func _jump_at_foe() -> void:
	var p: Dictionary = Game.player
	var node: CharacterSprite = me["node"]
	var target: CharacterSprite = foe["node"]
	var stand: Vector2 = target.position + Vector2(-40, 0)
	var top: Vector2 = target.position + Vector2(0, -target.height() * SCALE * 0.8)
	_say("Press {a} just as you land!")
	await _walk(node, stand, 160.0)
	var badge := _show_badge(me, "jump")
	var result := _rate_landing(await _arc(node, node.position, top, 50.0, 0.55, true))
	badge.queue_free()
	var hits := [p["pow"]]
	if result != "Miss":
		hits.append(p["pow"] + (1 if result == "Excellent" else 0))
	Net.duel_send({"t": "duel_act", "move": "jump", "hits": hits, "rating": result, "hp": _hp(me), "name": "Jump"})
	_show_rating(result)
	if result != "Miss":
		await _arc(node, top, top, 38.0, 0.45, false)
	await _arc(node, node.position, stand, 28.0, 0.35, false)


func _special_at_foe(sp_id: String, sp: Dictionary) -> void:
	var p: Dictionary = Game.player
	p["sp"] -= sp["sp"]
	_refresh()
	message.text = sp["name"] + "!"
	var result := await _timing_bar(1.0)
	var bonus: int = {"Excellent": 3, "Good": 1, "Miss": 0}[result]
	if sp_id == "peach_heart":
		_heal(me, {"Excellent": 14, "Good": 10, "Miss": 6}[result])
		Net.duel_send({"t": "duel_act", "move": "heal", "hp": _hp(me), "name": sp["name"]})
		await _wait(0.8)
		return
	if sp_id in ["star_spin", "shadow_drain", "poltergust_pull"]:
		_heal(me, {"Excellent": 5, "Good": 3, "Miss": 1}[result])
	Net.duel_send({"t": "duel_act", "move": "special", "hits": [p["pow"] + 2 + bonus], "rating": result,
		"hp": _hp(me), "name": sp["name"]})
	await _walk(me["node"], foe["node"].position + Vector2(-22, 0), 220.0)
	_burst(_middle(foe), Color(1.0, 0.7, 0.2), 18.0)


## What your move did, as the foe's game worked it out.
func _show_hit(hit: Dictionary) -> void:
	var dmg := int(hit.get("dmg", 0))
	foe["hp"] = clampi(int(hit.get("hp", foe["hp"])), 0, foe["max_hp"])
	if hit.get("dodged", false):
		foe["node"].jump()
		_show_rating("Dodged!")
		message.text = "%s jumped out of the way!" % foe["name"]
	else:
		if hit.get("guard", false):
			_show_rating("Guard!")
			message.text = "%s guarded!" % foe["name"]
		else:
			message.text = ""
		_flash(foe["node"])
		_shake(2.5, 0.12)
		_popup(foe["node"].position + Vector2(0, -50), str(dmg))
	_refresh()


# --- Their turn ------------------------------------------------------------------

func _their_turn() -> void:
	message.text = "%s's turn..." % foe["name"]
	var act := await _await_message("duel_act", TURN_TIMEOUT)
	if over:
		return
	if act.is_empty():
		Net.end_duel("timeout")
		await _foe_gone("timeout")
		return
	var their_hp := clampi(int(act.get("hp", foe["hp"])), 0, foe["max_hp"])
	match str(act.get("move", "wait")):
		"wait":
			foe["hp"] = their_hp
			message.text = "%s tried to run, but couldn't!" % foe["name"]
			_refresh()
			await _wait(1.0)
		"heal":
			var healed := their_hp - int(foe["hp"])
			foe["hp"] = their_hp
			message.text = "%s used %s!" % [foe["name"], act.get("name", "a Mushroom")]
			_show_rating("+%d HP" % maxi(0, healed))
			_refresh()
			await _wait(1.0)
		"jump":
			foe["hp"] = their_hp
			_refresh()
			await _take_stomp(act)
		_:
			foe["hp"] = their_hp
			_refresh()
			await _take_charge(act)


## Their Jump, as they did it: they walk up and stomp on you once, twice on a
## good press. Press {a} as they land to guard: that hit does half damage.
func _take_stomp(act: Dictionary) -> void:
	var node: CharacterSprite = me["node"]
	var fnode: CharacterSprite = foe["node"]
	var hits: Array = act.get("hits", [])
	var stand: Vector2 = node.position + Vector2(40, 0)
	var top: Vector2 = node.position + Vector2(0, -node.height() * SCALE * 0.8)
	message.text = "%s jumps at you!" % foe["name"]
	await _walk(fnode, stand, 160.0)
	fnode.facing = Vector2.LEFT
	var dmg := 0
	var guarded := false
	for i in hits.size():
		_say("Press {a} as %s lands to guard!", [foe["name"]])
		var badge := _show_badge(me, "jump")
		var from := fnode.position
		var guard := _rate_landing(await _arc(fnode, from, top, 50.0 if i == 0 else 38.0, 0.55 if i == 0 else 0.45, true))
		badge.queue_free()
		var d := maxi(1, int(hits[i]) - int(me["def"]))
		if guard != "Miss":
			d = floori(d / 2.0)
			guarded = true
			_show_rating("Guard!")
		elif i == 0:
			_show_rating(str(act.get("rating", "")))
		dmg += d
		_set_hp(me, _hp(me) - d)
		_flash(node)
		_shake(2.5, 0.12)
		_popup(node.position + Vector2(0, -50), str(d))
		_refresh()
		if _hp(me) <= 0:
			break
	message.text = ""
	Net.duel_send({"t": "duel_hit", "dmg": dmg, "hp": _hp(me), "dodged": false, "guard": guarded})
	await _arc(fnode, fnode.position, stand, 28.0, 0.35, false)
	await _walk(fnode, foe["home"], 160.0)
	fnode.facing = Vector2.LEFT
	await _after_hit()


## Their special charges at you; jump ({a}) so you're in the air when it hits.
func _take_charge(act: Dictionary) -> void:
	var node: CharacterSprite = me["node"]
	var fnode: CharacterSprite = foe["node"]
	_say("%s uses %s! Press {a} to jump!", [foe["name"], act.get("name", "an attack")])
	var badge := _show_badge(me, "jump")
	for i in 6:
		fnode.position.x = foe["home"].x + (2.0 if i % 2 == 0 else -2.0)
		await _wait(0.07)
	fnode.position = foe["home"]
	var start := fnode.position
	var contact := Vector2(node.position.x + 8, node.position.y)
	# A perfectly timed attack comes in faster, so it's harder to dodge.
	var duration := randf_range(0.55, 0.85) * (0.8 if act.get("rating") == "Excellent" else 1.0)
	var t := 0.0
	while t < duration:
		await get_tree().process_frame
		t = minf(t + get_process_delta_time(), duration)
		fnode.position = start.lerp(contact, t / duration)
		fnode.move_velocity = Vector2.LEFT * 100
		if Input.is_action_just_pressed("action"):
			node.jump()
	badge.queue_free()
	var dodged: bool = node.jump_height > 8.0
	var dmg := 0
	if dodged:
		_show_rating("Dodged!")
		message.text = ""
		await _slide(fnode, contact + Vector2(-60, 0), 0.25)
	else:
		for h in act.get("hits", []):
			dmg += maxi(1, int(h) - int(me["def"]))
		_set_hp(me, _hp(me) - dmg)
		_show_rating(str(act.get("rating", "")))
		_burst(_middle(me), Color(1.0, 0.7, 0.2), 18.0)
		_flash(node)
		_shake(2.5, 0.12)
		_popup(node.position + Vector2(0, -50), str(dmg))
		message.text = ""
		_refresh()
		await _slide(fnode, contact + Vector2(20, 0), 0.15)
	Net.duel_send({"t": "duel_hit", "dmg": dmg, "hp": _hp(me), "dodged": dodged})
	fnode.move_velocity = Vector2.RIGHT * 100
	await _slide(fnode, foe["home"], 0.4)
	fnode.move_velocity = Vector2.ZERO
	fnode.facing = Vector2.LEFT
	await _after_hit()


func _after_hit() -> void:
	if _hp(me) <= 0 and not over:
		Net.end_duel("lost")
		await _duel_lost()
		return
	await _wait(0.3)


# --- Endings ---------------------------------------------------------------------

func _on_duel_over(result: String) -> void:
	if over:
		return
	match result:
		"lost":
			_duel_won(true)
		"fled":
			over = true
			blocks.visible = false
			message.text = "%s ran away!" % foe["name"]
			await _wait(1.2)
			_leave("fled")
		"timeout":
			# We took too long; the foe's game called it.
			_duel_lost()
		_:
			_foe_gone(result)


## The foe stopped answering ("timeout") or left the map / lost the
## connection ("left"): either way they forfeit and drop their coins (their
## game takes them off, see Game.load_save and _connection_lost). "cancel"
## and anything else ends the duel with no winner.
func _foe_gone(why: String) -> void:
	if over:
		return
	if why not in ["timeout", "left"]:
		over = true
		blocks.visible = false
		message.text = "The duel was called off."
		await _wait(1.2)
		_leave("fled")
		return
	message.text = ("%s ran out of time!" if why == "timeout" else "%s left the battle!") % foe["name"]
	await _duel_won(true)


## Your connection dropped: the server tells the foe you left, so this
## counts as a loss here too.
func _connection_lost() -> void:
	if over:
		return
	over = true
	blocks.visible = false
	var drop: int = Game.pvp_drop(Game.player["coins"])
	message.text = "Lost the connection... The duel counts as a loss (-%d coins)." % drop
	await _wait(2.2)
	_leave("lost")


func _duel_won(coins_dropped: bool) -> void:
	if over:
		return
	over = true
	blocks.visible = false
	# Their last hit result can come in the same moment as "lost": show it.
	for m in Net.duel_inbox.filter(func(m): return m.get("t") == "duel_hit"):
		_show_hit(m)
	Net.duel_inbox.clear()
	foe["hp"] = 0
	_refresh()
	var p: Dictionary = Game.player
	var coins: int = Game.pvp_drop(int(foe["stats"].get("coins", 0))) if coins_dropped else 0
	var xp: int = 4 + 2 * int(foe["stats"].get("level", 1))
	p["coins"] += coins
	p["wins"] += 1
	p["pvp_wins"] = int(p.get("pvp_wins", 0)) + 1
	p["hp"] = maxi(1, p["hp"])
	var levels := Game.gain_xp(xp)
	var fade := create_tween()
	fade.tween_interval(0.3)
	fade.tween_property(foe["node"], "modulate:a", 0.0, 0.4)
	await _wait(0.8)
	message.text = "You beat %s! +%d XP  +%d coins" % [foe["name"], xp, coins]
	_refresh()
	await _wait(1.8)
	if levels > 0:
		message.text = "Level up! %s is now level %d!" % [Game.character_name(), p["level"]]
		_show_rating("LEVEL UP!")
		_refresh()
		await _wait(1.8)
	_leave("won")


func _duel_lost() -> void:
	if over:
		return
	over = true
	blocks.visible = false
	var drop: int = Game.pvp_drop(Game.player["coins"])
	me["node"].modulate.a = 0.4
	message.text = "%s beat you... You dropped %d coins." % [foe["name"], drop]
	await _wait(2.2)
	_leave("lost")  # home town, 10% of coins lost (the drop above)


# --- Helpers ---------------------------------------------------------------------

func _heal(a: Dictionary, amount: int) -> void:
	_set_hp(a, _hp(a) + amount)
	_show_rating("+%d HP" % amount)
	_refresh()


## Waits for the foe's next message of type `t` (buffered in Net.duel_inbox,
## so nothing sent while this scene loaded is lost). Returns {} on timeout or
## once the duel is over.
func _await_message(t: String, timeout: float) -> Dictionary:
	var waited := 0.0
	while waited < timeout and not over:
		for i in Net.duel_inbox.size():
			if Net.duel_inbox[i].get("t") == t:
				return Net.duel_inbox.pop_at(i)
		await get_tree().process_frame
		waited += get_process_delta_time()
	return {}
