class_name OnlinePlayers
extends Node
## Draws the other players on this map (from Net) and puts name tags over
## everyone, including you. The world creates one and calls setup().

const GLIDE_SPEED := 96.0

var others := {}  # id -> {node, target, velocity}
var _spawn: Callable  # world._spawn_character
var _player: CharacterSprite


func setup(spawn_character: Callable, local_player: CharacterSprite, map_id: String) -> void:
	_spawn = spawn_character
	_player = local_player
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
