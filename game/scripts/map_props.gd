class_name MapProps
extends RefCounted
## Tall things on a map (trees, buildings, posts, statues) and the walk mask
## they stand on. Each prop is a piece of the map picture redrawn on top of
## the characters: it sits in the y-sorted Actors node at its base line (where
## trunk or wall meets the ground), so anyone whose feet are above that line
## is drawn behind it. Only its small footprint blocks walking; the ground
## behind it stays walkable. Data: res://assets/maps/<id>_props.json, edited
## with the in-game map editor (map_editor.gd) or by hand.
##
## A prop in the JSON file:
##   {"name": "tree", "shape": "tree", "rect": [x, y, w, h], "base": y, "foot": [x, y, w, h]}
## shape "rect" redraws the whole rectangle; "tree" a rounded canopy over the
## top of the rectangle plus a trunk strip down to the base line. "foot" is
## optional. "poly" (with "poly_for") is an outline traced round the prop's art,
## used instead of the shape while the rect keeps its size. Any other keys (like
## "fill", used by tools/make_maps.py) are kept.

const HIDDEN_ALPHA := 0.5
const FADE_SPEED := 6.0

class Prop:
	var name := ""
	var shape := "rect"
	var rect := Rect2i()
	var base := 0
	var foot := Rect2i()   # zero size = nothing blocked
	var extra := {}        # keys we don't use, kept when saving
	var node: Polygon2D
	var polygon := PackedVector2Array()  # in map pixels

	func has_foot() -> bool:
		return foot.size.x > 0 and foot.size.y > 0

	func to_dict() -> Dictionary:
		var d := {"name": name, "shape": shape,
			"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "base": base}
		if has_foot():
			d["foot"] = [foot.position.x, foot.position.y, foot.size.x, foot.size.y]
		for k in extra:
			d[k] = extra[k]
		return d

var map_id := ""
var list: Array[Prop] = []
var _parent: Node2D
var _texture: Texture2D


# --- Files -----------------------------------------------------------------------

static func res_path(map_id_: String, suffix: String) -> String:
	return "res://assets/maps/%s%s" % [map_id_, suffix]


## Where the map editor saves: straight into the project when running from the
## Godot editor (or `godot --path game`), otherwise to user://maps/.
static func save_path(map_id_: String, suffix: String) -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path(res_path(map_id_, suffix))
	DirAccess.make_dir_recursive_absolute("user://maps")
	return "user://maps/%s%s" % [map_id_, suffix]


static func _user_override(map_id_: String, suffix: String) -> String:
	var p := "user://maps/%s%s" % [map_id_, suffix]
	return p if OS.is_debug_build() and not OS.has_feature("editor") and FileAccess.file_exists(p) else ""


## The walk mask (white = ground you can walk on).
static func load_mask(map_id_: String) -> Image:
	return _load_layer(map_id_, "_mask.png")


## The height layer, <map>_height.png (see world.gd, "Height"): how high the
## ground is, as grey levels. Black is the lowest ground (level 0), each
## LEVEL_STEP brighter is one level up, and white (FACE) is a ledge face: the
## drawn side of raised ground, which you can jump up (if it is low enough) or
## drop down. A map without the file is flat. Always an L8 image of `size`.
const LEVEL_STEP := 50
const MAX_LEVEL := 4
const FACE := 255

static func load_height(map_id_: String, size: Vector2i) -> Image:
	var img: Image = null
	var path := res_path(map_id_, "_height.png")
	if ResourceLoader.exists(path) or FileAccess.file_exists(path) or _user_override(map_id_, "_height.png") != "":
		img = _load_layer(map_id_, "_height.png")
	if img == null or img.is_empty() or img.get_size() != size:
		return Image.create(size.x, size.y, false, Image.FORMAT_L8)
	if img.get_format() != Image.FORMAT_L8:
		img.convert(Image.FORMAT_L8)
	return img


## Grey value of a height level (0..MAX_LEVEL) in the height layer.
static func level_value(level: int) -> int:
	return clampi(level, 0, MAX_LEVEL) * LEVEL_STEP


## Level stored at a grey value, or -1 for a ledge face.
static func value_level(v: int) -> int:
	return -1 if v > MAX_LEVEL * LEVEL_STEP + LEVEL_STEP / 2 else (v + LEVEL_STEP / 2) / LEVEL_STEP


static func _load_layer(map_id_: String, suffix: String) -> Image:
	var override := _user_override(map_id_, suffix)
	if override != "":
		return Image.load_from_file(override)
	var path := res_path(map_id_, suffix)
	if OS.has_feature("editor"):
		# Read the PNG itself, so a layer saved by the map editor is used even
		# before Godot re-imports it.
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null and not img.is_empty():
			return img
	return (load(path) as Texture2D).get_image()


func load_props(id: String) -> void:
	map_id = id
	list.clear()
	var path := _user_override(id, "_props.json")
	if path == "":
		path = res_path(id, "_props.json")
	if not FileAccess.file_exists(path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Bad props file: " + path)
		return
	for d in data.get("props", []):
		list.append(prop_from_dict(d))


static func prop_from_dict(d: Dictionary) -> Prop:
	var p := Prop.new()
	p.name = str(d.get("name", ""))
	p.shape = str(d.get("shape", "rect"))
	var r: Array = d["rect"]
	p.rect = Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
	p.base = int(d.get("base", p.rect.end.y))
	if d.has("foot"):
		var f: Array = d["foot"]
		p.foot = Rect2i(int(f[0]), int(f[1]), int(f[2]), int(f[3]))
	for k in d:
		if not k in ["name", "shape", "rect", "base", "foot"]:
			p.extra[k] = d[k]
	return p


## One prop per line, so changes read well in git.
func to_json() -> String:
	var lines := PackedStringArray()
	for p in list:
		lines.append(JSON.stringify(p.to_dict(), "", false))
	return "{\"props\": [\n" + ",\n".join(lines) + "\n]}\n"


func save_props() -> String:
	var path := save_path(map_id, "_props.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(to_json())
	return path


# --- Drawing -------------------------------------------------------------------

func build(parent: Node2D, texture: Texture2D) -> void:
	_parent = parent
	_texture = texture
	for p in list:
		refresh(p)


## (Re)creates the node that draws prop `p`; call after changing it.
func refresh(p: Prop) -> void:
	if _parent == null:
		return
	if p.node == null:
		p.node = Polygon2D.new()
		p.node.texture = _texture
		_parent.add_child(p.node)
	p.polygon = outline(p)
	p.node.position = Vector2(p.rect.position.x, p.base)
	var local := PackedVector2Array()
	for v in p.polygon:
		local.append(v - p.node.position)
	p.node.polygon = local
	p.node.uv = p.polygon  # texture pixels: the same spot of the map picture


func remove(p: Prop) -> void:
	if p.node:
		p.node.queue_free()
	list.erase(p)


## The outline drawn for a prop, in map pixels: the one traced round its art
## ("poly", see tools/make_maps.py --outlines) while its rect keeps the size it
## was traced for, otherwise the default shape below.
static func outline(p: Prop) -> PackedVector2Array:
	var r := Rect2(p.rect)
	var traced: Array = p.extra.get("poly", [])
	var traced_for: Array = p.extra.get("poly_for", [])
	if traced.size() >= 3 and traced_for.size() == 2 and Vector2i(int(traced_for[0]), int(traced_for[1])) == p.rect.size:
		var pts := PackedVector2Array()
		for v in traced:
			pts.append(r.position + Vector2(float(v[0]), float(v[1])))
		if not Geometry2D.triangulate_polygon(pts).is_empty():
			return pts
	if p.shape != "tree" or r.size.x < 4 or r.size.y < 4:
		return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	# Canopy: a superellipse over the top of the rectangle (rounder than a box,
	# fuller than an ellipse, so leaves aren't clipped).
	var canopy_h := r.size.y * 0.72
	var c := Vector2(r.get_center().x, r.position.y + canopy_h / 2.0)
	var a := r.size.x / 2.0
	var b := canopy_h / 2.0
	var canopy := PackedVector2Array()
	for i in 32:
		var t := TAU * i / 32.0
		var ct := cos(t)
		var st := sin(t)
		canopy.append(c + Vector2(a * signf(ct) * pow(absf(ct), 0.8), b * signf(st) * pow(absf(st), 0.8)))
	# Trunk: from the middle of the canopy down to the bottom of the rectangle.
	var fx := float(p.foot.get_center().x) if p.has_foot() else c.x
	var half := maxf(p.foot.size.x / 2.0 + 3.0, 6.0) if p.has_foot() else 6.0
	var trunk := PackedVector2Array([Vector2(fx - half, c.y), Vector2(fx + half, c.y),
		Vector2(fx + half, r.end.y), Vector2(fx - half, r.end.y)])
	var best := canopy
	var best_area := 0.0
	for m in Geometry2D.merge_polygons(canopy, trunk):
		var area := absf(_area(m))
		if area > best_area:
			best = m
			best_area = area
	return best


static func _area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		s += poly[i].cross(poly[(i + 1) % poly.size()])
	return s / 2.0


# --- Collision and fading --------------------------------------------------------

## Paints every footprint black into `img` (a copy of the walk mask).
func paint_feet(img: Image) -> void:
	for p in list:
		if p.has_foot():
			img.fill_rect(p.foot, Color.BLACK)


## Fades props that are drawn over characters (feet above their base line).
## Accepts a single CharacterSprite or an Array of CharacterSprites.
func update_fade(actors, delta: float) -> void:
	var list_to_check: Array = []
	if actors is Array:
		list_to_check = actors
	elif actors != null:
		list_to_check = [actors]

	for p in list:
		if p.node == null:
			continue
		var hides := false
		for who in list_to_check:
			if who == null or not is_instance_valid(who):
				continue
			var feet: Vector2 = who.position
			var h: float = who.height()
			if feet.y < p.base and feet.x > p.rect.position.x - 14 and feet.x < p.rect.end.x + 14 \
					and feet.y >= p.rect.position.y - 14 and feet.y - h < p.rect.end.y:
				var char_box := Rect2(feet.x - 10.0, feet.y - h, 20.0, h)
				if Rect2(p.rect).intersects(char_box):
					if p.shape != "tree":
						hides = true
					else:
						for fy in [0.0, 0.25, 0.5, 0.85]:
							for fx in [-0.3, 0.0, 0.3]:
								var q := feet + Vector2(fx * h, -fy * h)
								if Geometry2D.is_point_in_polygon(q, p.polygon):
									hides = true
									break
							if hides:
								break
			if hides:
				break
		var target := HIDDEN_ALPHA if hides else 1.0
		p.node.modulate.a = move_toward(p.node.modulate.a, target, FADE_SPEED * delta)


## The prop drawn in front at map point `pt` (largest base line), or null.
func prop_at(pt: Vector2) -> Prop:
	var best: Prop = null
	for p in list:
		if Rect2(p.rect).grow(1).has_point(pt) and (best == null or p.base > best.base):
			best = p
	return best
