class_name BroSprite
extends Node2D
## Draws one brother from a walk sheet (8 frames x 5 rows: down, down-right,
## right, up-right, up; left directions are mirrored) and handles jumping.

const FRAMES := 8
const ROWS := 5
const GRAVITY := 650.0
const JUMP_SPEED := 190.0
const WALK_FPS := 12.0

@export var texture: Texture2D
@export var facing := Vector2.DOWN

## Set every frame by whoever moves this brother; drives the walk animation.
var move_velocity := Vector2.ZERO
var jump_height := 0.0

var _jump_velocity := 0.0
var _anim_time := 0.0
var _sprite: Sprite2D


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.hframes = FRAMES
	_sprite.vframes = ROWS
	_sprite.offset = Vector2(0, -24)  # feet sit on this node's origin
	add_child(_sprite)
	_update_frame()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 7.0, Color(0, 0, 0, 0.35))


func is_airborne() -> bool:
	return jump_height > 0.0 or _jump_velocity > 0.0


func jump() -> void:
	if not is_airborne():
		_jump_velocity = JUMP_SPEED


func _process(delta: float) -> void:
	if move_velocity.length() > 1.0:
		facing = move_velocity.normalized()
		_anim_time += delta
	else:
		_anim_time = 0.0
	if is_airborne():
		jump_height += _jump_velocity * delta
		_jump_velocity -= GRAVITY * delta
		if jump_height <= 0.0:
			jump_height = 0.0
			_jump_velocity = 0.0
	_sprite.position.y = -jump_height
	_update_frame()


func _update_frame() -> void:
	if _sprite == null:
		return
	# Angle from straight right (0) to straight down (90) / up (-90).
	var angle := rad_to_deg(atan2(facing.y, absf(facing.x)))
	var row := 2
	if angle > 67.5:
		row = 0
	elif angle > 22.5:
		row = 1
	elif angle > -22.5:
		row = 2
	elif angle > -67.5:
		row = 3
	else:
		row = 4
	var col := int(_anim_time * WALK_FPS) % FRAMES if _anim_time > 0.0 else 0
	if is_airborne():
		col = 2
	_sprite.frame = row * FRAMES + col
	_sprite.flip_h = facing.x < -0.01
