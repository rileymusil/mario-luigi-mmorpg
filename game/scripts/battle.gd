extends Node2D
## Turn-based battle prototype with Superstar Saga style timed hits.
##
## Your turn: press the brother's button to Jump. Press it again right as he
## lands on the enemy for a second stomp ("Good" / "Excellent").
## Enemy turn: the enemy charges a brother; press that brother's button so
## he is in the air when it arrives to dodge.

const EARLY_WINDOW := 0.15  # seconds before landing that still count
const LATE_WINDOW := 0.08   # seconds after landing that still count
const EXCELLENT_WINDOW := 0.06

@onready var bros := {"mario": $Mario as BroSprite, "luigi": $Luigi as BroSprite}
@onready var enemy: Sprite2D = $Enemy
@onready var message: Label = $UI/Message
@onready var status: Label = $UI/Status
@onready var enemy_status: Label = $UI/EnemyStatus
@onready var rating: Label = $UI/Rating

var enemy_data: Dictionary
var enemy_hp := 0
var _home := {}
var _enemy_anim := 0.0


func _ready() -> void:
	var type := Game.current_enemy_type if Game.current_enemy_type != "" else "goomba"
	enemy_data = Game.ENEMIES[type]
	enemy_hp = enemy_data["max_hp"]
	for id in bros:
		_home[id] = bros[id].position
		bros[id].facing = Vector2.RIGHT
	_home["enemy"] = enemy.position
	rating.text = ""
	_refresh()
	_run_battle()


func _process(delta: float) -> void:
	_enemy_anim += delta
	enemy.frame = int(_enemy_anim * 8.0) % enemy.hframes


func _run_battle() -> void:
	message.text = "A %s appeared!" % enemy_data["name"]
	await _wait(1.0)
	while true:
		for id in ["mario", "luigi"]:
			if Game.party[id]["hp"] <= 0:
				continue
			await _bro_turn(id)
			if enemy_hp <= 0:
				await _finish(true)
				return
		await _enemy_turn()
		if Game.party["mario"]["hp"] <= 0 and Game.party["luigi"]["hp"] <= 0:
			await _finish(false)
			return


# --- Player turn -----------------------------------------------------------

func _bro_turn(id: String) -> void:
	var bro: BroSprite = bros[id]
	var data: Dictionary = Game.party[id]
	var key := "Z" if id == "mario" else "X"
	message.text = "%s's turn! Press %s to Jump." % [data["name"], key]
	await _wait_for(data["button"])

	message.text = "Press %s just as %s lands!" % [key, data["name"]]
	var stand := enemy.position + Vector2(-34, 0)
	await _walk(bro, stand, 140.0)
	var top := enemy.position + Vector2(0, -16)
	var timing := await _arc(bro, bro.position, top, 48.0, 0.55, data["button"])
	_damage_enemy(data["pow"])
	var result := _rate(timing)
	_show_rating(result)
	if result != "Miss":
		var bonus := 1 if result == "Excellent" else 0
		await _arc(bro, top, top, 36.0, 0.45, "")
		_damage_enemy(data["pow"] + bonus)
	await _arc(bro, bro.position, stand, 28.0, 0.35, "")
	await _walk(bro, _home[id], 140.0)
	bro.facing = Vector2.RIGHT
	await _wait(0.3)


func _rate(timing: float) -> String:
	if timing >= -EXCELLENT_WINDOW and timing <= LATE_WINDOW * 0.5:
		return "Excellent"
	if timing >= -EARLY_WINDOW and timing <= LATE_WINDOW:
		return "Good"
	return "Miss"


func _damage_enemy(amount: int) -> void:
	var dmg := maxi(1, amount - int(enemy_data["def"]))
	enemy_hp = maxi(0, enemy_hp - dmg)
	_flash(enemy)
	_refresh()


# --- Enemy turn ------------------------------------------------------------

func _enemy_turn() -> void:
	var targets := ["mario", "luigi"].filter(func(id): return Game.party[id]["hp"] > 0)
	var id: String = targets.pick_random()
	var bro: BroSprite = bros[id]
	var data: Dictionary = Game.party[id]
	var key := "Z" if id == "mario" else "X"
	message.text = "%s charges at %s! Press %s to jump over it!" % [enemy_data["name"], data["name"], key]

	# Wind-up shake, then a dash. Whether the brother is airborne at contact
	# decides the dodge, so pressing too early or too late both fail.
	for i in 6:
		enemy.position.x = _home["enemy"].x + (2.0 if i % 2 == 0 else -2.0)
		await _wait(0.07)
	enemy.position = _home["enemy"]
	var dodged := false
	var start := enemy.position
	var contact := Vector2(bro.position.x + 6, bro.position.y)
	var t := 0.0
	var duration := randf_range(0.55, 0.85)
	while t < duration:
		await get_tree().process_frame
		t = minf(t + get_process_delta_time(), duration)
		enemy.position = start.lerp(contact, t / duration)
		if Input.is_action_just_pressed(data["button"]):
			bro.jump()
	dodged = bro.jump_height > 8.0

	if dodged:
		_show_rating("Dodged!")
		await _slide(enemy, contact + Vector2(-50, 0), 0.25)
	else:
		var dmg := maxi(1, int(enemy_data["pow"]) - int(data["def"]))
		data["hp"] = maxi(0, data["hp"] - dmg)
		_flash(bro)
		_show_rating("-%d" % dmg)
		_refresh()
		await _slide(enemy, contact + Vector2(20, 0), 0.15)
	await _wait(0.2)
	await _slide(enemy, _home["enemy"], 0.4)
	await _wait(0.3)


# --- Helpers ---------------------------------------------------------------

## Moves a node along a jump arc. If an action is given, returns when it was
## pressed relative to landing (negative = early), or INF if never pressed.
func _arc(node: Node2D, from: Vector2, to: Vector2, height: float, duration: float, action: String) -> float:
	var t := 0.0
	var pressed_at := -1.0
	while t < duration:
		await get_tree().process_frame
		t = minf(t + get_process_delta_time(), duration)
		var k := t / duration
		node.position = from.lerp(to, k) + Vector2(0, -4.0 * height * k * (1.0 - k))
		if action != "" and pressed_at < 0.0 and Input.is_action_just_pressed(action):
			pressed_at = t
	if action != "" and pressed_at < 0.0:
		var g := 0.0
		while g < LATE_WINDOW:
			await get_tree().process_frame
			g += get_process_delta_time()
			if Input.is_action_just_pressed(action):
				pressed_at = duration + g
				break
	return pressed_at - duration if pressed_at >= 0.0 else INF


func _walk(bro: BroSprite, target: Vector2, speed: float) -> void:
	while bro.position.distance_to(target) > 0.5:
		await get_tree().process_frame
		var delta := get_process_delta_time()
		var before := bro.position
		bro.position = bro.position.move_toward(target, speed * delta)
		bro.move_velocity = (bro.position - before) / maxf(delta, 0.0001)
	bro.position = target
	bro.move_velocity = Vector2.ZERO


func _slide(node: Node2D, target: Vector2, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(node, "position", target, duration)
	await tween.finished


func _flash(node: CanvasItem) -> void:
	var tween := create_tween()
	for i in 3:
		tween.tween_property(node, "modulate", Color(1, 0.3, 0.3), 0.06)
		tween.tween_property(node, "modulate", Color.WHITE, 0.06)


func _show_rating(text: String) -> void:
	rating.text = text
	rating.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(0.6)
	tween.tween_property(rating, "modulate:a", 0.0, 0.3)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _wait_for(action: String) -> void:
	while true:
		await get_tree().process_frame
		if Input.is_action_just_pressed(action):
			return


func _refresh() -> void:
	status.text = Game.hud_text()
	enemy_status.text = "%s  HP %d/%d" % [enemy_data["name"], enemy_hp, enemy_data["max_hp"]]


func _finish(won: bool) -> void:
	if won:
		message.text = "You won! +%d coins" % enemy_data["coins"]
		var tween := create_tween()
		tween.tween_property(enemy, "modulate:a", 0.0, 0.4)
	else:
		message.text = "The Bros. are down... Back to the start!"
	await _wait(1.8)
	Game.end_battle(won)
