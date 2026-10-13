@tool
class_name GoldNumber
extends Control
## A number drawn with the gold digits from the Superstar Saga save menu.

const DIGITS := preload("res://assets/ui/gold_digits.png")
const CELL := Vector2(8, 13)

@export var value := 0:
	set(v):
		value = maxi(v, 0)
		_resize()
## Pads with leading zeros up to this many digits.
@export var min_digits := 1:
	set(v):
		min_digits = maxi(v, 1)
		_resize()


func _ready() -> void:
	_resize()


func _text() -> String:
	return str(value).pad_zeros(min_digits)


func _resize() -> void:
	custom_minimum_size = Vector2(CELL.x * _text().length(), CELL.y)
	update_minimum_size()
	queue_redraw()


func _draw() -> void:
	var x := 0.0
	var top := floorf((size.y - CELL.y) / 2.0)
	for ch in _text():
		var d := ch.unicode_at(0) - 48
		draw_texture_rect_region(DIGITS, Rect2(Vector2(x, top), CELL), Rect2(Vector2(d * CELL.x, 0), CELL))
		x += CELL.x
