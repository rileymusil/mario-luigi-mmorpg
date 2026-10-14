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
## "say" more pages and/or "do": "recruit" (partners), "shop" (a Buy / Sell
## counter selling the branch's "shop" list: [{"item": "mushroom"},
## {"item": "mushroom", "count": 3, "price": 21, "thanks": "..."}]; price
## defaults to the item's own (Game.ITEMS) times the branch's "markup") or
## "heal" (full HP and SP for you and your party).
## Conditions: side ("good"/"evil"), min_level, max_level, party_full (bool).
## In any text, {name} becomes the player's name and {character} their character.
##
## Partners (Game.PARTNERS) need no entry: they say their `line` and offer to
## join, and back away from evil players. An entry with their id overrides that.

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
	return not entry(id).is_empty()


## Dialogue `id` from the file, or the standard one for a partner.
static func entry(id: String) -> Dictionary:
	if all().has(id):
		return all()[id]
	if Game.PARTNERS.has(id):
		return {"branches": [
			{"if": {"side": "evil"}, "say": ["Eek! You're one of Bowser's bunch! Stay back!"]},
			{"say": [Game.PARTNERS[id].get("line", "Want to team up?")],
			 "choices": [{"text": "Ask to join", "do": "recruit"}, {"text": "Never mind"}]},
		]}
	return {}


## The first branch of dialogue `id` whose conditions match player `p`.
static func pick(id: String, p: Dictionary) -> Dictionary:
	for branch in entry(id).get("branches", []):
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
	var e := entry(id)
	if e.has("name"):
		return str(e["name"])
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
