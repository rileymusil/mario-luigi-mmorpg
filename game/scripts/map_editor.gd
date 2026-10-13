class_name MapEditor
extends Node2D
## Debug-only map editor, opened with F2 on any world map. Not in release
## builds (the published web game), unless started with `-- --map-editor`.
##
## Shows the walk mask tinted red (red = blocked ground) and every prop as a
## green box with its base line (pink) and footprint (orange).
##   1 / 2      paint walkable / blocked ground (left mouse; right mouse paints the opposite)
##   [ ]        brush size
##   3          props: click to select, drag to move; drag a corner square to
##              resize, the pink line to move the base line, the orange box to
##              move the footprint (its corner square resizes it)
##   N          new prop at the mouse      Del / Backspace  delete the selected prop
##   C          copy the selected prop     T  tree / rectangle shape    F  add / remove footprint
##   Arrows / WASD pan, mouse wheel zoom, Ctrl+S save, F2 close.
## Saving writes <map>_mask.png and <map>_props.json into res://assets/maps/
## when running from the Godot editor, otherwise into user://maps/.

enum Mode { WALK, BLOCK, PROPS }

const PAN_SPEED := 300.0
const OVERLAY_SHADER := """
shader_type canvas_item;
void fragment() {
	float walk = texture(TEXTURE, UV).r;
	COLOR = vec4(1.0, 0.1, 0.1, walk < 0.5 ? 0.45 : 0.0);
}
"""

var world  # the World node (world.gd)
var is_open := false
var mode := Mode.PROPS
var brush := 6
var selected: MapProps.Prop
var unsaved := false

var _drag := ""             # what the mouse is dragging: paint, move, tl, br, base, foot, foot_br
var _drag_from := Vector2.ZERO
var _orig := {}
var _paint_value := true
var _last_paint := Vector2.ZERO
var _overlay: Sprite2D
var _overlay_tex: ImageTexture
var _overlay_dirty := false
var _layer: CanvasLayer
var _status: Label
var _message := ""
var _saved_zoom := Vector2.ONE


static func available() -> bool:
	return OS.is_debug_build() or "--map-editor" in OS.get_cmdline_user_args()


func _ready() -> void:
	world = get_parent()
	z_index = 100
	visible = false
	_overlay = Sprite2D.new()
	_overlay.centered = false
	_overlay.z_index = -1
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = OVERLAY_SHADER
	_overlay.material = mat
	add_child(_overlay)
	_layer = CanvasLayer.new()
	_layer.layer = 50
	_layer.visible = false
	add_child(_layer)
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.55)
	panel.position = Vector2(0, 18)
	panel.size = Vector2(384, 56)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(panel)
	_status = Label.new()
	_status.position = Vector2(4, 18)
	_status.size = Vector2(376, 56)
	_status.add_theme_font_size_override("font_size", 8)
	_status.add_theme_color_override("font_color", Color(1, 1, 0.8))
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 3)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_status)


func toggle() -> void:
	is_open = not is_open
	visible = is_open
	_layer.visible = is_open
	world.editing = is_open
	var cam: Camera2D = world.camera
	if is_open:
		_saved_zoom = cam.zoom
		_overlay_tex = ImageTexture.create_from_image(world.mask)
		_overlay.texture = _overlay_tex
		_message = ""
	else:
		cam.zoom = _saved_zoom
		cam.position = world.player.position
		_drag = ""
	queue_redraw()


# --- Input -----------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_key(event)
	elif event is InputEventMouseButton:
		_mouse_button(event)
	elif event is InputEventMouseMotion and _drag != "":
		_mouse_drag()
	else:
		return
	get_viewport().set_input_as_handled()


func _key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_1:
			mode = Mode.WALK
		KEY_2:
			mode = Mode.BLOCK
		KEY_3:
			mode = Mode.PROPS
		KEY_BRACKETLEFT:
			brush = maxi(1, brush - 1)
		KEY_BRACKETRIGHT:
			brush = mini(40, brush + 1)
		KEY_S:
			if event.ctrl_pressed or event.meta_pressed:
				save()
		KEY_N:
			_new_prop(get_global_mouse_position())
		KEY_C:
			if selected:
				var d := selected.to_dict()
				var p := MapProps.prop_from_dict(d)
				p.rect.position += Vector2i(16, 16)
				p.base += 16
				p.foot.position += Vector2i(16, 16)
				_add(p)
		KEY_DELETE, KEY_BACKSPACE:
			if selected:
				world.props.remove(selected)
				selected = null
				_changed()
		KEY_T:
			if selected:
				selected.shape = "rect" if selected.shape == "tree" else "tree"
				_changed()
		KEY_F:
			if selected:
				if selected.has_foot():
					selected.foot = Rect2i()
				else:
					selected.foot = Rect2i(selected.rect.get_center().x - 6, selected.base - 8, 12, 8)
				_changed()
	queue_redraw()


func _mouse_button(event: InputEventMouseButton) -> void:
	var cam: Camera2D = world.camera
	if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		cam.zoom = (cam.zoom * 1.25).clamp(Vector2(0.25, 0.25), Vector2(4, 4))
		return
	if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		cam.zoom = (cam.zoom / 1.25).clamp(Vector2(0.25, 0.25), Vector2(4, 4))
		return
	var pt := get_global_mouse_position()
	if not event.pressed:
		if _drag == "paint":
			world.rebuild_collision()
		elif _drag != "":
			_changed()
		_drag = ""
		return
	if mode != Mode.PROPS:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_paint_value = (mode == Mode.WALK) == (event.button_index == MOUSE_BUTTON_LEFT)
			_drag = "paint"
			_last_paint = pt
			_paint_line(pt, pt)
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	_drag = _handle_at(pt) if selected else ""
	if _drag == "":
		selected = world.props.prop_at(pt)
		_drag = "move" if selected else ""
	if selected:
		_drag_from = pt
		_orig = {"rect": selected.rect, "base": selected.base, "foot": selected.foot}
	queue_redraw()


func _mouse_drag() -> void:
	var pt := get_global_mouse_position()
	if _drag == "paint":
		_paint_line(_last_paint, pt)
		_last_paint = pt
		return
	if selected == null:
		return
	var d := Vector2i((pt - _drag_from).round())
	var r: Rect2i = _orig["rect"]
	var f: Rect2i = _orig["foot"]
	match _drag:
		"move":
			selected.rect = Rect2i(r.position + d, r.size)
			selected.base = _orig["base"] + d.y
			if selected.has_foot():
				selected.foot = Rect2i(f.position + d, f.size)
		"tl":
			var tl := r.position + d
			selected.rect = Rect2i(tl, (r.end - tl).max(Vector2i(4, 4)))
		"br":
			selected.rect = Rect2i(r.position, (r.size + d).max(Vector2i(4, 4)))
		"base":
			selected.base = _orig["base"] + d.y
		"foot":
			selected.foot = Rect2i(f.position + d, f.size)
		"foot_br":
			selected.foot = Rect2i(f.position, (f.size + d).max(Vector2i(2, 2)))
	world.props.refresh(selected)
	queue_redraw()


## Which part of the selected prop is under the mouse.
func _handle_at(pt: Vector2) -> String:
	var tol: float = 4.0 / world.camera.zoom.x
	var p := selected
	var r := Rect2(p.rect)
	if pt.distance_to(r.end) <= tol:
		return "br"
	if pt.distance_to(r.position) <= tol:
		return "tl"
	if p.has_foot():
		var f := Rect2(p.foot)
		if pt.distance_to(f.end) <= tol:
			return "foot_br"
		if f.has_point(pt):
			return "foot"
	if absf(pt.y - p.base) <= tol and pt.x >= r.position.x - tol and pt.x <= r.end.x + tol:
		return "base"
	if r.has_point(pt):
		return "move"
	return ""


func _new_prop(at: Vector2) -> void:
	var p := MapProps.Prop.new()
	var c := Vector2i(at.round())
	p.name = "tree"
	p.shape = "tree"
	p.rect = Rect2i(c.x - 25, c.y - 60, 51, 72)
	p.base = c.y + 11
	p.foot = Rect2i(c.x - 6, c.y + 4, 12, 7)
	_add(p)


func _add(p: MapProps.Prop) -> void:
	world.props.list.append(p)
	world.props.refresh(p)
	selected = p
	_changed()


func _changed() -> void:
	unsaved = true
	if selected:
		world.props.refresh(selected)
	world.rebuild_collision()
	queue_redraw()


# --- Painting the mask -----------------------------------------------------------

func _paint_line(a: Vector2, b: Vector2) -> void:
	var steps := maxi(1, int(a.distance_to(b)))
	var col := Color.WHITE if _paint_value else Color.BLACK
	var img: Image = world.mask
	var size := img.get_size()
	for i in steps + 1:
		var c := a.lerp(b, float(i) / steps)
		for y in range(int(c.y) - brush, int(c.y) + brush + 1):
			for x in range(int(c.x) - brush, int(c.x) + brush + 1):
				if x >= 0 and y >= 0 and x < size.x and y < size.y and Vector2(x, y).distance_to(c) <= brush:
					img.set_pixel(x, y, col)
					world.solid.set_pixel(x, y, col)
	unsaved = true
	_overlay_dirty = true


func save() -> void:
	var mask_path := MapProps.save_path(world.map_id, "_mask.png")
	var err: Error = world.mask.save_png(mask_path)
	var props_path: String = world.props.save_props()
	if err == OK and props_path != "":
		unsaved = false
		_message = "Saved " + mask_path.get_file() + " and " + props_path.get_file()
		print("Map editor saved ", mask_path, " and ", props_path)
	else:
		_message = "Save failed (%s)" % error_string(err)


# --- Every frame -----------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_open:
		return
	var cam: Camera2D = world.camera
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir != Vector2.ZERO:
		cam.position = (cam.position + dir * PAN_SPEED * delta / cam.zoom.x).clamp(Vector2.ZERO, world.map_size)
	if _overlay_dirty:
		_overlay_tex.update(world.mask)
		_overlay_dirty = false
	var lines := ["MAP EDITOR  %s  [%s]%s" % [world.map_id, ["walk paint", "block paint", "props"][mode], "  *unsaved*" if unsaved else ""],
		"1 walk  2 block  3 props   [ ] brush %d   wheel zoom   Ctrl+S save   F2 close" % brush,
		"N new  C copy  Del delete  T shape  F footprint"]
	if selected:
		lines.append("%s (%s) rect %s base %d foot %s" % [selected.name, selected.shape, selected.rect, selected.base,
			selected.foot if selected.has_foot() else "none"])
	if _message != "":
		lines.append(_message)
	_status.text = "\n".join(lines)
	queue_redraw()


func _draw() -> void:
	if not is_open:
		return
	for p in world.props.list:
		var col := Color(1, 1, 0.2) if p == selected else Color(0.2, 1, 0.3)
		draw_rect(Rect2(p.rect), col, false, -1.0)
		draw_line(Vector2(p.rect.position.x, p.base), Vector2(p.rect.end.x, p.base), Color(1, 0.3, 1), -1.0)
		if p.has_foot():
			draw_rect(Rect2(p.foot), Color(1, 0.55, 0, 0.45))
			draw_rect(Rect2(p.foot), Color(1, 0.55, 0), false, -1.0)
	if selected:
		var h: float = 3.0 / world.camera.zoom.x
		for c in [Vector2(selected.rect.position), Vector2(selected.rect.end)] + ([Vector2(selected.foot.end)] if selected.has_foot() else []):
			draw_rect(Rect2(c - Vector2(h, h), Vector2(h, h) * 2), Color(1, 1, 0.2))
		draw_polyline(selected.polygon + PackedVector2Array([selected.polygon[0]]), Color(0.4, 0.9, 1), -1.0)
	if mode != Mode.PROPS:
		draw_arc(get_global_mouse_position(), brush, 0, TAU, 24, Color.WHITE if mode == Mode.WALK else Color.RED, -1.0)
