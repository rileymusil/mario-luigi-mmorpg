class_name CharacterSprite
extends Node2D
## Draws a character from res://assets/characters/<id>.png (3 rows: down,
## right, up; left is the right row mirrored), animates walking and jumps.
## Bosses also loop their idle frames and have a 4th row, their attack.

const GRAVITY := 650.0
const JUMP_SPEED := 190.0
const WALK_FPS := 12.0
const IDLE_FPS := 8.0     # bosses' idle loop
const ATTACK_FPS := 12.0  # bosses' attack row

## Emitted when a jump starts (followers replay it where it happened).
signal jumped

@export var character_id := "mario":
	set(value):
		character_id = value
		if is_inside_tree():
			_load_sheet()
@export var facing := Vector2.DOWN

## Set every frame by whoever moves this character; drives the walk cycle.
var move_velocity := Vector2.ZERO
var jump_height := 0.0

var _jump_velocity := 0.0
var _anim_time := 0.0
## Keeps the walk cycle going through a frame or two without movement:
## followers step along the leader's trail in uneven hops, and other players'
## positions arrive in bursts, so their velocity drops to zero now and then.
const WALK_HOLD := 0.15
var _walk_hold := 0.0
var _frames := 8
var _sprite: Sprite2D
var _squash := Vector2.ONE
var _was_airborne := false
var _jump_buffer := 0.0
var _rows := 3            # sheet rows: down, side, up (+ attack, see play_attack)
var _idle := 0            # bosses: frames of the idle loop played while standing
var _attack := 0          # bosses: frames in the attack row
var _idle_time := 0.0
var _attack_time := -1.0  # >= 0 while the attack row plays
var _attack_hold := false


func _ready() -> void:
	_sprite = Sprite2D.new()
	add_child(_sprite)
	_load_sheet()


func _load_sheet() -> void:
	var info: Dictionary = Game.CHARACTERS.get(character_id, Game.PARTNERS.get(character_id,
		Game.ENEMIES.get(character_id, Game.NPCS.get(character_id, Game.BOSSES.get(character_id,
		Game.BOSS_MINIONS.get(character_id, Game.BOSS_FORMS.get(character_id, {})))))))
	_frames = info.get("frames", 8)
	_idle = int(info.get("idle", 0))
	_attack = int(info.get("attack", 0))
	_rows = Game.sheet_rows(info)
	_attack_time = -1.0
	_sprite.texture = load("res://assets/characters/%s.png" % character_id)
	_sprite.hframes = _frames
	_sprite.vframes = _rows
	_sprite.centered = true
	# Feet sit on this node's origin.
	_sprite.offset = Vector2(0, -_sprite.texture.get_height() / (2.0 * _rows))
	_update_frame()
	queue_redraw()


func width() -> float:
	return _sprite.texture.get_width() / float(_frames) if _sprite and _sprite.texture else 16.0


func height() -> float:
	return _sprite.texture.get_height() / float(_rows) if _sprite and _sprite.texture else 32.0


## How big to draw this character in battle: `base`, but never taller than
## `max_height` px (the biggest bosses).
func battle_scale(base: float, max_height := 120.0) -> float:
	return minf(base, max_height / maxf(height(), 1.0))


## Plays the attack row once (bosses with one). hold: stay on its last frame
## until end_attack().
func play_attack(hold := false) -> void:
	if _attack > 0:
		_attack_time = 0.0
		_attack_hold = hold


func end_attack() -> void:
	_attack_time = -1.0


func _draw() -> void:
	var w := 7.0
	if _sprite and _sprite.texture:
		w = clampf(_sprite.texture.get_width() / float(_frames) * 0.3, 5.0, 14.0)
	# Shadow smoothly scales down and softly fades as character jumps higher
	var height_ratio := clampf(1.0 - jump_height / 70.0, 0.45, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0 * height_ratio, 0.4 * height_ratio))
	draw_circle(Vector2.ZERO, w, Color(0, 0, 0, 0.32 * height_ratio))


func is_airborne() -> bool:
	return jump_height > 0.0 or _jump_velocity > 0.0


func jump() -> void:
	if not is_airborne():
		_jump_velocity = JUMP_SPEED
		_squash = Vector2(0.86, 1.18)
		jumped.emit()
	else:
		# Buffer jump if requested close to landing
		_jump_buffer = 0.14


## Puts the character `h` px above the ground under it, keeping its jump
## going. The world uses it when someone hops up or drops down a ledge face:
## their feet move to the new ground and this keeps the sprite where it was.
func set_air(h: float) -> void:
	if h > 0.0:
		jump_height = h
	else:
		if jump_height > 0.0:
			_squash = Vector2(1.24, 0.8)  # landed on the ledge
		jump_height = 0.0
		_jump_velocity = maxf(_jump_velocity, 0.0)
	queue_redraw()


func _process(delta: float) -> void:
	if move_velocity.length() > 1.0:
		facing = move_velocity.normalized()
		_walk_hold = WALK_HOLD
	else:
		_walk_hold -= delta
	if _walk_hold > 0.0:
		_anim_time += delta
	else:
		_anim_time = 0.0

	if _jump_buffer > 0.0:
		_jump_buffer -= delta
	_idle_time += delta
	if _attack_time >= 0.0:
		_attack_time += delta
		if not _attack_hold and _attack_time * ATTACK_FPS >= _attack + 2:
			_attack_time = -1.0

	var airborne_now := is_airborne()
	if airborne_now:
		jump_height += _jump_velocity * delta
		_jump_velocity -= GRAVITY * delta
		if jump_height <= 0.0:
			jump_height = 0.0
			_jump_velocity = 0.0
			# Landing impact squash!
			_squash = Vector2(1.24, 0.8)
			if _jump_buffer > 0.0:
				_jump_buffer = 0.0
				_jump_velocity = JUMP_SPEED
				_squash = Vector2(0.86, 1.18)
				jumped.emit()
		queue_redraw()
	elif _was_airborne and jump_height == 0.0:
		queue_redraw()

	_was_airborne = airborne_now

	# Elastic recovery of squash and stretch back to 1.0
	_squash = _squash.lerp(Vector2.ONE, clampf(18.0 * delta, 0.0, 1.0))

	if _sprite:
		# Sheets with a single pose per direction hop a little instead of a walk cycle.
		var hop := absf(sin(_anim_time * WALK_FPS * 0.5)) * 2.0 if _frames == 1 else 0.0
		_sprite.position.y = -jump_height - hop
		_sprite.scale = _squash

	_update_frame()


func _update_frame() -> void:
	if _sprite == null or _sprite.texture == null:
		return
	if _attack_time >= 0.0:
		_sprite.frame = 3 * _frames + mini(int(_attack_time * ATTACK_FPS), _attack - 1)
		_sprite.flip_h = facing.x < 0.0
		return
	var is_side_only: bool = character_id in ["buzzy_beetle", "shy_guy"]
	var row := 1
	if not is_side_only and absf(facing.y) > absf(facing.x) * 1.2:
		row = 0 if facing.y > 0.0 else 2
	var col := int(_anim_time * WALK_FPS) % _frames if _anim_time > 0.0 else 0
	if _idle > 0 and _anim_time == 0.0:
		col = int(_idle_time * IDLE_FPS) % _idle
	if is_airborne():
		col = mini(2, _frames - 1)
	_sprite.frame = row * _frames + col
	if is_side_only:
		if facing.x < -0.05:
			_sprite.flip_h = true
		elif facing.x > 0.05:
			_sprite.flip_h = false
	else:
		_sprite.flip_h = row == 1 and facing.x < 0.0
