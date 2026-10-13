class_name OnlinePlayers
extends Node
## Draws the other players on this map (from Net), puts name tags over
## everyone (you included), and runs text chat with speech bubbles.
## The world creates one and calls setup(), then tick() every frame.

const GLIDE_SPEED := 96.0
const BUBBLE_SECONDS := 5.0

var others := {}  # id -> {node, target, velocity}
var _spawn: Callable  # world._spawn_character
var _player: CharacterSprite
var _world: Node  # has `busy`, which pauses movement while you type
var chat: ChatBox


func setup(world: Node, spawn_character: Callable, local_player: CharacterSprite, map_id: String) -> void:
	_world = world
	_spawn = spawn_character
	_player = local_player
	chat = ChatBox.new()
	add_child(chat)
	chat.message_shown.connect(_show_bubble)
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
	if not busy and chat.wants_to_open():
		_type_chat()
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
	node.position = Vector2(p["x"], p["y"])
	add_name_tag(node, p["name"])
	others[p["id"]] = {"node": node, "target": node.position, "velocity": Vector2.ZERO}


func _on_player_moved(id: String, pos: Vector2, velocity: Vector2) -> void:
	if others.has(id):
		others[id]["target"] = pos
		others[id]["velocity"] = velocity


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
