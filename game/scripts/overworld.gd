extends Node2D
## Overworld root: builds the field's walls and keeps the HUD up to date.

@onready var ground: Node2D = $Ground
@onready var hud: Label = $HUD/Status
@onready var camera: Camera2D = $Actors/Mario/Camera2D


func _ready() -> void:
	var world: Vector2 = ground.size
	camera.limit_right = int(world.x)
	camera.limit_bottom = int(world.y)
	_add_wall(Rect2(-16, -16, world.x + 32, 24))
	_add_wall(Rect2(-16, world.y - 8, world.x + 32, 24))
	_add_wall(Rect2(-16, -16, 24, world.y + 32))
	_add_wall(Rect2(world.x - 8, -16, 24, world.y + 32))


func _process(_delta: float) -> void:
	hud.text = Game.hud_text()


func _add_wall(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.get_center()
	body.add_child(shape)
	add_child(body)
