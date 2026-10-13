extends "res://scripts/battle.gd"
## Online duel between an evil player and a good player (1 on 1, no partners).
## Both games run this scene and take turns through the server:
##   your turn: pick a move and do its timed press here, then send the move
##     (duel_act) with how hard it hits.
##   their turn: their move comes in, you press Z to jump over their charge,
##     then send back what it did to you (duel_hit). Each game keeps its own HP.
## The loser drops some coins, which the winner picks up along with XP.
## Shares the look and timing helpers of battle.gd.

const TURN_TIMEOUT := 45.0  # waiting this long for the foe's move wins the duel
const HIT_TIMEOUT := 20.0

var foe := {}        # battle actor like battle.gd's foes, plus "stats"
var me := {}
var over := false
var _inbox: Array = []


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
	node.position = ENEMY_SPOTS[0]
	stage.add_child(node)
	foe = {"name": str(pvp.get("name", "???")), "type": node.character_id, "node": node, "ally": false,
		"hp": int(stats.get("hp", 1)), "max_hp": int(stats.get("max_hp", 1)), "pow": int(stats.get("pow", 1)),
		"def": int(stats.get("def", 0)), "burn": 0, "stun": false, "home": node.position, "stats": stats}
	foes.append(foe)
	Net.duel_message.connect(func(msg): _inbox.append(msg))
	Net.duel_over.connect(_on_duel_over)
	bar.visible = false
	rating.text = ""
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


# --- Your turn -------------------------------------------------------------------

func _my_turn() -> void:
	var p: Dictionary = Game.player
	var sp_id: String = Game.CHARACTERS[p["character"]]["special"]
	var sp: Dictionary = Game.SPECIALS[sp_id]
	var options := ["Jump", "%s (%d SP)" % [sp["name"], sp["sp"]], "Mushroom (%d)" % p["mushrooms"], "Run"]
	var enabled := [true, p["sp"] >= sp["sp"], p["mushrooms"] > 0, true]
	var infos := ["Stomp! Press Z as you land for a 2nd hit.", sp["info"], "Heal 10 HP.", "Try to escape."]
	message.text = "Your turn"
	var choice: String = options[await menu.choose(options, me["name"], false, enabled, infos)]
	if over:
		return
	message.text = ""
	if choice == "Run":
		if randf() < 0.5:
			Net.end_duel("fled")
			over = true
			message.text = "Got away safely!"
			await _wait(1.0)
			Game.end_battle("fled")
			return
		message.text = "Couldn't get away!"
		Net.duel_send({"t": "duel_act", "move": "wait", "hp": _hp(me)})
		await _wait(0.8)
		return
	if choice.begins_with("Mushroom"):
		p["mushrooms"] -= 1
		_heal(me, 10)
		Net.duel_send({"t": "duel_act", "move": "heal", "hp": _hp(me), "name": "Mushroom"})
		await _wait(0.8)
		return
	var move := "jump"
	var move_name := "Jump"
	var hits: Array = []
	var result := "Miss"
	if choice == "Jump":
		result = await _jump_at_foe()
		hits = [me["pow"]]
		if result != "Miss":
			hits.append(me["pow"] + (1 if result == "Excellent" else 0))
	else:
		p["sp"] -= sp["sp"]
		move = "special"
		move_name = sp["name"]
		message.text = move_name + "!"
		result = await _timing_bar(1.0)
		var bonus: int = {"Excellent": 3, "Good": 1, "Miss": 0}[result]
		if sp_id == "peach_heart":
			_heal(me, {"Excellent": 14, "Good": 10, "Miss": 6}[result])
			Net.duel_send({"t": "duel_act", "move": "heal", "hp": _hp(me), "name": move_name})
			await _wait(0.8)
			return
		if sp_id in ["star_spin", "shadow_drain", "poltergust_pull"]:
			_heal(me, {"Excellent": 5, "Good": 3, "Miss": 1}[result])
		hits = [me["pow"] + 2 + bonus]
		await _walk(me["node"], foe["node"].position + Vector2(-22, 0), 220.0)
	_refresh()
	Net.duel_send({"t": "duel_act", "move": move, "hits": hits, "rating": result, "hp": _hp(me), "name": move_name})
	message.text = "..."
	var hit := await _await_message("duel_hit", HIT_TIMEOUT)
	if over:
		return
	if hit.is_empty():
		Net.end_duel("timeout")
		await _foe_gone("timeout")
		return
	var dmg := int(hit.get("dmg", 0))
	foe["hp"] = clampi(int(hit.get("hp", foe["hp"])), 0, foe["max_hp"])
	if hit.get("dodged", false):
		_show_rating("Dodged!")
		message.text = "%s jumped out of the way!" % foe["name"]
	else:
		_flash(foe["node"])
		_popup(foe["node"].position + Vector2(0, -50), str(dmg))
		message.text = ""
	_refresh()
	await _walk(me["node"], me["home"], 160.0)
	me["node"].facing = Vector2.RIGHT
	await _wait(0.4)


## battle.gd's jump, without dealing damage (the foe's game works that out).
func _jump_at_foe() -> String:
	var node: CharacterSprite = me["node"]
	var target: CharacterSprite = foe["node"]
	var stand: Vector2 = target.position + Vector2(-40, 0)
	var top: Vector2 = target.position + Vector2(0, -target.height() * SCALE * 0.8)
	message.text = "Press Z just as you land!"
	await _walk(node, stand, 160.0)
	var result := _rate_landing(await _arc(node, node.position, top, 50.0, 0.55, true))
	_show_rating(result)
	if result != "Miss":
		await _arc(node, top, top, 38.0, 0.45, false)
	await _arc(node, node.position, stand, 28.0, 0.35, false)
	return result


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
			await _wait(1.0)
		"heal":
			var healed := their_hp - int(foe["hp"])
			foe["hp"] = their_hp
			message.text = "%s used %s!" % [foe["name"], act.get("name", "a Mushroom")]
			_show_rating("+%d HP" % maxi(0, healed))
			_refresh()
			await _wait(1.0)
		_:
			foe["hp"] = their_hp
			_refresh()
			await _take_attack(act)


## The foe charges; jump (Z) so you're in the air when it reaches you.
func _take_attack(act: Dictionary) -> void:
	var node: CharacterSprite = me["node"]
	var fnode: CharacterSprite = foe["node"]
	message.text = "%s uses %s! Press Z to jump!" % [foe["name"], act.get("name", "an attack")]
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
	var dodged: bool = node.jump_height > 8.0
	var dmg := 0
	if dodged:
		_show_rating("Dodged!")
		await _slide(fnode, contact + Vector2(-60, 0), 0.25)
	else:
		for h in act.get("hits", []):
			dmg += maxi(1, int(h) - int(me["def"]))
		_set_hp(me, _hp(me) - dmg)
		_flash(node)
		_popup(node.position + Vector2(0, -50), str(dmg))
		_refresh()
		await _slide(fnode, contact + Vector2(20, 0), 0.15)
	Net.duel_send({"t": "duel_hit", "dmg": dmg, "hp": _hp(me), "dodged": dodged})
	fnode.move_velocity = Vector2.RIGHT * 100
	await _slide(fnode, foe["home"], 0.4)
	fnode.move_velocity = Vector2.ZERO
	fnode.facing = Vector2.LEFT
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
			menu.visible = false
			message.text = "%s ran away!" % foe["name"]
			await _wait(1.2)
			Game.end_battle("fled")
		"timeout":
			# We took too long; the foe's game called it.
			_duel_lost()
		_:
			_foe_gone(result)


## The foe stopped answering ("timeout": their game drops coins too) or
## left the map (you win, but they drop nothing).
func _foe_gone(why: String) -> void:
	if over:
		return
	message.text = ("%s ran out of time!" if why == "timeout" else "%s left the battle.") % foe["name"]
	_duel_won(why == "timeout")


func _duel_won(coins_dropped: bool) -> void:
	over = true
	menu.visible = false
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
	await _wait(0.6)
	message.text = "You beat %s! +%d XP  +%d coins" % [foe["name"], xp, coins]
	_refresh()
	await _wait(1.8)
	if levels > 0:
		message.text = "Level up! %s is now level %d!" % [Game.character_name(), p["level"]]
		_show_rating("LEVEL UP!")
		_refresh()
		await _wait(1.8)
	Game.end_battle("won")


func _duel_lost() -> void:
	over = true
	menu.visible = false
	var drop: int = Game.pvp_drop(Game.player["coins"])
	message.text = "%s beat you... You dropped %d coins." % [foe["name"], drop]
	await _wait(2.2)
	Game.end_battle("lost")  # home town, 10% of coins lost (the drop above)


# --- Helpers ---------------------------------------------------------------------

func _heal(a: Dictionary, amount: int) -> void:
	_set_hp(a, _hp(a) + amount)
	_show_rating("+%d HP" % amount)
	_refresh()


## Waits for the foe's next message of type `t`. Returns {} on timeout or
## once the duel is over.
func _await_message(t: String, timeout: float) -> Dictionary:
	var waited := 0.0
	while waited < timeout and not over:
		for i in _inbox.size():
			if _inbox[i].get("t") == t:
				return _inbox.pop_at(i)
		await get_tree().process_frame
		waited += get_process_delta_time()
	return {}
