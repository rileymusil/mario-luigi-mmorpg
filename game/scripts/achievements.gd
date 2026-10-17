class_name Achievements
extends RefCounted
## Goals to work towards, each with a reward (badges for the big ones). The
## world checks them every half second (Achievements.check) and puts a note
## in the chat when you earn one; the pause menu's Quests page lists them.
## Earned ids are saved in player["achievements"]. Counters they read:
## wins (battles), level, bosses, recruited, pvp_wins, quests (story lines
## finished), dailies_done, trades, visited (map ids), bounties, fish_caught,
## rope_best.

const LIST := [
	{"id": "first_win", "name": "First Victory", "text": "Win a battle.", "reward": {"coins": 20}},
	{"id": "wins_50", "name": "Seasoned Fighter", "text": "Win 50 battles.", "reward": {"items": {"super_mushroom": 3}}},
	{"id": "wins_200", "name": "Battle Legend", "text": "Win 200 battles.", "reward": {"items": {"guard_badge": 1}}},
	{"id": "level_10", "name": "Rising Star", "text": "Reach level 10.", "reward": {"items": {"sp_badge": 1}}},
	{"id": "level_25", "name": "Superstar", "text": "Reach level 25.", "reward": {"items": {"great_badge": 1}}},
	{"id": "recruit_1", "name": "Teamwork", "text": "Get a partner or recruit.", "reward": {"items": {"syrup": 2}}},
	{"id": "recruit_10", "name": "Full House", "text": "Get 10 partners or recruits.", "reward": {"items": {"heart_badge": 1}}},
	{"id": "boss_1", "name": "Boss Buster", "text": "Beat a boss.", "reward": {"items": {"spiny_badge": 1}}},
	{"id": "boss_all", "name": "Boss Tower Champion", "text": "Beat every boss.", "reward": {"coins": 300, "items": {"one_up": 2}}},
	{"id": "pvp_1", "name": "Duelist", "text": "Win a PvP duel.", "reward": {"coins": 50}},
	{"id": "pvp_10", "name": "Champion of the Week", "text": "Win 10 PvP duels.", "reward": {"items": {"power_badge": 1}}},
	{"id": "bounty_1", "name": "Bounty Hunter", "text": "Collect a bounty.", "reward": {"coins": 100}},
	{"id": "story", "name": "Hero's Tale", "text": "Finish your side's story quests.", "reward": {"coins": 100}},
	{"id": "daily_7", "name": "Helping Hand", "text": "Finish 7 daily quests.", "reward": {"items": {"ultra_mushroom": 2}}},
	{"id": "trade_1", "name": "Trader", "text": "Complete a trade.", "reward": {"coins": 30}},
	{"id": "angler", "name": "Angler", "text": "Catch 20 fish at the pier.", "reward": {"coins": 80}},
	{"id": "rope_50", "name": "Jump Rope Pro", "text": "Make 50 jumps in a row.", "reward": {"items": {"ultra_mushroom": 2}}},
	{"id": "explorer", "name": "Explorer", "text": "Visit every area outside the Boss Tower.", "reward": {"items": {"super_syrup": 2}}},
]


## Areas the Explorer achievement needs (every map but the Boss Tower's floors).
static func explore_maps() -> Array:
	return Game.MAPS.keys().filter(func(m): return not str(m).begins_with("boss_tower"))


## How far along you are on one achievement: [have, need].
static func progress(id: String) -> Array:
	var p: Dictionary = Game.player
	match id:
		"first_win":
			return [mini(int(p.get("wins", 0)), 1), 1]
		"wins_50":
			return [int(p.get("wins", 0)), 50]
		"wins_200":
			return [int(p.get("wins", 0)), 200]
		"level_10":
			return [int(p.get("level", 1)), 10]
		"level_25":
			return [int(p.get("level", 1)), 25]
		"recruit_1":
			return [_recruited(), 1]
		"recruit_10":
			return [_recruited(), 10]
		"boss_1":
			return [mini(_bosses_beaten(), 1), 1]
		"boss_all":
			return [_bosses_beaten(), Game.BOSSES.size()]
		"pvp_1":
			return [int(p.get("pvp_wins", 0)), 1]
		"pvp_10":
			return [int(p.get("pvp_wins", 0)), 10]
		"bounty_1":
			return [int(p.get("bounties", 0)), 1]
		"story":
			return [int(p.get("quests", {}).get(p.get("side", "good"), {}).get("finished", false)) if typeof(p.get("quests")) == TYPE_DICTIONARY else 0, 1]
		"daily_7":
			return [int(p.get("dailies_done", 0)), 7]
		"trade_1":
			return [int(p.get("trades", 0)), 1]
		"angler":
			return [int(p.get("fish_caught", 0)), 20]
		"rope_50":
			return [int(p.get("rope_best", 0)), 50]
		"explorer":
			var seen: Array = p.get("visited", []) if typeof(p.get("visited")) == TYPE_ARRAY else []
			return [explore_maps().filter(func(m): return m in seen).size(), explore_maps().size()]
	return [0, 1]


## Partners and recruits you've ever had (saves from before the counter: at
## least everyone you have now).
static func _recruited() -> int:
	return maxi(int(Game.player.get("recruited", 0)), Game.player.get("party", []).size() + Game.bench().size())


static func _bosses_beaten() -> int:
	var b = Game.player.get("bosses", {})
	if typeof(b) != TYPE_DICTIONARY:
		return 0
	return Game.BOSSES.keys().filter(func(id): return int(b.get(id, 0)) > 0).size()


static func earned() -> Array:
	if typeof(Game.player.get("achievements")) != TYPE_ARRAY:
		Game.player["achievements"] = []
	return Game.player["achievements"]


## Notes that you've been somewhere (for Explorer).
static func visit(map_id: String) -> void:
	if typeof(Game.player.get("visited")) != TYPE_ARRAY:
		Game.player["visited"] = []
	if not map_id in Game.player["visited"]:
		Game.player["visited"].append(map_id)


## Hands out every achievement you've just reached. Returns how many.
static func check() -> int:
	if Game.player.is_empty():
		return 0
	var got := 0
	for a in LIST:
		if a["id"] in earned():
			continue
		var pr := progress(a["id"])
		if pr[0] < pr[1]:
			continue
		earned().append(a["id"])
		got += 1
		Game.quest_notes.append("Achievement: %s! %s" % [a["name"], _give(a["reward"])])
	if got > 0:
		Game.save()
	return got


static func _give(r: Dictionary) -> String:
	var parts: Array = []
	if r.has("coins"):
		Game.player["coins"] = int(Game.player["coins"]) + int(r["coins"])
		parts.append("%d coins" % r["coins"])
	var items: Dictionary = r.get("items", {})
	for id in items:
		var got := Game.add_item(id, int(items[id]))
		var item_name: String = Game.goods(id).get("name", id)
		if got > 0:
			parts.append(Game.with_article(item_name) if got == 1 else "%d %ss" % [got, item_name])
	return "Got " + " and ".join(parts) + "." if not parts.is_empty() else ""


## The list as pages for LeadersScreen.show_pages.
static func pages() -> Array:
	var rows: Array = []
	for a in LIST:
		var done: bool = a["id"] in earned()
		var pr := progress(a["id"])
		var value := "Done!" if done else "%d/%d" % [mini(pr[0], pr[1]), pr[1]]
		rows.append([a["text"], value, Color(1, 0.9, 0.3) if done else Color(0.85, 0.85, 0.9)])
	var out: Array = []
	var per_page := 8
	var total := ceili(rows.size() / float(per_page))
	for i in total:
		out.append({"title": "Achievements", "rows": rows.slice(i * per_page, (i + 1) * per_page),
			"note": "%d of %d earned" % [earned().size(), LIST.size()]})
	return out
