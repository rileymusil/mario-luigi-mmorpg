extends "res://scripts/battle.gd"
## Online battle, party against party. An evil player attacks a good player
## outside town, and both players' party partners on the map (the other
## players they teamed up with) join in: up to 2 players a side, each with
## their own partners and recruited boss.
##
## Each round:
##   1. Everyone picks a move for each of their characters at the same time,
##      in secret (PLAN_TIME seconds; a character with no pick waits).
##   2. The moves play out fastest first (SPD: heroes 8 + level, partners
##      6 + level, bosses 4 + level, see _roster).
##   3. Whoever makes a move does its timed press on their screen while
##      whoever it's aimed at defends on theirs: {a} as a stomp lands guards
##      it (half damage), {a} to jump over a dash, a throw or a blast. Harder
##      than against enemies: tighter windows, faster attacks.
## Moves: Jump, Hammer, the hero's Special, Bros. Attack (hero and a partner,
## BROS_SP), any item from the bag, Run (50%: you and your partners leave).
## Partners use their own move or an item.
##
## The attacker's game (the host) runs the battle: it collects the picks,
## sorts them, works out what each move does and tells everyone, so every
## screen shows the same thing. Messages go through Net.duel_send:
##   host -> everyone: setup (who is who), plan (pick your moves), do (the
##     next move), res (what it did), tick (burns, someone dropping out), end
##   everyone -> host: roster (your characters), pick (your moves), off (how
##     your timed press went), def (how your defence went)
## Losers drop PVP_COIN_DROP of their coins and maybe an item, which the
## winners share. Leaving or losing the connection mid-battle counts as
## losing; running away doesn't.
##
## pending_battle["pvp"]["bots"] plays it offline against made-up players
## (tests and screenshots); "auto" picks and presses for you too; "no_exit"
## stays on the battle at the end (`finished` still fires).

signal finished(result: String)

const PLAN_TIME := 45.0
const ROSTER_WAIT := 8.0
const PRESS_WAIT := 12.0
const MISSED_ROUNDS := 2   # rounds in a row with no pick before a player drops out
const BROS_SP := 6
const BURN_DAMAGE := 2
const ITEM_DROP_CHANCE := 0.5
## Defending is harder than against enemies (battle.gd LAND_EARLY 0.15,
## LAND_LATE 0.08, charges 0.55-0.85 s).
const GUARD_EARLY := 0.1
const GUARD_LATE := 0.05
const DASH_TIME := Vector2(0.35, 0.55)
const SMALL_SCALE := 1.25  # characters when a side has two players
## Two players a side: the first stands in front, the second behind.
const TEAM_SPOTS := [
	[Vector2(136, 194), Vector2(92, 200), Vector2(48, 192)],
	[Vector2(152, 144), Vector2(108, 138), Vector2(64, 146)],
]
const WORD := {"guard": "Guard!", "dodge": "Dodged!"}

var my_id := ""
var host_id := ""
var is_host := false
var offline := false
var auto := false
var my_side := "good"
var players := {}      # id -> {name, side, character, level, coins, status}; status: in, out, fled, left
var actors: Array = [] # everyone in the battle, in setup order: battle.gd actors plus i, owner, kind
var over := false
var _inbox: Array = [] # {from, d}
var _deadline := 0.0   # while picking: when time runs out (Time.get_ticks_msec)
var _timed_out := false
var _seen_setup := false

# The host's side of things.
var _sim: Array = []      # per actor: {owner, side, kind, name, hp, max_hp, sp, max_sp, pow, def, spd, act, burn, stun, gone}
var _bags := {}           # player id -> {item id: count}, from the rosters
var _missed := {}         # player id -> rounds in a row without a pick
var _seq := 0


func _ready() -> void:
	var info: Dictionary = Game.pending_battle.get("pvp", {})
	offline = info.get("bots", false) == true
	auto = info.get("auto", false) == true
	my_id = "me" if offline else Net.my_id
	host_id = str(info.get("host", my_id))
	is_host = host_id == my_id
	for p in info.get("players", []):
		players[str(p["id"])] = {"name": str(p.get("name", "???")), "side": str(p.get("side", "good")),
			"character": str(p.get("character", "mario")), "level": 1, "coins": 0, "status": "in"}
	if not players.has(my_id):
		players[my_id] = {"name": Game.username(), "side": Game.player["side"], "character": Game.player["character"],
			"level": 1, "coins": 0, "status": "in"}
	my_side = players[my_id]["side"]
	_setup_presentation(Game.player.get("map", ""))
	message.text = "Get ready..."
	_send_host(_roster())
	if is_host:
		_host()
	_run_view()


func _process(delta: float) -> void:
	super(delta)
	if not offline:
		while not Net.duel_inbox.is_empty():
			var m: Dictionary = Net.duel_inbox.pop_front()
			match m.get("t"):
				"duel_msg":
					if typeof(m.get("d")) == TYPE_DICTIONARY:
						_inbox.append({"from": str(m.get("from", "")), "d": m["d"]})
				"duel_left":
					_on_left(str(m.get("id", "")), m.get("fled", false) == true)
				"duel_over":
					_on_called_off(str(m.get("result", "cancel")), str(m.get("winner", "")))
		if not over and not Net.is_online():
			_connection_lost()
	# Out of time while picking: close whatever is open (the pick ends there).
	if _deadline > 0.0 and Time.get_ticks_msec() > _deadline and not _timed_out:
		_timed_out = true
		if blocks.visible:
			blocks.chosen.emit(-1)
		if targets.visible:
			targets.chosen.emit(-1)
		if menu.visible:
			menu.chosen.emit(-1)


# --- Messages ----------------------------------------------------------------------

## From the host to everyone, the host included.
func _send_all(d: Dictionary) -> void:
	if not offline:
		Net.duel_send(d)
	_inbox.append({"from": my_id, "d": d})


func _send_host(d: Dictionary) -> void:
	if is_host:
		_inbox.append({"from": my_id, "d": d})
	else:
		Net.duel_send(d, true)


## The first message of kind k (and sequence s, if given) from `from` (anyone
## if ""), taken out of the inbox; {} if there is none yet.
func _take(k: String, s := -1, from := "") -> Dictionary:
	for i in _inbox.size():
		var m: Dictionary = _inbox[i]
		var d: Dictionary = m["d"]
		if d.get("k") == k and (s < 0 or int(d.get("s", d.get("n", -1))) == s) and (from == "" or m["from"] == from):
			_inbox.remove_at(i)
			return m
	return {}


## Waits up to `timeout` for _take(k, s, from). {} if it never came.
func _await_msg(k: String, timeout: float, s := -1, from := "") -> Dictionary:
	var waited := 0.0
	while not over:
		var m := _take(k, s, from)
		if not m.is_empty():
			return m
		if waited >= timeout:
			break
		await get_tree().process_frame
		waited += get_process_delta_time()
	return {}


# --- Rosters -----------------------------------------------------------------------

## You and your partners as the host needs them:
## [name, sprite, kind, hp, max_hp, sp, max_sp, pow, def, spd, move].
func _roster() -> Dictionary:
	var p: Dictionary = Game.player
	var level: int = p["level"]
	var acts := [[Game.username(), p["character"], "hero", p["hp"], p["max_hp"], p["sp"], p["max_sp"], p["pow"],
		p["def"], 8 + level, Game.CHARACTERS[p["character"]]["special"]]]
	for m in p["party"]:
		var kind: String = m.get("kind", "partner")
		acts.append([m["name"], m["id"], kind, m["hp"], m["max_hp"], 0, 0, m["pow"], m["def"],
			(4 if kind == "boss" else 6) + level, Game.move_of(kind, m["id"])])
	var bag := {}
	for id in Game.owned_items():
		if bag.size() < 9:
			bag[id] = Game.item_count(id)
	return {"k": "roster", "level": level, "coins": p["coins"], "items": bag, "acts": acts}


## A made-up player for offline battles: a hero of their character and one
## partner, about as strong as you.
func _bot_roster(pid: String) -> Dictionary:
	var p: Dictionary = Game.player
	var character: String = players[pid]["character"]
	if not Game.CHARACTERS.has(character):
		character = "mario"
	var c: Dictionary = Game.CHARACTERS[character]
	var level: int = p["level"]
	var hp: int = int(c["hp"]) + 3 * (level - 1)
	var good: bool = players[pid]["side"] == "good"
	var buddy: String = "toad" if good else "goomba"
	var kind := "partner" if good else "enemy"
	var m := Game.make_member(kind, buddy)
	return {"k": "roster", "level": level, "coins": 100, "items": {"mushroom": 2},
		"acts": [[players[pid]["name"], character, "hero", hp, hp, int(c["sp"]), int(c["sp"]), int(c["pow"]) + level - 1,
			int(c["def"]) + (level - 1) / 2, 8 + level, c["special"]],
			[m["name"], buddy, kind, m["hp"], m["max_hp"], 0, 0, m["pow"], m["def"], 6 + level, Game.move_of(kind, buddy)]]}


func _is_bot(pid: String) -> bool:
	return offline and pid != my_id


# --- The host: runs the battle --------------------------------------------------------

func _host() -> void:
	var rosters := {}
	var waited := 0.0
	while rosters.size() < players.size() and waited < ROSTER_WAIT and not over:
		for pid in players:
			if rosters.has(pid):
				continue
			if _is_bot(pid):
				rosters[pid] = _bot_roster(pid)
				continue
			var m := _take("roster", -1, pid)
			if not m.is_empty():
				rosters[pid] = m["d"]
		await get_tree().process_frame
		waited += get_process_delta_time()
	if over:
		return
	var list := []
	var coins := {}
	var levels := {}
	for pid in players:
		if not rosters.has(pid):
			players[pid]["status"] = "left"  # never showed up
			continue
		var r: Dictionary = rosters[pid]
		coins[pid] = maxi(0, int(r.get("coins", 0)))
		levels[pid] = clampi(int(r.get("level", 1)), 1, 99)
		_bags[pid] = {}
		var bag = r.get("items", {})
		if typeof(bag) == TYPE_DICTIONARY:
			for id in bag:
				if Game.ITEMS.has(str(id)):
					_bags[pid][str(id)] = clampi(int(bag[id]), 0, Game.MAX_ITEM)
		var acts = r.get("acts", [])
		if typeof(acts) != TYPE_ARRAY:
			continue
		for a in acts.slice(0, 1 + Game.MAX_PARTY):
			if typeof(a) != TYPE_ARRAY or a.size() < 11:
				continue
			var max_hp := clampi(int(a[4]), 1, 9999)
			_sim.append({"owner": pid, "side": players[pid]["side"], "name": str(a[0]).left(16), "sprite": str(a[1]),
				"kind": str(a[2]), "hp": clampi(int(a[3]), 0, max_hp), "max_hp": max_hp, "sp": clampi(int(a[5]), 0, 999),
				"max_sp": clampi(int(a[6]), 0, 999), "pow": clampi(int(a[7]), 0, 999), "def": clampi(int(a[8]), 0, 999),
				"spd": clampi(int(a[9]), 0, 999), "act": str(a[10]), "burn": 0, "stun": false, "gone": false})
	var rows := []
	for a in _sim:
		rows.append([a["owner"], a["name"], a["sprite"], a["kind"], a["hp"], a["max_hp"], a["sp"], a["max_sp"]])
	_send_all({"k": "setup", "a": rows, "coins": coins, "levels": levels})
	var n := 0
	while not over:
		n += 1
		await _host_round(n)
		var winner = _winner()
		if winner != null:
			_host_end(winner)
			return


## null while both sides can still fight; else the side that won ("" for
## nobody: everyone on a side ran away).
func _winner():
	var done := {}
	for side in ["good", "evil"]:
		var mine := players.keys().filter(func(pid): return players[pid]["side"] == side)
		done[side] = mine.all(func(pid): return players[pid]["status"] != "in" or not _fighting(pid))
	if not done["good"] and not done["evil"]:
		return null
	for side in ["good", "evil"]:
		var other := "evil" if side == "good" else "good"
		if done[side] and not done[other]:
			var beaten := players.keys().any(func(pid): return players[pid]["side"] == side and players[pid]["status"] != "fled")
			return other if beaten else ""
	return ""


## True while any of this player's characters can still fight.
func _fighting(pid: String) -> bool:
	return _sim.any(func(a): return a["owner"] == pid and a["hp"] > 0 and not a["gone"])


func _host_round(n: int) -> void:
	# Burns hurt at the start of the round.
	var notes := []
	for a in _sim:
		if a["hp"] > 0 and not a["gone"] and a["burn"] > 0:
			a["burn"] -= 1
			a["hp"] = maxi(0, a["hp"] - BURN_DAMAGE)
			notes.append("%s is hurt by the burn!" % a["name"])
	_mark_out()
	if not notes.is_empty():
		_send_all({"k": "tick", "hp": _hps(), "st": _statuses(), "note": " ".join(notes), "gone": []})
		await _wait(1.0)
	if _winner() != null:
		return
	var waiting := players.keys().filter(func(pid): return players[pid]["status"] == "in" and _fighting(pid))
	_send_all({"k": "plan", "n": n})
	var picks := {}
	var got := {}
	var waited := 0.0
	while got.size() < waiting.size() and waited < PLAN_TIME + 5.0 and not over:
		for pid in waiting:
			if got.has(pid):
				continue
			if players[pid]["status"] != "in":
				got[pid] = true
				continue
			var acts = null
			if _is_bot(pid):
				acts = _bot_picks(pid)
			else:
				var m := _take("pick", n, pid)
				if not m.is_empty():
					acts = m["d"].get("a", [])
			if acts == null:
				continue
			got[pid] = true
			if typeof(acts) != TYPE_ARRAY:
				continue
			for e in acts:
				if typeof(e) != TYPE_ARRAY or e.size() < 4:
					continue
				var i := int(e[0])
				if i >= 0 and i < _sim.size() and _sim[i]["owner"] == pid:
					picks[i] = {"c": str(e[1]), "t": int(e[2]), "item": str(e[3])}
		await get_tree().process_frame
		waited += get_process_delta_time()
	# Away too long: drop out (counts as losing if their side does).
	var gone := []
	for pid in waiting:
		if players[pid]["status"] != "in":
			continue
		var picked := picks.keys().any(func(i): return _sim[i]["owner"] == pid)
		_missed[pid] = 0 if picked else int(_missed.get(pid, 0)) + 1
		if _missed[pid] >= MISSED_ROUNDS:
			players[pid]["status"] = "left"
			for a in _sim:
				if a["owner"] == pid:
					a["gone"] = true
			gone.append(pid)
	if not gone.is_empty():
		_send_all({"k": "tick", "hp": _hps(), "st": _statuses(), "gone": gone,
			"note": "%s is away and drops out!" % " and ".join(gone.map(func(pid): return players[pid]["name"]))})
		await _wait(1.0)
	# Fastest first; ties go either way.
	var order := []
	for i in picks:
		order.append([float(_sim[i]["spd"]) + randf() * 0.5, i])
	order.sort_custom(func(x, y): return x[0] > y[0])
	for o in order:
		if over or _winner() != null:
			return
		await _host_step(o[1], picks[o[1]])


## Players whose characters are all down are out.
func _mark_out() -> void:
	for pid in players:
		if players[pid]["status"] == "in" and not _fighting(pid):
			players[pid]["status"] = "out"


func _hps() -> Array:
	return _sim.map(func(a): return a["hp"])


## Per actor: 1 burning, 2 stunned, 3 both.
func _statuses() -> Array:
	return _sim.map(func(a): return (1 if a["burn"] > 0 else 0) + (2 if a["stun"] else 0))


func _foes_of(side: String) -> Array:
	var out := []
	for i in _sim.size():
		if _sim[i]["side"] != side and _sim[i]["hp"] > 0 and not _sim[i]["gone"]:
			out.append(i)
	return out


## The animation (and the kind of defence) for actor a's command c.
func _anim_of(a: Dictionary, c: String) -> String:
	match c:
		"jump", "hammer", "bros", "item", "run", "wait":
			return c
		"special":
			match a["act"]:
				"fire_jump":
					return "jump"
				"thunderhand", "pickaxe_pound":
					return "hammer"
				"peach_heart":
					return "heal"
				"fire_breath", "wicked_whirl", "grodus_bolt":
					return "blast"
				"rookie_rush", "bros_tower":
					return "multi"
			return "throw"
		"move":
			var kind: String = Game.MOVES.get(a["act"], {}).get("kind", "tackle")
			return {"stomp": "jump", "tackle": "hammer", "throw": "throw", "blast": "blast", "multi": "multi"}.get(kind, "hammer")
	return "wait"


func _move_name(a: Dictionary, c: String, item: String) -> String:
	match c:
		"jump":
			return "Jump"
		"hammer":
			return "Hammer"
		"bros":
			return "Bros. Attack"
		"special":
			return Game.SPECIALS.get(a["act"], {}).get("name", "Special")
		"move":
			return Game.MOVES.get(a["act"], {}).get("name", "Attack")
		"item":
			return Game.ITEMS.get(item, {}).get("name", "an item")
	return ""


func _host_step(i: int, pick: Dictionary) -> void:
	var a: Dictionary = _sim[i]
	if a["hp"] <= 0 or a["gone"]:
		return
	_seq += 1
	var s := _seq
	var c: String = pick["c"]
	var item: String = pick["item"]
	var note := ""
	if a["stun"]:
		a["stun"] = false
		_send_all({"k": "do", "s": s, "i": i, "c": "stunned", "anim": "wait", "t": [], "name": ""})
		_send_all({"k": "res", "s": s, "hp": _hps(), "sp": _sps(), "st": _statuses(), "pops": [],
			"note": "%s is stunned and can't move!" % a["name"]})
		return
	# Make sure the pick still works; fall back to a Jump.
	var partner := _partner_of(i)
	if c == "special" and (a["kind"] != "hero" or a["sp"] < int(Game.SPECIALS.get(a["act"], {}).get("sp", 99))):
		c = "jump"
	if c == "bros" and (a["kind"] != "hero" or a["sp"] < BROS_SP or partner < 0):
		c = "jump"
	if c in ["jump", "hammer"] and a["kind"] != "hero":
		c = "move"
	if c == "item" and int(_bags.get(a["owner"], {}).get(item, 0)) <= 0:
		c = "wait"
		note = "%s has no %s left!" % [a["name"], Game.ITEMS.get(item, {}).get("name", "item")]
	if c == "run" and a["kind"] != "hero" and _sim.any(func(x): return x["owner"] == a["owner"] and x["kind"] == "hero" and x["hp"] > 0):
		c = "wait"
	var anim := _anim_of(a, c)
	# Targets.
	var t: Array = []
	if anim in ["jump", "hammer", "throw", "multi", "bros"]:
		var foes_left := _foes_of(a["side"])
		if foes_left.is_empty():
			return
		var want: int = pick["t"]
		t = [want if want in foes_left else foes_left.pick_random()]
	elif anim == "blast":
		t = _foes_of(a["side"])
	elif anim == "heal":
		t = _team_of(a["side"])
	elif anim == "item":
		t = [_item_target(i, item, pick["t"])]
	if anim in ["jump", "hammer", "throw", "multi", "bros", "blast", "heal"] and c == "special":
		a["sp"] -= int(Game.SPECIALS[a["act"]]["sp"])
	if c == "bros":
		a["sp"] -= BROS_SP
	_send_all({"k": "do", "s": s, "i": i, "c": c, "anim": anim, "t": t, "item": item, "p": partner,
		"name": _move_name(a, c, item)})
	# Wait for the timed press (the mover) and the defence (whoever it's aimed at).
	var off := {"r": "Miss", "n": 0}
	var defs := {}
	var need_off: bool = anim in ["jump", "hammer", "throw", "multi", "bros", "blast", "heal"]
	var defenders := []
	if anim in ["jump", "hammer", "throw", "multi", "bros", "blast"]:
		for ti in t:
			var o: String = _sim[ti]["owner"]
			if not o in defenders and players[o]["status"] == "in":
				defenders.append(o)
	var waited := 0.0
	while (need_off or not defenders.is_empty()) and waited < PRESS_WAIT and not over:
		if need_off:
			if _is_bot(a["owner"]):
				off = {"r": ["Excellent", "Good", "Good", "Miss"].pick_random(), "n": randi_range(0, 3)}
				need_off = false
			elif players[a["owner"]]["status"] == "left":
				need_off = false
			else:
				var m := _take("off", s, a["owner"])
				if not m.is_empty():
					off = {"r": str(m["d"].get("r", "Miss")), "n": clampi(int(m["d"].get("n", 0)), 0, 4)}
					need_off = false
		for o in defenders.duplicate():
			if _is_bot(o):
				for ti in t:
					if _sim[ti]["owner"] == o:
						defs[ti] = ["none", "none", "guard" if anim in ["jump", "bros"] else "dodge"].pick_random()
				defenders.erase(o)
			elif players[o]["status"] != "in":
				defenders.erase(o)
			else:
				var m := _take("def", s, o)
				if not m.is_empty():
					var r = m["d"].get("r", {})
					if typeof(r) == TYPE_DICTIONARY:
						for key in r:
							var ti := int(key)
							if ti in t and _sim[ti]["owner"] == o and str(r[key]) in ["guard", "dodge"]:
								# Only the defence that fits: guard a stomp, jump the rest.
								if (str(r[key]) == "guard") == (anim in ["jump", "bros"]):
									defs[ti] = str(r[key])
					defenders.erase(o)
		if need_off or not defenders.is_empty():
			await get_tree().process_frame
			waited += get_process_delta_time()
	if not off["r"] in ["Excellent", "Good", "Miss"]:
		off["r"] = "Miss"
	var res := _resolve(i, c, anim, t, item, off, defs)
	if note != "":
		res["note"] = note
	res.merge({"k": "res", "s": s, "hp": _hps(), "sp": _sps(), "st": _statuses()})
	_mark_out()
	_send_all(res)


func _sps() -> Array:
	return _sim.map(func(a): return a["sp"])


func _team_of(side: String) -> Array:
	var out := []
	for i in _sim.size():
		if _sim[i]["side"] == side and _sim[i]["hp"] > 0 and not _sim[i]["gone"]:
			out.append(i)
	return out


## The first of the hero's own partners still standing, or -1.
func _partner_of(i: int) -> int:
	if _sim[i]["kind"] != "hero":
		return -1
	for j in _sim.size():
		if j != i and _sim[j]["owner"] == _sim[i]["owner"] and _sim[j]["hp"] > 0 and not _sim[j]["gone"]:
			return j
	return -1


## Who an item goes to: the pick if it still makes sense, else the user.
func _item_target(i: int, item: String, want: int) -> int:
	var info: Dictionary = Game.ITEMS.get(item, {})
	var side: String = _sim[i]["side"]
	if want >= 0 and want < _sim.size() and _sim[want]["side"] == side and not _sim[want]["gone"]:
		if info.has("revive") or _sim[want]["hp"] > 0:
			return want
	return i


## What a move does. Returns the res fields: pops [[actor, text]], words
## [[actor, text]] (Guard! / Dodged!), note, fled.
func _resolve(i: int, c: String, anim: String, t: Array, item: String, off: Dictionary, defs: Dictionary) -> Dictionary:
	var a: Dictionary = _sim[i]
	var r: String = off["r"]
	var pops := []
	var words := []
	var notes := []
	var out := {"pops": pops, "words": words, "rating": r if anim not in ["item", "run", "wait"] else ""}
	match c:
		"wait":
			out["rating"] = ""
			return out
		"run":
			if randf() < 0.5:
				players[a["owner"]]["status"] = "fled"
				for x in _sim:
					if x["owner"] == a["owner"]:
						x["gone"] = true
				out["fled"] = a["owner"]
				out["note"] = "%s got away!" % players[a["owner"]]["name"]
			else:
				out["note"] = "%s couldn't get away!" % players[a["owner"]]["name"]
			return out
		"item":
			_bags[a["owner"]][item] = int(_bags[a["owner"]].get(item, 0)) - 1
			var who: Dictionary = _sim[t[0]]
			var info: Dictionary = Game.ITEMS.get(item, {})
			if info.has("hp") and who["hp"] > 0:
				var before: int = who["hp"]
				who["hp"] = mini(who["max_hp"], who["hp"] + int(info["hp"]))
				pops.append([t[0], "+%d HP" % (who["hp"] - before)])
			elif info.has("sp"):
				var before: int = who["sp"]
				who["sp"] = mini(who["max_sp"], who["sp"] + int(info["sp"]))
				pops.append([t[0], "+%d SP" % (who["sp"] - before)])
			elif info.has("revive"):
				if who["hp"] <= 0:
					who["hp"] = maxi(1, int(who["max_hp"] * float(info["revive"])))
					out["note"] = "%s is back on their feet!" % who["name"]
					pops.append([t[0], "+%d HP" % who["hp"]])
				else:
					out["note"] = "It had no effect..."
			elif info.get("cure", false):
				who["burn"] = 0
				who["stun"] = false
				pops.append([t[0], "Cured!"])
			elif info.has("pow"):
				who["pow"] += int(info["pow"])
				pops.append([t[0], "POW +%d" % int(info["pow"])])
			elif info.has("def"):
				who["def"] += int(info["def"])
				pops.append([t[0], "DEF +%d" % int(info["def"])])
			return out
	var exc := r == "Excellent"
	var good := r != "Miss"
	var power: int = a["pow"]
	var hits: Array = []
	var ignore_def := false
	var heal_team := 0
	var drain := false
	var stun := false
	var burn := 0
	var def_down := 0
	match c:
		"jump":
			hits = [power] + ([power + (1 if exc else 0)] if good else [])
		"hammer":
			hits = [power + {"Excellent": 3, "Good": 2, "Miss": 0}[r]]
		"bros":
			# Hero and partner stomp in turn: one more for each good press (max 4).
			var mate: Dictionary = _sim[_partner_of(i)] if _partner_of(i) >= 0 else a
			for k in 1 + mini(int(off["n"]), 3):
				hits.append((power if k % 2 == 0 else int(mate["pow"])) + 1)
		"special":
			var bonus: int = {"Excellent": 3, "Good": 1, "Miss": 0}[r]
			match a["act"]:
				"fire_jump":
					hits = [power] + ([power + (1 if exc else 0)] if good else [])
					burn = 3 + (1 if exc else 0)
				"thunderhand":
					hits = [power + 2 + (2 if exc else 0)]
					stun = exc or (good and randf() < 0.5)
				"peach_heart":
					heal_team = {"Excellent": 14, "Good": 10, "Miss": 6}[r]
				"fire_breath", "wicked_whirl":
					hits = [power + {"Excellent": 3, "Good": 1, "Miss": -1}[r]]
					stun = a["act"] == "wicked_whirl" and exc
				"grodus_bolt":
					hits = [power + {"Excellent": 2, "Good": 1, "Miss": -1}[r]]
					def_down = {"Excellent": 2, "Good": 1, "Miss": 0}[r]
				"star_spin":
					hits = [power + 1 + bonus]
					heal_team = {"Excellent": 6, "Good": 4, "Miss": 2}[r]
				"pickaxe_pound":
					hits = [power + {"Excellent": 4, "Good": 2, "Miss": 0}[r]]
					ignore_def = true
				"shadow_drain", "poltergust_pull":
					hits = [power + bonus]
					drain = true
				"rookie_rush":
					for k in maxi(1, int(off["n"])):
						hits.append(power - 1 + 2 * k)
				"bros_tower":
					hits = [power + 1 + int(off["n"])]
				_:
					hits = [power + 2 + bonus]
		"move":
			var move: Dictionary = Game.MOVES.get(a["act"], {})
			power += int(move.get("bonus", 0))
			ignore_def = move.get("ignore_def", false)
			match move.get("kind", "tackle"):
				"stomp":
					hits = [power] + ([power + (1 if exc else 0)] if good else [])
				"blast":
					hits = [power + {"Excellent": 2, "Good": 0, "Miss": -1}[r]]
				"multi":
					for k in clampi(int(off["n"]), 1, int(move.get("hits", 2))):
						hits.append(power - 1 + (1 if good else 0))
				_:
					hits = [power + {"Excellent": 2, "Good": 1, "Miss": 0}[r]]
			if exc:
				stun = move.get("stun", false)
				burn = int(move.get("burn", 0))
				def_down = int(move.get("def_down", 0))
				heal_team = int(move.get("heal", 0))
	var dealt := 0
	for ti in t:
		var who: Dictionary = _sim[ti]
		if anim == "heal":
			continue
		var d: String = defs.get(ti, "none")
		var dmg := 0
		for h in hits:
			dmg += maxi(1, int(h) - (0 if ignore_def else int(who["def"])))
		if d == "dodge":
			dmg = 0
			words.append([ti, "Dodged!"])
		elif d == "guard":
			dmg = dmg / 2
			words.append([ti, "Guard!"])
		if hits.is_empty():
			continue
		who["hp"] = maxi(0, who["hp"] - dmg)
		dealt += dmg
		pops.append([ti, str(dmg)])
		if dmg > 0 and who["hp"] > 0:
			if stun:
				who["stun"] = true
				notes.append("%s is stunned!" % who["name"])
			if burn > 0:
				who["burn"] = maxi(who["burn"], burn)
				notes.append("%s is burning!" % who["name"])
			if def_down > 0 and who["def"] > 0:
				who["def"] = maxi(0, who["def"] - def_down)
				notes.append("%s's DEF went down!" % who["name"])
		if who["hp"] <= 0:
			who["burn"] = 0
			who["stun"] = false
			notes.append("%s is down!" % who["name"])
	if drain and dealt > 0:
		a["hp"] = mini(a["max_hp"], a["hp"] + dealt)
		pops.append([i, "+%d HP" % dealt])
	if heal_team > 0:
		for j in _team_of(a["side"]):
			_sim[j]["hp"] = mini(_sim[j]["max_hp"], _sim[j]["hp"] + heal_team)
			if anim == "heal":
				pops.append([j, "+%d HP" % heal_team])
		if anim != "heal":
			notes.append("The team heals %d HP!" % heal_team)
	out["note"] = "  ".join(notes)
	return out


## Made-up picks for an offline player: attack someone, with a special now
## and then.
func _bot_picks(pid: String) -> Array:
	var acts := []
	for i in _sim.size():
		var a: Dictionary = _sim[i]
		if a["owner"] != pid or a["hp"] <= 0 or a["gone"]:
			continue
		var foes_left := _foes_of(a["side"])
		if foes_left.is_empty():
			break
		var c := "move"
		if a["kind"] == "hero":
			c = ["jump", "hammer", "jump"].pick_random()
			if a["sp"] >= int(Game.SPECIALS.get(a["act"], {}).get("sp", 99)) and randf() < 0.3:
				c = "special"
		acts.append([i, c, foes_left.pick_random(), ""])
	return acts


func _host_end(winner: String) -> void:
	var winners := players.keys().filter(func(pid): return players[pid]["side"] == winner and players[pid]["status"] in ["in", "out"])
	var losers := players.keys().filter(func(pid): return winner != "" and players[pid]["side"] != winner and players[pid]["status"] != "fled")
	var gain := {}
	var loss := {}
	for pid in winners:
		gain[pid] = [0, 0, []]
	var pot := 0
	var xp := 0
	for pid in losers:
		var drop: int = Game.pvp_drop(int(players[pid]["coins"]))
		var lost_item := ""
		var bag: Dictionary = _bags.get(pid, {})
		var have := bag.keys().filter(func(id): return int(bag[id]) > 0)
		if not have.is_empty() and randf() < ITEM_DROP_CHANCE:
			lost_item = have.pick_random()
		loss[pid] = [drop, lost_item]
		pot += drop
		xp += 4 + 2 * int(players[pid]["level"])
		if lost_item != "" and not winners.is_empty():
			gain[winners.pick_random()][2].append(lost_item)
	for k in winners.size():
		gain[winners[k]][0] = pot / winners.size() + (pot % winners.size() if k == 0 else 0)
		gain[winners[k]][1] = xp
	_send_all({"k": "end", "w": winner, "gain": gain, "loss": loss})
	if not offline:
		Net.finish_duel(winner)


# --- Everyone: shows the battle ---------------------------------------------------------

func _run_view() -> void:
	var setup := await _await_msg("setup", ROSTER_WAIT + 6.0)
	if over:
		return
	if setup.is_empty():
		_called_off("The battle was called off.")
		return
	_build(setup["d"])
	_seen_setup = true
	message.text = _intro()
	await _wait(1.4)
	while not over:
		var m := _next_event()
		if m.is_empty():
			await get_tree().process_frame
			continue
		var d: Dictionary = m["d"]
		match d.get("k"):
			"plan":
				await _plan(int(d.get("n", 0)))
			"do":
				await _show_step(d)
			"tick":
				_apply_state(d)
				for pid in d.get("gone", []):
					_hide_player(str(pid))
				message.text = str(d.get("note", ""))
				await _wait(1.0)
			"end":
				await _end(d)
				return


func _next_event() -> Dictionary:
	for i in _inbox.size():
		if _inbox[i]["d"].get("k") in ["plan", "do", "tick", "end"]:
			return _inbox.pop_at(i)
	return {}


func _intro() -> String:
	var foes_names := []
	for pid in players:
		if players[pid]["side"] != my_side:
			foes_names.append(players[pid]["name"])
	return ("You attack %s!" if my_side == "evil" else "%s attacks you!") % " and ".join(foes_names)


## Puts everyone on the field: your side on the left, theirs on the right.
func _build(d: Dictionary) -> void:
	var rows: Array = d.get("a", [])
	var coins = d.get("coins", {})
	var levels = d.get("levels", {})
	for pid in players:
		if typeof(coins) == TYPE_DICTIONARY:
			players[pid]["coins"] = int(coins.get(pid, 0))
		if typeof(levels) == TYPE_DICTIONARY:
			players[pid]["level"] = int(levels.get(pid, 1))
	# Owners in order, you first on your side.
	var owners := {"mine": [], "theirs": []}
	for row in rows:
		var o := str(row[0])
		var key := "mine" if players.get(o, {}).get("side", "good") == my_side else "theirs"
		if not o in owners[key]:
			owners[key].append(o)
	if my_id in owners["mine"]:
		owners["mine"].erase(my_id)
		owners["mine"].push_front(my_id)
	var two: bool = owners["mine"].size() > 1 or owners["theirs"].size() > 1
	var size := SMALL_SCALE if two else SCALE
	var party_index := 0
	var count := {}
	for row in rows:
		var o := str(row[0])
		var ally: bool = players.get(o, {}).get("side", "good") == my_side
		var team: Array = owners["mine" if ally else "theirs"]
		var k: int = count.get(o, 0)
		count[o] = k + 1
		var spot: Vector2 = (TEAM_SPOTS[team.find(o)][k] if two else ALLY_SPOTS[k])
		if not ally:
			spot.x = 384.0 - spot.x
		var node := CharacterSprite.new()
		var sprite := str(row[2])
		node.character_id = sprite if ResourceLoader.exists("res://assets/characters/%s.png" % sprite) else "mario"
		node.facing = Vector2.RIGHT if ally else Vector2.LEFT
		node.scale = Vector2(size, size)
		node.position = _spot(spot)
		stage.add_child(node)
		if str(row[3]) == "boss":
			node.scale = Vector2.ONE * node.battle_scale(size)
		# Two of the same (two Toads): the second is "Toad B", like enemies.
		var shown := str(row[1])
		if actors.any(func(x): return x["name"] == shown and x["ally"] == ally):
			shown += " B"
		var a := {"i": actors.size(), "owner": o, "kind": str(row[3]), "name": shown, "type": node.character_id,
			"node": node, "ally": ally, "home": node.position, "pow": 0, "def": 0, "burn": 0, "stun": false,
			"dizzy": false, "hp": int(row[4]), "max_hp": maxi(1, int(row[5]))}
		if ally:
			var member: Dictionary
			if o == my_id and k == 0:
				member = Game.player
			elif o == my_id and party_index < Game.player["party"].size():
				member = Game.player["party"][party_index]
				party_index += 1
			else:
				member = {"hp": int(row[4]), "max_hp": maxi(1, int(row[5]))}
			a["member"] = member
			# Your teammate's partners: no HP box at the bottom (it would get too wide).
			a["no_box"] = o != my_id and k > 0
			a["you"] = o == my_id and k == 0
			allies.append(a)
		else:
			foes.append(a)
		actors.append(a)
		_set_hp(a, int(row[4]))
	_refresh()


func _mine(a: Dictionary) -> bool:
	return a["owner"] == my_id


func _hide_player(pid: String) -> void:
	for a in actors:
		if a["owner"] == pid:
			a["gone"] = true
			var fade := create_tween()
			fade.tween_property(a["node"], "modulate:a", 0.0, 0.4)
	_refresh()


## HP, SP and statuses from the host.
func _apply_state(d: Dictionary) -> void:
	var hp = d.get("hp", [])
	var sp = d.get("sp", [])
	var st = d.get("st", [])
	for a in actors:
		var i: int = a["i"]
		if typeof(hp) == TYPE_ARRAY and i < hp.size():
			_set_hp(a, int(hp[i]))
			if not a["ally"]:
				a["node"].modulate.a = 1.0 if a["hp"] > 0 else 0.4
			if a.get("gone", false):
				a["node"].modulate.a = 0.0
		if typeof(st) == TYPE_ARRAY and i < st.size():
			a["burn"] = 1 if int(st[i]) & 1 else 0
			a["stun"] = (int(st[i]) & 2) != 0
			a["dizzy"] = a["stun"]
		if typeof(sp) == TYPE_ARRAY and i < sp.size() and _mine(a) and a["kind"] == "hero":
			Game.player["sp"] = clampi(int(sp[i]), 0, Game.player["max_sp"])
	_refresh()


# --- Picking moves ------------------------------------------------------------------------

func _plan(n: int) -> void:
	var mine := actors.filter(func(a): return _mine(a) and _hp(a) > 0 and not a.get("gone", false))
	if mine.is_empty() or players[my_id]["status"] != "in":
		message.text = "Everyone is picking their moves..."
		return
	_deadline = Time.get_ticks_msec() + PLAN_TIME * 1000.0 / maxf(0.01, Engine.time_scale)
	_timed_out = false
	var acts := []
	var reserved := {}
	for a in mine:
		if over or _timed_out:
			break
		var pick: Array = _auto_pick(a) if auto else await _pick_move(a, reserved)
		if pick.is_empty():
			break
		acts.append([a["i"]] + pick)
		if pick[0] == "run":
			break  # the whole group runs
	_deadline = 0.0
	_set_turn({})
	blocks.visible = false
	targets.visible = false
	menu.visible = false
	if _timed_out:
		message.text = "Out of time!"
		await _wait(0.6)
	_send_host({"k": "pick", "n": n, "a": acts})
	message.text = "Waiting for the others..."


func _auto_pick(a: Dictionary) -> Array:
	var alive := _alive(foes).filter(func(f): return not f.get("gone", false))
	if alive.is_empty():
		return []
	var c := "move"
	if a["kind"] == "hero":
		c = ["jump", "hammer"].pick_random()
	return [c, alive.pick_random()["i"], ""]


## Picks a move (and a target or an item) for one of your characters:
## [command, target, item], or [] when time ran out.
func _pick_move(a: Dictionary, reserved: Dictionary) -> Array:
	var hero: bool = a["kind"] == "hero"
	var commands := []
	if hero:
		var p: Dictionary = Game.player
		var sp: Dictionary = Game.SPECIALS[Game.CHARACTERS[p["character"]]["special"]]
		var has_partner := actors.any(func(x): return _mine(x) and x["kind"] != "hero" and _hp(x) > 0 and not x.get("gone", false))
		commands = [
			{"id": "jump", "label": "Jump", "icon": "jump", "info": "Stomp! Press {a} as you land for a 2nd hit."},
			{"id": "hammer", "label": "Hammer", "icon": "hammer", "info": "One big swing, {a} in the gold zone. Good against high DEF."},
			{"id": "special", "label": "%s (%d SP)" % [sp["name"], sp["sp"]], "icon": "burst",
				"enabled": p["sp"] >= sp["sp"], "info": sp["info"]},
			{"id": "bros", "label": "Bros. Attack (%d SP)" % BROS_SP, "icon": "hand", "enabled": has_partner and p["sp"] >= BROS_SP,
				"info": "You and a partner stomp in turn: {a} as each one lands." if has_partner else "Needs a partner still standing."},
		]
	else:
		var move: Dictionary = Game.MOVES.get(Game.move_of(a["kind"], a["type"]), {})
		commands = [{"id": "move", "label": move.get("name", "Attack"), "icon": "hammer", "info": move.get("info", "")}]
	commands.append({"id": "item", "label": "Items", "icon": "mushroom", "enabled": not _usable_items(reserved).is_empty(),
		"info": "Use any item from your bag."})
	var hero_up := actors.any(func(x): return _mine(x) and x["kind"] == "hero" and _hp(x) > 0)
	if hero or not hero_up:
		commands.append({"id": "run", "label": "Run", "icon": "run", "info": "50% chance. You and your partners leave the battle."})
	_set_turn(a if a["ally"] and a.has("panel") else {})
	while not _timed_out and not over:
		_say("Pick a move for %s." % a["name"])
		var i: int = await blocks.choose(commands, a["node"], not hero)
		if i < 0 or _timed_out:
			return []
		var c: String = commands[i]["id"]
		match c:
			"run":
				return ["run", -1, ""]
			"item":
				var got := await _pick_item(reserved)
				if got.is_empty():
					continue
				reserved[got[1]] = int(reserved.get(got[1], 0)) + 1
				return ["item", got[0], got[1]]
			_:
				var alive := _alive(foes).filter(func(f): return not f.get("gone", false))
				if alive.is_empty():
					return []
				var target = alive[0]
				if alive.size() > 1:
					target = await _pick(alive, "Attack who?", func(f): return "%s %d/%d" % [f["name"], f["hp"], f["max_hp"]])
				if target == null:
					continue
				return [c, target["i"], ""]
	return []


func _usable_items(reserved: Dictionary) -> Array:
	return Game.owned_items().filter(func(id): return Game.item_count(id) - int(reserved.get(id, 0)) > 0 \
		and not _item_targets(id).is_empty())


## [target actor, item id], or [] to go back.
func _pick_item(reserved: Dictionary) -> Array:
	while not _timed_out:
		var ids := Game.owned_items()
		var labels := []
		var enabled := []
		var infos := []
		var icons := []
		var usable := _usable_items(reserved)
		for id in ids:
			labels.append("%s x%d" % [Game.ITEMS[id]["name"], Game.item_count(id) - int(reserved.get(id, 0))])
			enabled.append(id in usable)
			infos.append(Game.ITEMS[id]["info"])
			icons.append(load("res://assets/items/%s.png" % id))
		menu.max_rows = 5
		menu.info_width = 150.0
		_say("Which item? {b} to go back.")
		var i := await menu.choose(labels, "Items", true, enabled, infos, icons)
		if i < 0 or _timed_out:
			return []
		var id: String = ids[i]
		var list := _item_targets(id)
		var who = list[0]
		if list.size() > 1:
			who = await _pick(list, "Use the %s on who?" % Game.ITEMS[id]["name"],
				func(t): return "%s %d/%d" % [t["name"], _hp(t), t["member"]["max_hp"]])
			if who == null:
				continue
		return [who["i"], id]
	return []


## battle.gd's item targets, minus anyone who left.
func _item_targets(id: String) -> Array:
	return super(id).filter(func(a): return not a.get("gone", false))


# --- Showing a move -----------------------------------------------------------------------

func _show_step(d: Dictionary) -> void:
	var s := int(d.get("s", 0))
	var i := int(d.get("i", -1))
	if i < 0 or i >= actors.size():
		await _await_res(s)
		return
	var a: Dictionary = actors[i]
	var anim := str(d.get("anim", "wait"))
	var c := str(d.get("c", "wait"))
	var t: Array = []
	for ti in d.get("t", []):
		if int(ti) >= 0 and int(ti) < actors.size():
			t.append(actors[int(ti)])
	var mate: Dictionary = actors[int(d["p"])] if int(d.get("p", -1)) >= 0 and int(d.get("p", -1)) < actors.size() else {}
	var mine := _mine(a)
	var name := str(d.get("name", ""))
	if c != "stunned" and name != "":
		message.text = "%s uses %s!" % [a["name"], name] if c != "item" else "%s uses %s!" % [a["name"], Game.with_article(name)]
	elif c == "run":
		message.text = "%s tries to run..." % a["name"]
	if c == "item" and mine:
		Game.add_item(str(d.get("item", "")), -1)
	var res := {}
	if mine and not auto:
		var off := await _offense(a, anim, t, mate)
		if not off.is_empty():
			_send_host({"k": "off", "s": s, "r": off["r"], "n": off["n"]})
	elif mine:
		await _watch(a, anim, t, mate, [])
		if anim in ["jump", "hammer", "throw", "multi", "bros", "blast", "heal"]:
			_send_host({"k": "off", "s": s, "r": ["Excellent", "Good", "Miss"].pick_random(), "n": randi_range(0, 3)})
	else:
		var defend := t.filter(func(x): return _mine(x)) if anim in ["jump", "hammer", "throw", "multi", "bros", "blast"] else []
		var defs := await _watch(a, anim, t, mate, defend)
		if not defend.is_empty():
			if auto:
				defs = {}
			_send_host({"k": "def", "s": s, "r": defs})
	res = await _await_res(s)
	if over:
		return
	_show_res(res, a)
	await _wait(0.9)
	# Everyone back where they stand.
	for x in [a, mate]:
		if x.is_empty():
			continue
		if x["node"].position.distance_to(x["home"]) > 0.5:
			await _walk(x["node"], x["home"], 200.0)
		x["node"].facing = Vector2.RIGHT if x["ally"] else Vector2.LEFT
	if str(res.get("fled", "")) != "":
		await _someone_fled(str(res["fled"]))


func _await_res(s: int) -> Dictionary:
	var m := await _await_msg("res", 60.0, s)
	return m.get("d", {})


func _show_res(res: Dictionary, a: Dictionary) -> void:
	_apply_state(res)
	var rating_text := str(res.get("rating", ""))
	if not _mine(a) and rating_text != "":
		_show_rating(rating_text)
	for w in res.get("words", []):
		if typeof(w) == TYPE_ARRAY and w.size() == 2 and int(w[0]) < actors.size():
			_show_rating(str(w[1]))
	for p in res.get("pops", []):
		if typeof(p) != TYPE_ARRAY or p.size() != 2 or int(p[0]) >= actors.size():
			continue
		var who: Dictionary = actors[int(p[0])]
		var text := str(p[1])
		if text.is_valid_int() and int(text) > 0:
			_flash(who["node"])
			_shake(2.5, 0.12)
		_popup(who["node"].position + Vector2(0, -50), text)
	var note := str(res.get("note", ""))
	if note != "":
		message.text = note


## Which way `a` faces to hit someone: right from the left side.
func _dir(a: Dictionary) -> float:
	return 1.0 if a["ally"] else -1.0


## Your own move, with its timed presses. Returns {r, n} for the host as soon
## as the presses are done (the rest of the animation plays after).
func _offense(a: Dictionary, anim: String, t: Array, mate: Dictionary) -> Dictionary:
	var node: CharacterSprite = a["node"]
	var target: Dictionary = t[0] if not t.is_empty() else {}
	match anim:
		"jump":
			var tnode: CharacterSprite = target["node"]
			var stand: Vector2 = tnode.position + Vector2(-40 * _dir(a), 0)
			var top: Vector2 = tnode.position + Vector2(0, -tnode.height() * tnode.scale.y * 0.8)
			_say("Press {a} just as you land!")
			await _walk(node, stand, 160.0)
			var badge := _show_badge(a, "jump")
			var r := _rate_landing(await _arc(node, node.position, top, 50.0, 0.55, true))
			badge.queue_free()
			_show_rating(r)
			if r != "Miss":
				await _arc(node, top, top, 38.0, 0.45, false)
			await _arc(node, node.position, stand, 28.0, 0.35, false)
			return {"r": r, "n": 0}
		"hammer", "throw", "blast", "heal":
			var r := await _timing_bar(1.0, "hammer_red" if anim == "hammer" else "burst_red")
			if anim == "hammer":
				await _walk(node, target["node"].position + Vector2(-26 * _dir(a), 0), 220.0)
				_swing_at(a)
			elif anim == "throw":
				await _projectile(_middle(a) + Vector2(10 * _dir(a), 0), _middle(target), Color(1.0, 0.75, 0.3))
			elif anim == "blast":
				for x in t:
					_burst(_middle(x), Color(1.0, 0.6, 0.15), 22.0)
			return {"r": r, "n": 0}
		"multi":
			await _walk(node, target["node"].position + Vector2(-26 * _dir(a), 0), 220.0)
			var r := "Miss"
			var n := 0
			for k in 3:
				r = await _timing_bar(0.8, "hammer_red")
				_swing_at(a)
				if r == "Miss":
					break
				n += 1
			return {"r": "Excellent" if n == 3 else ("Good" if n > 0 else "Miss"), "n": n}
		"bros":
			var tnode: CharacterSprite = target["node"]
			var top: Vector2 = tnode.position + Vector2(0, -tnode.height() * tnode.scale.y * 0.8)
			var stands := [tnode.position + Vector2(-40 * _dir(a), 0), tnode.position + Vector2(-64 * _dir(a), 0)]
			_say("Bros. Attack! {a} as each one lands!")
			await _walk(node, stands[0], 180.0)
			if not mate.is_empty():
				await _walk(mate["node"], stands[1], 220.0)
			var n := 0
			var r := "Miss"
			for k in 4:
				var who: Dictionary = a if k % 2 == 0 or mate.is_empty() else mate
				var wnode: CharacterSprite = who["node"]
				var badge := _show_badge(who, "jump")
				r = _rate_landing(await _arc(wnode, wnode.position, top, 46.0, 0.5 if k < 2 else 0.4, true))
				badge.queue_free()
				_show_rating(r)
				await _arc(wnode, top, stands[0 if who == a else 1], 26.0, 0.3, false)
				if r == "Miss" or k == 3:
					break
				n += 1
			return {"r": "Excellent" if n >= 3 else ("Good" if n > 0 else "Miss"), "n": n}
	await _wait(0.5)
	return {}


func _swing_at(a: Dictionary) -> void:
	var node: CharacterSprite = a["node"]
	var t := create_tween()
	t.tween_property(node, "position:x", node.position.x + 10.0 * _dir(a), 0.06)
	t.tween_property(node, "position:x", node.position.x, 0.12)


## Someone else's move as it plays out on your screen. `defend`: your
## characters it's aimed at; you get one press for them all. Returns the
## defence for the host: {actor index: "guard" / "dodge"}.
func _watch(a: Dictionary, anim: String, t: Array, mate: Dictionary, defend: Array) -> Dictionary:
	var node: CharacterSprite = a["node"]
	var target: Dictionary = t[0] if not t.is_empty() else {}
	var out := {}
	match anim:
		"jump", "bros":
			var tnode: CharacterSprite = target["node"]
			var stand: Vector2 = tnode.position + Vector2(-40 * _dir(a), 0)
			var top: Vector2 = tnode.position + Vector2(0, -tnode.height() * tnode.scale.y * 0.8)
			await _walk(node, stand, 160.0)
			if anim == "bros" and not mate.is_empty():
				await _walk(mate["node"], stand + Vector2(-24 * _dir(a), 0), 220.0)
			if not defend.is_empty():
				_say("Press {a} as %s lands to guard!", [a["name"]])
			var badge: Sprite2D = null
			if not defend.is_empty():
				badge = _show_badge(target, "jump")
			var timing := await _arc(node, node.position, top, 50.0, 0.5, not defend.is_empty())
			if badge:
				badge.queue_free()
			if not defend.is_empty() and timing >= -GUARD_EARLY and timing <= GUARD_LATE:
				for x in defend:
					out[str(x["i"])] = "guard"
			await _arc(node, top, stand, 28.0, 0.35, false)
		"hammer", "multi", "throw", "blast":
			# Winding up while they do their press.
			for k in 8:
				node.position.x = a["home"].x + (2.0 if k % 2 == 0 else -2.0)
				await _wait(0.1)
			node.position = a["home"]
			await _wait(randf_range(0.0, 0.4))  # no counting along
			var nodes: Array = defend.map(func(x): return x["node"])
			if not defend.is_empty():
				_say("%s attacks! Press {a} to jump!", [a["name"]])
			var badge: Sprite2D = null
			if not defend.is_empty():
				badge = _show_badge(defend[0], "jump")
			var duration := randf_range(DASH_TIME.x, DASH_TIME.y)
			var contact: Vector2 = target["node"].position + Vector2(-12 * _dir(a), 0) if not target.is_empty() else node.position
			var start := node.position
			var ball: Polygon2D = null
			if anim == "throw" or anim == "blast":
				ball = _circle(5.0 if anim == "throw" else 9.0, Color(1.0, 0.6, 0.2))
				ball.position = _middle(a)
				ball.z_index = 10
				stage.add_child(ball)
			var t0 := 0.0
			while t0 < duration:
				await get_tree().process_frame
				t0 = minf(t0 + get_process_delta_time(), duration)
				var k := t0 / duration
				if ball:
					ball.position = _middle(a).lerp(_middle(target) if anim == "throw" else contact + Vector2(0, -10), k)
				else:
					node.position = start.lerp(contact, k)
					node.move_velocity = Vector2(100 * _dir(a), 0)
				if Input.is_action_just_pressed("action"):
					for n in nodes:
						n.jump()
			node.move_velocity = Vector2.ZERO
			if badge:
				badge.queue_free()
			for x in defend:
				if x["node"].jump_height > 8.0:
					out[str(x["i"])] = "dodge"
			if ball:
				if anim == "blast":
					for x in t:
						_burst(_middle(x), Color(1.0, 0.6, 0.15), 22.0)
				ball.queue_free()
		"heal":
			await _wait(1.0)
			for x in t:
				_burst(_middle(x), Color(1.0, 0.6, 0.8), 14.0)
		"item", "run":
			await _wait(0.6)
		_:
			await _wait(0.3)
	return out


func _someone_fled(pid: String) -> void:
	if pid == my_id:
		message.text = "Got away safely!"
		for a in actors:
			if _mine(a):
				a["node"].modulate.a = 0.0
		await _wait(1.0)
		if not is_host:
			over = true
			Net.end_duel("fled")
			_leave("fled")
			return
		message.text = "Got away! The others fight on..."
	else:
		_hide_player(pid)


# --- Endings -------------------------------------------------------------------------------

func _end(d: Dictionary) -> void:
	over = true
	blocks.visible = false
	targets.visible = false
	menu.visible = false
	var winner := str(d.get("w", ""))
	var gain = d.get("gain", {})
	var loss = d.get("loss", {})
	if typeof(gain) == TYPE_DICTIONARY and gain.has(my_id):
		var g: Array = gain[my_id]
		await _victory(int(g[0]), int(g[1]), g[2] if typeof(g[2]) == TYPE_ARRAY else [])
	elif typeof(loss) == TYPE_DICTIONARY and loss.has(my_id):
		var l: Array = loss[my_id]
		await _defeat(int(l[0]), str(l[1]))
	else:
		message.text = "The battle is over." if winner == "" else ("Your side won!" if winner == my_side else "Your side lost...")
		await _wait(1.8)
		_leave("fled")


func _victory(coins: int, xp: int, items: Array) -> void:
	var p: Dictionary = Game.player
	p["coins"] += coins
	p["wins"] += 1
	p["pvp_wins"] = int(p.get("pvp_wins", 0)) + 1  # for the achievements
	p["hp"] = maxi(1, p["hp"])
	for m in p["party"]:
		m["hp"] = maxi(1, m["hp"])
	for f in foes:
		var fade := create_tween()
		fade.tween_property(f["node"], "modulate:a", 0.0, 0.4)
	_show_rating("YOU WIN!")
	var levels := Game.gain_xp(xp)
	await _wait(0.8)
	message.text = "You won! +%d XP  +%d coins" % [xp, coins]
	_refresh()
	await _wait(1.8)
	for item in items:
		if not Game.ITEMS.has(str(item)):
			continue
		Game.add_item(str(item))
		message.text = "Picked up %s they dropped!" % Game.with_article(Game.ITEMS[str(item)]["name"])
		await _item_pop(allies[0], str(item))
		await _wait(0.8)
	if levels > 0:
		message.text = "Level up! %s is now level %d!" % [Game.character_name(), p["level"]]
		_show_rating("LEVEL UP!")
		_refresh()
		await _wait(1.8)
	_leave("won")


func _defeat(coins: int, item: String) -> void:
	var p: Dictionary = Game.player
	var drop := mini(coins, int(p["coins"]))
	p["coins"] -= drop
	var text := "Your side lost... You dropped %d coins" % drop
	if item != "" and Game.item_count(item) > 0:
		Game.add_item(item, -1)
		text += " and %s" % Game.with_article(Game.ITEMS[item]["name"])
	message.text = text + "."
	for a in allies:
		if _mine(a):
			a["node"].modulate.a = 0.4
	await _wait(2.4)
	_leave("lost")


## The server: someone left (ran away, quit or lost the connection).
func _on_left(pid: String, fled: bool) -> void:
	if not players.has(pid) or over:
		return
	if is_host and players[pid]["status"] in ["in", "out"]:
		players[pid]["status"] = "fled" if fled else "left"
		for a in _sim:
			if a["owner"] == pid:
				a["gone"] = true
	if not fled:
		message.text = "%s left the battle!" % players[pid]["name"]
	_hide_player(pid)


## The duel ended from the server's side: the host left ("host_left", winner
## is the side that wins, or "" for nobody), or it was called off.
func _on_called_off(result: String, winner: String) -> void:
	if over:
		return
	if result != "host_left" or winner == "" or not _seen_setup:
		_called_off("The battle was called off.")
		return
	over = true
	if winner == my_side:
		var pot := 0
		var xp := 0
		var mates := 0
		for pid in players:
			if players[pid]["side"] == winner:
				mates += 1
			else:
				pot += Game.pvp_drop(int(players[pid]["coins"]))
				xp += 4 + 2 * int(players[pid]["level"])
		message.text = "%s left the battle!" % players.get(host_id, {}).get("name", "They")
		await _wait(1.2)
		await _victory(pot / maxi(1, mates), xp, [])
	else:
		await _defeat(Game.pvp_drop(int(Game.player["coins"])), "")


func _called_off(text: String) -> void:
	if over:
		return
	over = true
	blocks.visible = false
	targets.visible = false
	menu.visible = false
	message.text = text
	await _wait(1.2)
	_leave("fled")


## Your connection dropped: the server tells the others you left, so it
## counts as losing here too.
func _connection_lost() -> void:
	if over:
		return
	over = true
	blocks.visible = false
	targets.visible = false
	menu.visible = false
	var drop: int = Game.pvp_drop(Game.player["coins"])
	Game.player["coins"] -= drop
	message.text = "Lost the connection... It counts as a loss (-%d coins)." % drop
	await _wait(2.2)
	_leave("lost")


func _leave(result: String) -> void:
	finished.emit(result)
	if Game.pending_battle.get("pvp", {}).get("no_exit", false):
		return
	Net.duel_inbox.clear()
	super(result)
