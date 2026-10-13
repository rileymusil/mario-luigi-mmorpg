class_name DialogueBox
extends Control
## Superstar Saga speech balloon: the text types in letter by letter, a blue
## arrow bobs when it is done, the speaker's name sits on a tab and a tail
## points at whoever is talking.
##     await dialogue.say("Hello!", "Toad", toad_node)   # waits for Z / X / a click or tap
##     dialogue.open("Join us?", "Toad", toad_node)      # stays up, e.g. under a menu
##     dialogue.close()
## Clicking or tapping works like Z: anywhere while say() waits, and on the
## balloon itself (to show the rest of the text) when it sits under a menu.

signal typed

const CHARS_PER_SECOND := 50.0
const MARGIN := 16.0
const LINES := 3

var typing := false
var _anchor: Node2D
var _shown := 0.0
var _time := 0.0
var _at_top := false
var _waiting := false  # say() is waiting for Z / X / a click
var _clicked := false

@onready var box: PanelContainer = $Box
@onready var text_label: Label = $Box/Text
@onready var tail: TextureRect = $Tail
@onready var name_tag: PanelContainer = $Name
@onready var name_label: Label = $Name/Label
@onready var next_arrow: TextureRect = $Next


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The name tab is a slimmer balloon than the theme's default.
	var sb := box.get_theme_stylebox("panel").duplicate() as StyleBox
	sb.content_margin_top = 2
	sb.content_margin_bottom = 1
	name_tag.add_theme_stylebox_override("panel", sb)
	# The touch screen buttons step aside while a balloon is up.
	add_to_group(&"touch_blockers")
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.gui_input.connect(_on_box_input)
	visible = false


## Shows the balloon and starts typing; returns right away.
## anchor: the speaker in the world (the tail points at it), or null.
func open(text: String, speaker := "", anchor: Node2D = null) -> void:
	_anchor = anchor
	text_label.text = text
	text_label.visible_characters = 0
	_shown = 0.0
	typing = true
	name_label.text = speaker
	name_tag.visible = speaker != ""
	next_arrow.visible = false
	var vp := get_viewport_rect().size
	var line_h := text_label.get_line_height()
	box.size = Vector2(vp.x - MARGIN * 2, 0)
	text_label.custom_minimum_size = Vector2(box.size.x - 16, line_h * LINES)
	box.reset_size()
	box.size.x = vp.x - MARGIN * 2
	# Sit at the bottom unless the speaker stands in the lower part of the screen.
	_at_top = anchor != null and _screen_pos(anchor).y > vp.y * 0.62
	box.position = Vector2(MARGIN, 14.0 if _at_top else vp.y - box.size.y - 6.0)
	name_tag.reset_size()
	name_tag.position = Vector2(box.position.x + 10, box.position.y - name_tag.size.y + 5)
	_place_tail()
	visible = true


## Shows the text, waits for Z or X (or a click or tap), then closes.
## Pressing while it is still typing shows the rest at once.
func say(text: String, speaker := "", anchor: Node2D = null) -> void:
	open(text, speaker, anchor)
	_clicked = false
	await get_tree().process_frame
	_waiting = true
	while true:
		await get_tree().process_frame
		if Input.is_action_just_pressed("action") or Input.is_action_just_pressed("talk") or _clicked:
			_clicked = false
			if typing:
				skip()
			else:
				break
	_waiting = false
	close()


func skip() -> void:
	_shown = text_label.get_total_character_count()


func wait_typed() -> void:
	if typing:
		await typed


func close() -> void:
	visible = false
	typing = false
	_anchor = null


## While say() waits, a click or tap anywhere reads on (no menu is open then).
func _input(event: InputEvent) -> void:
	if _waiting and visible and Pointer.is_press(event):
		_clicked = true
		get_viewport().set_input_as_handled()


func _on_box_input(event: InputEvent) -> void:
	# Under a menu (open()), clicking the balloon only finishes the typing; it
	# doesn't count as clicking outside the menu.
	if Pointer.is_press(event) and typing:
		skip()


func _screen_pos(node: Node2D) -> Vector2:
	return node.get_global_transform_with_canvas().origin


func _place_tail() -> void:
	tail.visible = _anchor != null and is_instance_valid(_anchor)
	if not tail.visible:
		return
	var tip := _screen_pos(_anchor)
	var h := tail.size.y
	if _at_top:
		# Tail hangs from the bottom edge, pointing down at the speaker's head.
		tail.flip_v = false
		tail.position.y = box.position.y + box.size.y - 2.0
	else:
		# Tail rises from the top edge toward the speaker.
		tail.flip_v = true
		tail.position.y = box.position.y - h + 2.0
	tail.position.x = clampf(tip.x - 2.0, box.position.x + 4.0, box.position.x + box.size.x - tail.size.x - 8.0)


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	if typing:
		_shown += CHARS_PER_SECOND * delta
		var total := text_label.get_total_character_count()
		text_label.visible_characters = mini(int(_shown), total)
		if _shown >= total:
			text_label.visible_characters = -1
			typing = false
			typed.emit()
	next_arrow.visible = not typing
	if next_arrow.visible:
		next_arrow.position = box.position + box.size - Vector2(18, 13 + absf(sin(_time * 6.0)) * 3.0)
	if _anchor != null and is_instance_valid(_anchor):
		_place_tail()
