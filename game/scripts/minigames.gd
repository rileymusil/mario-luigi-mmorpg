class_name Minigames
extends RefCounted
## The prizes and daily limits of the minigames; the games themselves are
## ui/fishing_screen.gd (the fisher Toad on the Outskirts Pier) and
## ui/jump_rope_screen.gd (the Beanish kid in Castle Town).
## Saved in player["fishing"] = {day, casts}, player["rope"] = {day, tiers},
## and the counters player["fish_caught"] and player["rope_best"].

const CASTS_PER_DAY := 10
## How fast you have to reel in after the bite (seconds): faster is better.
const GREAT_REEL := 0.3
const GOOD_REEL := 0.6

## What you can catch: weight (how often), how good the reel has to be, prize.
const FISH := [
	{"name": "Cheep Cheep", "weight": 40, "reel": "any", "coins": 8},
	{"name": "Spiny Cheep", "weight": 22, "reel": "any", "coins": 4, "item": "mushroom"},
	{"name": "Blooper", "weight": 18, "reel": "any", "coins": 4, "item": "syrup"},
	{"name": "Big Cheep", "weight": 14, "reel": "good", "coins": 30, "item": "super_mushroom"},
	{"name": "Golden Cheep", "weight": 6, "reel": "great", "coins": 100, "item": "ultra_mushroom"},
]

## Jump rope: coins for every ROPE_COINS_EVERY jumps, and a prize the first
## time each day you reach each tier.
const ROPE_COINS_EVERY := 2
const ROPE_TIERS := [
	{"jumps": 20, "item": "super_mushroom"},
	{"jumps": 40, "item": "super_syrup"},
	{"jumps": 60, "item": "ultra_mushroom"},
]


static func _today_state(key: String) -> Dictionary:
	var s = Game.player.get(key, {})
	if typeof(s) != TYPE_DICTIONARY or str(s.get("day", "")) != Quests.today():
		s = {"day": Quests.today()}
		Game.player[key] = s
	return s


static func casts_left() -> int:
	return maxi(0, CASTS_PER_DAY - int(_today_state("fishing").get("casts", 0)))


## One cast. reel: seconds from the bite to your button press, or < 0 if you
## missed it (too early or too late). Returns {fish, text}; fish is "" when it
## got away. Uses up one of today's casts either way.
static func cast(reel: float, roll := -1.0) -> Dictionary:
	var s := _today_state("fishing")
	s["casts"] = int(s.get("casts", 0)) + 1
	if reel < 0.0:
		return {"fish": "", "text": "It got away..."}
	var grade := "great" if reel <= GREAT_REEL else ("good" if reel <= GOOD_REEL else "any")
	var pool: Array = FISH.filter(func(f): return f["reel"] == "any" or (f["reel"] == "good" and grade != "any") or grade == "great")
	var total := 0
	for f in pool:
		total += int(f["weight"])
	var pick := (roll if roll >= 0.0 else randf()) * total
	var fish: Dictionary = pool.back()
	for f in pool:
		pick -= int(f["weight"])
		if pick < 0.0:
			fish = f
			break
	Game.player["fish_caught"] = int(Game.player.get("fish_caught", 0)) + 1
	Game.player["coins"] = clampi(int(Game.player.get("coins", 0)) + int(fish["coins"]), 0, 99999)
	var got := "%d coins" % fish["coins"]
	if fish.has("item") and Game.add_item(fish["item"]) > 0:
		got += " and " + Game.with_article(Game.goods(fish["item"]).get("name", fish["item"]))
	return {"fish": fish["name"], "text": "You caught %s! Got %s." % [Game.with_article(fish["name"]), got]}


## Pays out a jump rope game of `jumps` jumps. Returns the lines to show.
static func rope_prize(jumps: int) -> Array:
	var lines: Array = []
	var coins := jumps / ROPE_COINS_EVERY
	if coins > 0:
		Game.player["coins"] = clampi(int(Game.player.get("coins", 0)) + coins, 0, 99999)
		lines.append("%d jumps! Got %d coins." % [jumps, coins])
	else:
		lines.append("%d jumps. Keep at it!" % jumps)
	var s := _today_state("rope")
	var tiers: Array = s.get("tiers", [])
	for t in ROPE_TIERS:
		if jumps >= int(t["jumps"]) and not int(t["jumps"]) in tiers and Game.add_item(t["item"]) > 0:
			tiers.append(int(t["jumps"]))
			lines.append("%d jumps in one go: here's %s!" % [t["jumps"], Game.with_article(Game.goods(t["item"]).get("name", t["item"]))])
	s["tiers"] = tiers
	if jumps > int(Game.player.get("rope_best", 0)):
		if int(Game.player.get("rope_best", 0)) > 0:
			lines.append("A new record!")
		Game.player["rope_best"] = jumps
	return lines
