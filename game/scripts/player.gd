extends CharacterBody2D
## Mario leads; Luigi walks the same path a few steps behind, like in
## Superstar Saga. Z jumps with Mario, X jumps with Luigi.

const SPEED := 75.0
const FOLLOW_DISTANCE := 16.0

@export var follower: BroSprite

@onready var visual: BroSprite = $Visual

var _trail: Array[Vector2] = []


func _ready() -> void:
	add_to_group("player")
	if Game.has_return_position:
		global_position = Game.return_position
	if follower:
		follower.global_position = global_position + Vector2(-FOLLOW_DISTANCE, 0)
		_trail.append(follower.global_position)
		follower.facing = Vector2.RIGHT
		visual.facing = Vector2.RIGHT


func _physics_process(_delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input * SPEED
	move_and_slide()
	visual.move_velocity = get_real_velocity()

	if Input.is_action_just_pressed("mario_action"):
		visual.jump()
	if follower and Input.is_action_just_pressed("luigi_action"):
		follower.jump()
	_update_follower()


func _update_follower() -> void:
	if follower == null:
		return
	if _trail.is_empty() or _trail.back().distance_to(global_position) > 1.0:
		_trail.append(global_position)
	# Walk toward the trail point that is FOLLOW_DISTANCE behind Mario.
	var target := follower.global_position
	while _trail.size() > 1 and _trail[0].distance_to(global_position) > FOLLOW_DISTANCE:
		target = _trail.pop_front()
	var step := target - follower.global_position
	follower.global_position = target
	follower.move_velocity = step / get_physics_process_delta_time() if step.length() > 0.01 else Vector2.ZERO
