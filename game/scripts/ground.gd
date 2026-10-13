@tool
extends Node2D
## Placeholder field: checkered grass with a darker border and some flowers.
## Swap for a TileMapLayer built from the Superstar Saga map art later.

@export var size := Vector2(640, 480):
	set(value):
		size = value
		queue_redraw()
@export var tile := 16


func _draw() -> void:
	var a := Color("6cc04a")
	var b := Color("62b443")
	for y in int(size.y / tile):
		for x in int(size.x / tile):
			draw_rect(Rect2(x * tile, y * tile, tile, tile), a if (x + y) % 2 == 0 else b)
	draw_rect(Rect2(Vector2.ZERO, size), Color("3d7a2a"), false, 6.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 40:
		var p := Vector2(rng.randf_range(16, size.x - 16), rng.randf_range(16, size.y - 16))
		var c: Color = [Color.WHITE, Color("ffd84a"), Color("ff7aa8")][i % 3]
		draw_circle(p, 2.0, c)
		draw_circle(p, 0.8, Color("ffb000"))
