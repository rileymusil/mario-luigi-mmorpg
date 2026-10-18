class_name Dungeon
extends Node
## The Teehee Ruins' puzzles: pieces a map lists in Game.MAPS[map]["puzzle"]
## stand in the room (sprites cut by tools/make_dungeon.py) and you work them
## with the talk key (X, or B on touch):
##   rock    smash it with your hammer to clear the way
##   switch  hit it to flip the gates it names ("toggles"), open <-> shut
##   gate    planks barring a way; only switches move them
##   block   a ? block: hit it for a Ruins Key
##   lock    a stone face that sinks away for a Ruins Key
##   prize   the big block at the end (Game.claim_ruins_prize)
## Rocks, gates, locks and the blocks themselves are solid (paint) while they
## stand. What you have done stays put until you walk back in from the valley
## (Game.puzzle_state, not saved: the ruins are fresh for each run).

const REACH := 26.0
const FOOT_DEPTH := 10
const TEX := {
	"rock": preload("res://assets/dungeon/rock.png"),
	"switch": preload("res://assets/dungeon/switch.png"),
	"gate": preload("res://assets/dungeon/gate.png"),
	"lock": preload("res://assets/dungeon/lock.png"),
	"block": preload("res://assets/dungeon/block.png"),
	"prize": preload("res://assets/dungeon/prize.png"),
}
const FRAMES := {"rock": 5, "switch": 2, "block": 2}
const VERBS := {"rock": "Smash", "switch": "Hit", "block": "Hit", "lock": "Open", "prize": "Open"}

var world: Node
var map_id := ""
var pieces: Array = []  # [{def, node: Sprite2D}]


func setup(w: Node, id: String, defs: Array) -> void:
	world = w
	map_id = id
	var state := _state()
	for d in defs:
		if not state.has(d["id"]):
			state[d["id"]] = d.get("open", false)
		var s := Sprite2D.new()
		s.texture = TEX[d["kind"]]
		s.hframes = FRAMES.get(d["kind"], 1)
		s.centered = false
		var size := Vector2(s.texture.get_width() / s.hframes, s.texture.get_height())
		s.offset = Vector2(-size.x / 2.0, -size.y).round()
		s.position = d["pos"]
		world.actors.add_child(s)
		var p := {"def": d, "node": s, "size": size}
		pieces.append(p)
		_show(p, false)


## This map's puzzle state: piece id -> done (rock broken, switch on, gate
## open, block hit, lock open, prize taken).
func _state() -> Dictionary:
	if not Game.puzzle_state.has(map_id):
		Game.puzzle_state[map_id] = {}
	return Game.puzzle_state[map_id]


func done(p: Dictionary) -> bool:
	return _state().get(p["def"]["id"], false)


func _show(p: Dictionary, animate: bool) -> void:
	var s: Sprite2D = p["node"]
	var kind: String = p["def"]["kind"]
	var on := done(p)
	match kind:
		"switch", "block":
			s.frame = 1 if on else 0
		"rock", "gate", "lock":
			if not animate:
				s.visible = not on
				s.modulate.a = 1.0
				s.frame = 0 if s.hframes > 1 else s.frame
			elif on:
				var t := s.create_tween()
				if kind == "rock":
					for f in range(1, 5):
						t.tween_callback(s.set_frame.bind(f))
						t.tween_interval(0.06)
				t.tween_property(s, "modulate:a", 0.0, 0.25)
				t.tween_callback(s.hide)
			else:
				s.visible = true
				s.modulate.a = 0.0
				s.create_tween().tween_property(s, "modulate:a", 1.0, 0.2)


func solid(p: Dictionary) -> bool:
	match p["def"]["kind"]:
		"rock", "gate", "lock":
			return not done(p)
	return true  # switches, blocks and the prize always stand


## The ground under each standing piece, blocked in `img` (the world's solid layer).
func paint(img: Image) -> void:
	for p in pieces:
		if solid(p):
			img.fill_rect(foot(p).intersection(Rect2i(Vector2i.ZERO, img.get_size())), Color.BLACK)


func foot(p: Dictionary) -> Rect2i:
	var w := int(p["size"].x) + (4 if p["def"]["kind"] == "gate" else -4)
	var pos: Vector2 = p["def"]["pos"]
	return Rect2i(int(pos.x) - w / 2, int(pos.y) - FOOT_DEPTH, w, FOOT_DEPTH)


## The piece you are next to that the talk key works, or {}.
func nearest(from: Vector2) -> Dictionary:
	var best := {}
	var best_d := REACH
	for p in pieces:
		if not VERBS.has(p["def"]["kind"]) or (p["def"]["kind"] in ["rock", "lock"] and done(p)):
			continue
		var r := Rect2(foot(p))
		var d := from.distance_to(from.clamp(r.position, r.end))
		if d < best_d:
			best = p
			best_d = d
	return best


func verb(p: Dictionary) -> String:
	return VERBS.get(p["def"]["kind"], "")


func keys() -> int:
	return int(Game.puzzle_state.get("keys", 0))


## Works a piece (the talk key) and says what happened.
func use(p: Dictionary) -> void:
	var line := work(p)
	if line != "":
		await world.say(line)


## Works a piece: changes the room and returns the line to show ("" for none).
func work(p: Dictionary) -> String:
	var d: Dictionary = p["def"]
	var state := _state()
	match d["kind"]:
		"rock":
			state[d["id"]] = true
			world.player.facing = (d["pos"] - world.player.position).normalized()
			_show(p, true)
			_changed()
		"switch":
			state[d["id"]] = not state.get(d["id"], false)
			_show(p, true)
			var opened := 0
			var shut := 0
			for g in d.get("toggles", []):
				var gate := piece(g)
				if gate.is_empty():
					continue
				state[g] = not state.get(g, false)
				if state[g]:
					opened += 1
				else:
					shut += 1
				_show(gate, true)
			_changed()
			var bits: Array = []
			if opened:
				bits.append("%d gate%s opened" % [opened, "" if opened == 1 else "s"])
			if shut:
				bits.append("%d gate%s shut" % [shut, "" if shut == 1 else "s"])
			return "Click! " + (" and ".join(bits) if bits else "Nothing happened") + "."
		"block":
			if state.get(d["id"], false):
				return "The block is empty."
			state[d["id"]] = true
			_show(p, true)
			Game.puzzle_state["keys"] = keys() + 1
			return "You found a Ruins Key! (Keys: %d)" % keys()
		"lock":
			if keys() <= 0:
				return "A stone face with a keyhole in its mouth. It wants a Ruins Key."
			Game.puzzle_state["keys"] = keys() - 1
			state[d["id"]] = true
			_show(p, true)
			_changed()
			return "The stone face swallows the key and sinks into the floor!"
		"prize":
			return Game.claim_ruins_prize()
	return ""


func piece(id: String) -> Dictionary:
	for p in pieces:
		if p["def"]["id"] == id:
			return p
	return {}


## The ground changed: rebuild collision, and move anyone a gate shut on.
func _changed() -> void:
	world.rebuild_collision()
	if not world.can_stand(world.player.position):
		world.player.position = world.nearest_walkable(world.player.position)
	for e in world.enemies:
		if e.has("node") and e["node"] != null and not world.can_stand(e["node"].position):
			e["node"].position = world.nearest_walkable(e["node"].position)
