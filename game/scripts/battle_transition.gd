class_name BattleTransition
extends CanvasLayer
## Scene changes in and out of battles. Lives on the root while it plays so it
## survives the scene change, then frees itself.
##
## Into a battle (the Superstar Saga star swipe): the screen flashes, a star
## spins up out of the middle until it fills the screen, the battle loads behind
## it and the yellow fades away.
##     BattleTransition.into_battle(get_tree(), Game.BATTLE_SCENE)
## With at_once the battle loads right away and the swipe plays over a still
## of the screen it left, for battles that must be running straight away (a
## co-op guest, whose partner's battle sends its setup at once).
## Out of a battle: a quick fade to black and back.
##     BattleTransition.out_of_battle(get_tree(), func(): Game.end_battle("won"))

const FRAMES := preload("res://assets/battle/battle_start.png")
const FRAME_COUNT := 23
const COLUMNS := 6
const ROWS := 4
const FPS := 30.0
const STAR_YELLOW := Color8(240, 240, 0)
const SOURCE_SCREEN := Vector2(240, 160)  # the swipe was drawn for the GBA screen

static var _current: BattleTransition

var _cover: ColorRect
var _star: Sprite2D
var _still: TextureRect


static func into_battle(tree: SceneTree, scene: String, at_once := false) -> void:
	var t := _start(tree)
	if t:
		t._play_in(scene, at_once)
	else:
		tree.call_deferred("change_scene_to_file", scene)


static func out_of_battle(tree: SceneTree, change: Callable) -> void:
	var t := _start(tree)
	if t:
		t._play_out(change)
	else:
		change.call()


static func is_playing() -> bool:
	return is_instance_valid(_current)


static func _start(tree: SceneTree) -> BattleTransition:
	if is_playing():
		return null
	var t := BattleTransition.new()
	_current = t
	tree.root.add_child(t)
	return t


func _init() -> void:
	layer = 100  # over everything, the touch controls (90) too
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	var view := get_viewport().get_visible_rect().size
	_cover = ColorRect.new()
	_cover.size = view
	_cover.color = Color(1, 1, 1, 0)
	# Eats clicks and taps while it plays.
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_cover)
	_star = Sprite2D.new()
	_star.texture = FRAMES
	_star.hframes = COLUMNS
	_star.vframes = ROWS
	_star.position = view / 2.0
	_star.scale = Vector2.ONE * maxf(view.x / SOURCE_SCREEN.x, view.y / SOURCE_SCREEN.y)
	_star.visible = false
	add_child(_star)


func _play_in(scene: String, at_once: bool) -> void:
	if at_once:
		_freeze()
		await _change_scene(func(): get_tree().change_scene_to_file(scene))
	else:
		await get_tree().process_frame
	for i in 2:
		_cover.color = Color(1, 1, 1, 0.85)
		await _wait(0.05)
		_cover.color = Color(1, 1, 1, 0.0)
		await _wait(0.05)
	_star.visible = true
	for f in FRAME_COUNT:
		_star.frame = f
		await _wait(1.0 / FPS)
	_cover.color = STAR_YELLOW
	_star.visible = false
	if _still:
		_still.queue_free()
	if not at_once:
		await _change_scene(func(): get_tree().change_scene_to_file(scene))
	var tween := create_tween()
	tween.tween_property(_cover, "color:a", 0.0, 0.35)
	await tween.finished
	queue_free()


func _play_out(change: Callable) -> void:
	_cover.color = Color(0, 0, 0, 0)
	var tween := create_tween()
	tween.tween_property(_cover, "color:a", 1.0, 0.3)
	await tween.finished
	await _change_scene(change)
	tween = create_tween()
	tween.tween_property(_cover, "color:a", 0.0, 0.3)
	await tween.finished
	queue_free()


## Holds the last frame on screen (under the flash and the star).
func _freeze() -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return
	_still = TextureRect.new()
	_still.texture = ImageTexture.create_from_image(image)
	_still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_still.stretch_mode = TextureRect.STRETCH_SCALE
	_still.size = get_viewport().get_visible_rect().size
	_still.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_still)
	move_child(_still, 0)


## Runs `change` and waits until the new scene is in place (or a moment passes,
## if it didn't change the scene after all).
func _change_scene(change: Callable) -> void:
	var tree := get_tree()
	var old := tree.current_scene
	change.call()
	var waited := 0.0
	while (tree.current_scene == old or tree.current_scene == null) and waited < 3.0:
		await tree.process_frame
		waited += get_process_delta_time()
	await tree.process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout
