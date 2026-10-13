extends "res://scripts/battle.gd"
## A normal battle (battle.gd) that your party partner joins from their own
## game. This game runs the battle; the partner's game (coop_guest.gd) shows
## it and plays their part. Messages go through Net.send_party:
##   to partner:   setup, state (HP and the message line), turn (pick a move),
##                 dodge (an enemy is charging at you), end (result + rewards)
##   from partner: coop_yes / coop_no, act (their move), dodged
## If the partner can't come, doesn't answer or leaves, the battle carries on
## without them.

const ANSWER_WAIT := 3.0
const TURN_WAIT := 40.0
const DODGE_WAIT := 6.0
const EXTRA_SPOT := Vector2(96, 124)

var guest := {}  # the partner's battle actor, once they've joined
var _inbox: Array = []
var _last_state := ""
var _result := "fled"


func _ready() -> void:
	Net.party_message.connect(func(d): _inbox.append(d))
	Net.send_party({"kind": "coop_start"})
	message.text = "Calling %s..." % Net.party_name
	var answer := await _await_party(["coop_yes", "coop_no"], ANSWER_WAIT)
	message.text = ""
	super()
	if answer.get("kind") == "coop_yes":
		_add_guest(answer)
	tree_exiting.connect(func(): Net.send_party({"kind": "end", "result": _result}))


func _add_guest(info: Dictionary) -> void:
	var node := CharacterSprite.new()
	var character := str(info.get("id", "mario"))
	node.character_id = character if Game.CHARACTERS.has(character) else "mario"
	node.facing = Vector2.RIGHT
	node.scale = Vector2(SCALE, SCALE)
	node.position = ALLY_SPOTS[allies.size()] if allies.size() < ALLY_SPOTS.size() else EXTRA_SPOT
	stage.add_child(node)
	var member := {"name": str(info.get("name", "Partner")), "max_hp": maxi(1, int(info.get("max_hp", 10))),
		"hp": maxi(1, int(info.get("hp", 10))), "pow": int(info.get("pow", 1)), "def": int(info.get("def", 0))}
	guest = {"name": member["name"], "node": node, "member": member, "ally": true, "home": node.position,
		"pow": member["pow"], "def": member["def"], "remote": true}
	allies.append(guest)
	var ally_list := []
	for a in allies:
		ally_list.append([a["name"], a["node"].character_id, a["home"].x, a["home"].y])
	var foe_list := []
	for f in foes:
		foe_list.append([f["name"], f["type"], f["home"].x, f["home"].y])
	Net.send_party({"kind": "setup", "allies": ally_list, "foes": foe_list, "me": allies.size() - 1})
	_refresh()


# --- The partner's turn ----------------------------------------------------------

func _ally_turn(a: Dictionary) -> String:
	if not a.get("remote", false):
		return await super(a)
	if not Net.party_here:
		_drop_guest()
		return ""
	message.text = "%s's turn" % a["name"]
	_inbox.clear()
	Net.send_party({"kind": "turn"})
	var act := await _await_party(["act"], TURN_WAIT)
	if act.is_empty():
		message.text = "%s is away." % a["name"]
		await _wait(0.8)
		if not Net.party_here:
			_drop_guest()
		return ""
	message.text = ""
	match str(act.get("move", "")):
		"heal":
			_set_hp(a, int(act.get("hp", _hp(a))))
			_show_rating("+HP")
			_refresh()
			await _wait(0.6)
		"jump", "special":
			var alive := _alive(foes)
			if alive.is_empty():
				return ""
			var i := int(act.get("target", 0))
			var target: Dictionary = foes[i] if i >= 0 and i < foes.size() and _hp(foes[i]) > 0 else alive[0]
			await _remote_attack(a, target, act)
	return ""


## Plays the partner's move on this screen and deals its damage.
func _remote_attack(a: Dictionary, target: Dictionary, act: Dictionary) -> void:
	var node: CharacterSprite = a["node"]
	var hits: Array = act.get("hits", [])
	_show_rating(str(act.get("rating", "")))
	if act.get("move") == "jump":
		var stand: Vector2 = target["node"].position + Vector2(-40, 0)
		var top: Vector2 = target["node"].position + Vector2(0, -target["node"].height() * SCALE * 0.8)
		await _walk(node, stand, 160.0)
		await _arc(node, node.position, top, 50.0, 0.55, false)
		for i in hits.size():
			_damage(target, clampi(int(hits[i]), 0, 99))
			if i < hits.size() - 1:
				await _arc(node, top, top, 38.0, 0.45, false)
		await _arc(node, node.position, stand, 28.0, 0.35, false)
	else:
		message.text = str(act.get("name", "Special")) + "!"
		await _walk(node, target["node"].position + Vector2(-22, 0), 220.0)
		for h in hits:
			_damage(target, clampi(int(h), 0, 99))
	await _walk(node, a["home"], 160.0)
	node.facing = Vector2.RIGHT
	await _wait(0.4)


## The partner went away: they sit out the rest of the battle. (Still listed
## in `allies`, since this can happen while battle.gd loops over it.)
func _drop_guest() -> void:
	if guest.is_empty() or _hp(guest) <= 0:
		return
	guest["member"]["hp"] = 0
	guest["node"].visible = false
	message.text = "%s left the battle." % guest["name"]
	_refresh()


# --- Enemy turns: same as battle.gd, but the partner dodges on their own screen ----

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
	if await _foe_attack_taken(f, target):  # Mimic's memory, Vivian's Shade Veil
		return
	await _charge(f, target, not target.get("remote", false))


## Like battle.gd's enemy charge. `local`: Z (A on touch) jumps here;
## otherwise the partner's game plays the dodge and says whether it worked.
func _charge(f: Dictionary, target: Dictionary, local: bool) -> void:
	var node: CharacterSprite = target["node"]
	_say("%s charges at %s! Press {a} to jump!" if local else "%s charges at %s!", [f["name"], target["name"]])
	var badge: Sprite2D = _show_badge(target, "jump") if local else null
	var fnode: CharacterSprite = f["node"]
	for i in 6:
		fnode.position.x = f["home"].x + (2.0 if i % 2 == 0 else -2.0)
		await _wait(0.07)
	fnode.position = f["home"]
	var duration := randf_range(0.55, 0.85)
	if not local:
		_inbox.clear()
		Net.send_party({"kind": "dodge", "foe": foes.find(f), "time": duration})
	var start := fnode.position
	var contact := Vector2(node.position.x + 8, node.position.y)
	var t := 0.0
	while t < duration:
		await get_tree().process_frame
		t = minf(t + get_process_delta_time(), duration)
		fnode.position = start.lerp(contact, t / duration)
		fnode.move_velocity = Vector2.LEFT * 100
		if local and Input.is_action_just_pressed("action"):
			node.jump()
	if badge:
		badge.queue_free()
	var dodged: bool = node.jump_height > 8.0
	if not local:
		var answer := await _await_party(["dodged"], DODGE_WAIT)
		dodged = answer.get("ok", false) == true
		if dodged:
			node.jump()
	if dodged:
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


# --- Endings and keeping the partner's screen up to date ---------------------------

func _win() -> void:
	_result = "won"
	Net.send_party({"kind": "end", "result": "won", "xp": xp_earned, "coins": coins_earned,
		"hp": _hp(guest) if not guest.is_empty() else 0})
	await super()


func _lose() -> void:
	_result = "lost"
	Net.send_party({"kind": "end", "result": "lost"})
	await super()


func _refresh() -> void:
	super()
	_send_state()


func _process(delta: float) -> void:
	super(delta)
	if message.text != _last_state:
		_send_state()


func _send_state() -> void:
	if guest.is_empty():
		return
	_last_state = message.text
	var a_hp := []
	for a in allies:
		a_hp.append([_hp(a), a["member"]["max_hp"]])
	var f_hp := []
	for f in foes:
		f_hp.append(f["hp"])
	Net.send_party({"kind": "state", "msg": message.text.left(90), "allies": a_hp, "foes": f_hp})


## Waits for one of `kinds` from the partner. {} on timeout.
func _await_party(kinds: Array, timeout: float) -> Dictionary:
	var waited := 0.0
	while waited < timeout:
		for i in _inbox.size():
			if _inbox[i].get("kind") in kinds:
				return _inbox.pop_at(i)
		await get_tree().process_frame
		waited += get_process_delta_time()
	return {}
