class_name DialogueData
extends RefCounted
## What NPCs say, read from res://data/dialogue.json. Each map NPC has a
## `talk` id (MAPS in game.gd); the file maps ids to an entry:
##
##   "palace_guard": {
##     "name": "Castle Guard",                  optional, else the NPC's own name
##     "branches": [                            the first one whose "if" matches is used
##       {"if": {"side": "evil"}, "say": ["Halt! ..."]},
##       {"if": {"min_level": 5}, "say": ["...", "..."], "random": true},
##       {"say": ["Page one.", "Page two."],
##        "choices": [{"text": "Ask to join", "do": "recruit"},
##                    {"text": "Tell me more", "say": ["..."]},
##                    {"text": "Never mind"}]}
##     ]}
##
## "say" pages are shown one after another ("random": true shows just one of
## them). With "choices", the last page stays up as the question. A choice can
## "say" more pages and/or "do": "recruit" (partners), "shop" (sells the
## branch's "shop" list: [{"item": "mushroom", "count": 1, "price": 8}]) or
## "heal" (full HP and SP for you and your party).
## Conditions: side ("good"/"evil"), min_level, max_level, party_full (bool).
## In any text, {name} becomes the player's name and {character} their character.

const PATH := "res://data/dialogue.json"
const CONDITIONS := ["side", "min_level", "max_level", "party_full"]
const ACTIONS := ["recruit", "shop", "heal"]

static var _data := {}


static func all() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Can't read " + PATH)
			return {}
		_data = parsed
	return _data


static func has(id: String) -> bool:
	return all().has(id)


## The first branch of dialogue `id` whose conditions match player `p`.
static func pick(id: String, p: Dictionary) -> Dictionary:
	var entry: Dictionary = all().get(id, {})
	for branch in entry.get("branches", []):
		if matches(branch.get("if", {}), p):
			return branch
	return {"say": ["..."]}


static func matches(cond: Dictionary, p: Dictionary) -> bool:
	for key in cond:
		var want = cond[key]
		match key:
			"side":
				if p.get("side", "") != want:
					return false
			"min_level":
				if int(p.get("level", 1)) < int(want):
					return false
			"max_level":
				if int(p.get("level", 1)) > int(want):
					return false
			"party_full":
				if (p.get("party", []).size() >= Game.MAX_PARTY) != bool(want):
					return false
			_:
				push_warning("Unknown dialogue condition: " + str(key))
				return false
	return true


## The name on the speech balloon's tab.
static func speaker(id: String, npc_id: String) -> String:
	var entry: Dictionary = all().get(id, {})
	if entry.has("name"):
		return str(entry["name"])
	for table in [Game.NPCS, Game.PARTNERS, Game.CHARACTERS, Game.ENEMIES]:
		if table.has(npc_id):
			return table[npc_id]["name"]
	return ""


## The pages to show for a branch (one at random if it says "random").
static func pages(branch: Dictionary) -> Array:
	var all_pages: Array = branch.get("say", [])
	if branch.get("random", false) and not all_pages.is_empty():
		return [all_pages.pick_random()]
	return all_pages


static func fill(text: String) -> String:
	return text.replace("{name}", Game.username()).replace("{character}", Game.character_name())
