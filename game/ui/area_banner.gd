class_name AreaBanner
extends PanelContainer
## The place-name strip from the save menu. show_name() drops it in from the
## top of the screen, holds it, then fades it out.

@onready var label: Label = $Label

var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0


func show_name(text: String, hold := 1.6) -> void:
	label.text = text
	size = Vector2.ZERO
	reset_size()
	size.x = maxf(size.x, 150.0)
	var vp := get_viewport_rect().size
	var rest := Vector2(roundf((vp.x - size.x) / 2.0), 30.0)
	position = rest - Vector2(0, 12)
	modulate.a = 0.0
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "position", rest, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 1.0, 0.2)
	_tween.chain().tween_interval(hold)
	_tween.chain().tween_property(self, "modulate:a", 0.0, 0.5)
