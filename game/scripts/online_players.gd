class_name OnlinePlayers
extends Node
## Draws the other players on this map (from Net), puts name tags over
## everyone (you included), runs text chat with speech bubbles, and handles
## parties: X next to another player to team up; your partner's tag is green
## and taking an exit brings them along. Evil players can also pick "Battle!"
## on a good player outside town to start an online duel (pvp_battle.gd).
## The world creates one and calls setup(), then tick() every frame.

const GLIDE_SPEED := 96.0
const BUBBLE_SECONDS := 5.0
const REACH := 26.0  # how close you must be to press X on someone
const PARTNER_COLOR := Color(0.55, 1, 0.55)
const REACH_COLOR := Color(1, 0.9, 0.3)
const CHALLENGE_WAIT := 10.0  # give up if the other game doesn't answer by then
const BUSY_GRACE := 6.0       # an attacked player in a menu gets this long to close it

var others := {}  # id -> {node, target, velocity}
var _spawn: Callable  # world._spawn_character
var _player: CharacterSprite
var _world: Node  # has `busy`, which pauses movement while you type
var chat: ChatBox
var _invites: Array = []  # [{from, name}] waiting for you to answer
var _map_id := ""
static var _announced := ""  # partner already announced, so map changes don't repeat it
static var _followed := false  # arrived by following, so step aside from the partner
var _challenge := {}  # an evil player attacked you: start once you're free
var _challenge_age := 0.0
var _waiting := 0.0  # seconds left waiting for the player you attacked
## Optional: maps a reported position onto ground walkable on this map.
var snap := Callable()


func setup(world: Node, spawn_character: Callable, local_player: CharacterSprite, map_id: String) -> void:
	_world = world
	_spawn = spawn_character
	_player = local_player
	_map_id = map_id
	if _followed:
		_followed = false
		_player.position = _world.nearest_walkable(_player.position + Vector2(-28, 6))
	chat = ChatBox.new()
	add_child(chat)
	chat.message_shown.connect(_show_bubble)
	Net.invited.connect(func(from_id, who): _invites.append({"from": from_id, "name": who}))
	Net.invite_declined.connect(func(who): chat.system("%s said no thanks." % who))
	Net.party_changed.connect(_on_party_changed)
	Net.in_world = true
	tree_exiting.connect(func(): Net.in_world = false)
	Net.challenged.connect(_on_challenged)
	Net.party_message.connect(_on_party_message)
	Net.duel_started.connect(_on_duel_started)
	Net.duel_over.connect(_on_duel_over)
	add_name_tag(_player, Game.username())
	Net.player_joined.connect(_on_player_joined)
	Net.player_moved.connect(_on_player_moved)
	Net.player_jumped.connect(_on_player_jumped)
	Net.player_left.connect(_on_player_left)
	Net.zone_reset.connect(_clear)
	# Coming back from a battle keeps the connection, so draw who is already here.
	for p in Net.players.values():
		_on_player_joined(p)
	Net.join_zone(map_id, Game.player["character"], Game.username(), _player.position)


## Call every frame from the world.
func tick(delta: float, busy: bool) -> void:
	Net.update_position(_player.position, Vector2.ZERO if busy else _player.move_velocity)
	var near := _nearest_other()
	for id in others:
		var tag: Label = others[id]["node"].get_node("NameTag")
		tag.modulate = PARTNER_COLOR if id == Net.party_id else (REACH_COLOR if id == near and not busy else Color.WHITE)
	if _waiting > 0.0:
		_waiting -= delta
		if _waiting <= 0.0:
			Net.end_duel("cancel")
			chat.system("They didn't answer.")
	if not _challenge.is_empty():
		_challenge_age += delta
		if not busy:
			Net.answer_challenge(true)
			_challenge = {}
		elif _challenge_age > BUSY_GRACE:
			Net.answer_challenge(false)
			_challenge = {}
	if busy:
		return
	if not Net.pending_warp.is_empty():
		_follow_partner()
	elif not _invites.is_empty():
		_answer_invite(_invites.pop_front())
	elif chat.wants_to_open():
		_type_chat()
	elif near != "" and _world.keys_ready() and Input.is_action_just_pressed("talk") and _world._nearest_npc() == null:
		_interact(near)
	for o in others.values():
		var node: CharacterSprite = o["node"]
		var to: Vector2 = o["target"] - node.position
		if to.length() > GLIDE_SPEED:
			node.position = o["target"]
		else:
			node.position += to.limit_length(maxf(GLIDE_SPEED * 1.2, to.length() * 6.0) * delta)
		# Walk animation follows their reported velocity, so it doesn't stutter
		# between updates; a last glide after they stop still animates.
		var velocity: Vector2 = o["velocity"]
		if velocity.length() < 1.0 and to.length() > 1.0:
			velocity = to.normalized() * GLIDE_SPEED
		node.move_velocity = velocity


func _type_chat() -> void:
	_world.busy = true
	await chat.type_message()
	_world.busy = false


func _nearest_other() -> String:
	var best := ""
	var best_d := REACH
	for id in others:
		var d: float = others[id]["node"].position.distance_to(_player.position)
		if d < best_d:
			best = id
			best_d = d
	return best


## X next to another player.
func _interact(id: String) -> void:
	var who: String = Net.players[id]["name"]
	var options := ["Team up", "Cancel"]
	var enabled := [Net.party_id == "", true]
	var infos := ["Travel together.", ""]
	if id == Net.party_id:
		options = ["Leave party", "Cancel"]
		enabled = [true, true]
		infos = ["Go separate ways.", ""]
	elif Game.player["side"] == "evil" and Net.players[id].get("side", "good") == "good":
		var town: bool = Game.MAPS[_map_id].get("safe", true)
		options.insert(0, "Battle!")
		enabled.insert(0, not town and _waiting <= 0.0)
		infos.insert(0, "No fighting in town." if town else "Take them down!")
	_world.busy = true
	var i: int = await _world.menu.choose(options, who, true, enabled, infos)
	_world.busy = false
	if i < 0 or options[i] == "Cancel" or not Net.players.has(id):
		return
	match options[i]:
		"Battle!":
			Net.challenge(id)
			_waiting = CHALLENGE_WAIT
			chat.system("You attack %s!" % who)
		"Team up":
			Net.send_invite(id)
			chat.system("You asked %s to team up." % who)
		"Leave party":
			chat.system("You left the party with %s." % who)
			Net.leave_party()


func _answer_invite(inv: Dictionary) -> void:
	if Net.party_id != "" or not Net.players.has(inv["from"]):
		Net.answer_invite(inv["from"], false)
		return
	_world.busy = true
	var i: int = await _world.menu.choose(["Team up!", "No thanks"], "%s wants to team up" % inv["name"], false, [],
		["Travel together.", ""])
	_world.busy = false
	Net.answer_invite(inv["from"], i == 0)


## Your partner touched an enemy: jump into their battle if you're free.
func _on_party_message(d: Dictionary) -> void:
	if d.get("kind") != "coop_start":
		return
	if _world.busy or not _challenge.is_empty() or Net.duel_foe != "":
		Net.send_party({"kind": "coop_no"})
		return
	var p: Dictionary = Game.player
	Net.send_party({"kind": "coop_yes", "name": Game.username(), "id": p["character"],
		"hp": p["hp"], "max_hp": p["max_hp"], "pow": p["pow"], "def": p["def"]})
	_world.busy = true
	Game.join_coop(d, _player.position)


func _on_challenged(foe: Dictionary) -> void:
	_challenge = foe
	_challenge_age = 0.0
	chat.system("%s attacks you!" % foe["name"])


func _on_duel_started(foe: Dictionary, first: bool) -> void:
	_waiting = 0.0
	_world.busy = true
	Game.start_pvp(foe, first, _player.position)


func _on_duel_over(result: String) -> void:
	_waiting = 0.0
	_challenge = {}
	match result:
		"busy":
			chat.system("They're busy. Try again in a moment.")
		"refused":
			chat.system("You can't attack them right now.")


func _on_party_changed() -> void:
	if Net.party_id == "":
		chat.system("The party is over.")
		_announced = ""
	elif Net.party_here and _announced != Net.party_id:
		chat.system("Teamed up with %s! /p to talk, exits take you both." % Net.party_name)
		_announced = Net.party_id


func _follow_partner() -> void:
	var warp: Dictionary = Net.pending_warp
	Net.pending_warp = {}
	if warp["map"] == _map_id or not Game.MAPS.has(warp["map"]):
		return
	chat.system("Following %s..." % Net.party_name)
	_world.busy = true
	_followed = true
	Game.go_to_map(warp["map"], warp["spawn"])


## A speech bubble over whoever just said something.
func _show_bubble(id: String, text: String) -> void:
	var node: CharacterSprite = _player if id == Net.my_id else (others[id]["node"] if others.has(id) else null)
	if node == null:
		return
	var old := node.get_node_or_null("Bubble")
	if old:
		old.free()
	var bubble := PanelContainer.new()
	bubble.name = "Bubble"
	bubble.theme_type_variation = &"NavyPanel"
	bubble.z_index = 11
	var label := Label.new()
	label.theme_type_variation = &"LightLabel"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = minf(140.0, 8.0 + text.length() * 6.0)
	bubble.add_child(label)
	node.add_child(bubble)
	bubble.size = bubble.get_combined_minimum_size()
	bubble.position = Vector2(-bubble.size.x / 2.0, -node.height() - 16 - bubble.size.y)
	get_tree().create_timer(BUBBLE_SECONDS).timeout.connect(func():
		if is_instance_valid(bubble):
			bubble.queue_free())


static func add_name_tag(node: CharacterSprite, text: String) -> Label:
	var tag := Label.new()
	tag.name = "NameTag"
	tag.text = text
	tag.theme_type_variation = &"OutlineLabel"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.size = Vector2(96, 14)
	tag.position = Vector2(-48, -node.height() - 14)
	tag.z_index = 10
	node.add_child(tag)
	return tag


func _on_player_joined(p: Dictionary) -> void:
	if others.has(p["id"]):
		return
	# A character this version of the game doesn't have yet (someone on a
	# newer build) is drawn as Mario rather than hidden.
	var character: String = p["character"] if Game.CHARACTERS.has(p["character"]) else "mario"
	var node: CharacterSprite = _spawn.call(character)
	node.position = _snapped(Vector2(p["x"], p["y"]))
	add_name_tag(node, p["name"])
	others[p["id"]] = {"node": node, "target": node.position, "velocity": Vector2.ZERO}


func _on_player_moved(id: String, pos: Vector2, velocity: Vector2) -> void:
	if others.has(id):
		others[id]["target"] = _snapped(pos)
		others[id]["velocity"] = velocity


func _snapped(pos: Vector2) -> Vector2:
	return snap.call(pos) if snap.is_valid() else pos


func _on_player_jumped(id: String) -> void:
	if others.has(id):
		others[id]["node"].jump()


func _on_player_left(id: String) -> void:
	if others.has(id):
		others[id]["node"].queue_free()
		others.erase(id)


func _clear() -> void:
	for o in others.values():
		o["node"].queue_free()
	others.clear()
