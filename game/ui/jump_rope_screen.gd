class_name JumpRopeScreen
extends Control
## The jump rope minigame (the Beanish kid in Castle Town): two Beanish
## swing a rope; press Z (or tap) to jump over it each time it comes round.
## It speeds up as you go; one miss ends the game.
##     var jumps := await jump_rope_screen.play()

signal _done(jumps: int)

const START_PERIOD := 1.3   # seconds for one swing of the rope
const MIN_PERIOD := 0.6
const SPEED_UP := 0.015     # each jump makes the swing this much faster

var _panel: PanelContainer
var _yard: Control
var _hint: Label
var _jumper: CharacterSprite
var _turners: Array[CharacterSprite] = []
var _playing := false
var _phase := 0.0           # 0..1 round the swing; the rope is at your feet at 0.5
var _period := START_PERIOD
var _jumps := 0
var _started := false


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(&"touch_blockers")
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"NavyPanel"
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_panel.add_child(box)
	_yard = Control.new()
	_yard.custom_minimum_size = Vector2(170, 80)
	_yard.clip_contents = true
	_yard.draw.connect(_draw_rope)
	box.add_child(_yard)
	for i in 2:
		var t := CharacterSprite.new()
		t.character_id = "bean_villager"
		t.position = Vector2(20 if i == 0 else 150, 70)
		t.facing = Vector2.RIGHT if i == 0 else Vector2.LEFT
		_yard.add_child(t)
		_turners.append(t)
	_jumper = CharacterSprite.new()
	_jumper.position = Vector2(85, 70)
	_yard.add_child(_jumper)
	_hint = Label.new()
	_hint.theme_type_variation = &"LightLabel"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_hint)


## Plays one game and returns how many jumps you made.
func play() -> int:
	_jumper.character_id = Game.player.get("character", "mario")
	_jumper.facing = Vector2.DOWN
	visible = true
	_jumps = 0
	_period = START_PERIOD
	_phase = 0.0
	_started = false
	_playing = true
	_hint.text = "Press Z to start, then jump the rope!"
	_center.call_deferred()
	var jumps: int = await _done
	await get_tree().create_timer(1.0).timeout
	visible = false
	return jumps


func _process(delta: float) -> void:
	if not _playing or not _started:
		_yard.queue_redraw()
		return
	var before := _phase
	_phase += delta / _period
	if before < 0.5 and _phase >= 0.5:  # the rope passes your feet
		if _jumper.is_airborne():
			_jumps += 1
			_period = maxf(MIN_PERIOD, _period - SPEED_UP * START_PERIOD)
			_hint.text = "Jumps: %d" % _jumps
		else:
			_playing = false
			_hint.text = "Tripped! %d jumps." % _jumps
			_done.emit(_jumps)
	if _phase >= 1.0:
		_phase -= 1.0
	_yard.queue_redraw()


## The rope: a curve between the two turners' hands that swings over the top
## (behind the jumper) and under their feet (in front).
func _draw_rope() -> void:
	var size := _yard.size
	_yard.draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.75, 0.4))
	var a := Vector2(28, 52)
	var b := Vector2(size.x - 28, 52)
	var sag := -cos(_phase * TAU) * 30.0  # -30 over the top, +30 at the feet (phase 0.5)
	var points := PackedVector2Array()
	for i in 17:
		var t := i / 16.0
		points.append(a.lerp(b, t) + Vector2(0, sag * sin(t * PI) * (0.6 if sag > 0 else 1.2)))
	_yard.draw_polyline(points, Color(0.95, 0.9, 0.3), 2.0)


func _press() -> void:
	if not _playing:
		return
	if not _started:
		_started = true
		_hint.text = "Jumps: 0"
		return
	_jumper.jump()


func _center() -> void:
	_panel.reset_size()
	_panel.position = ((get_viewport_rect().size - _panel.size) / 2.0).round()


func _gui_input(event: InputEvent) -> void:
	if Pointer.is_press(event):
		_press()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if _playing and event.is_action_pressed("action"):
		_press()
		get_viewport().set_input_as_handled()
