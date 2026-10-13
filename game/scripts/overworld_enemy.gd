extends Area2D
## An enemy wandering the overworld. Touching the Bros. starts a battle.

@export var enemy_type := "goomba"
@export var wander_radius := 40.0
@export var speed := 25.0

@onready var sprite: Sprite2D = $Sprite2D

var _home := Vector2.ZERO
var _target := Vector2.ZERO
var _anim_time := 0.0
var _pause := 0.0


func _ready() -> void:
	if Game.defeated_enemies.has(_id()):
		queue_free()
		return
	_home = position
	_target = position
	body_entered.connect(_on_body_entered)


func _id() -> String:
	return str(get_path())


func _process(delta: float) -> void:
	_anim_time += delta
	sprite.frame = int(_anim_time * 8.0) % sprite.hframes
	if _pause > 0.0:
		_pause -= delta
		return
	position = position.move_toward(_target, speed * delta)
	if position.distance_to(_target) < 1.0:
		_pause = randf_range(0.4, 1.5)
		_target = _home + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * wander_radius


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		set_deferred("monitoring", false)
		# Step the Bros. back a little so they don't land on the enemy's spot.
		var away: Vector2 = (body.global_position - global_position).normalized() * 24.0
		Game.start_battle(_id(), enemy_type, body.global_position + away)
