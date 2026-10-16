class_name Quests
extends RefCounted
## A short questline for each side. One NPC gives each line ("giver", a talk
## id from dialogue.json): talk to them to get a step, do it, then go back to
## them for the reward and the next step. A "talk" step is done by talking to
## someone else instead (their talk id), and the line's last step has the
## biggest reward.
##
## Goals:
##   defeat  win battles against `count` enemies (only on `map`, if given)
##   team    have `count` partners or recruits (party and home together)
##   talk    talk to `talk` (a talk id); they say `say` instead of their usual lines
##   boss    beat any boss (rematches count)
##   level   reach level `count`
##
## Saved as player["quests"][side] = {"step", "count", "done", "finished"}.
## Progress notes queue in Game.quest_notes; the world shows them in the chat.

const LINES := {
	"good": {
		"name": "Toadsworth's Errands",
		"giver": "toadsworth",
		"giver_name": "Toadsworth",
		"home": "Beanbean Castle Town",
		"steps": [
			{"goal": "defeat", "count": 5, "map": "outskirts", "text": "Defeat 5 enemies in the Beanbean Outskirts.",
				"ask": ["Ah, a hero! The Beanbean Outskirts are crawling with ruffians, and I daren't go to the market.",
					"Would you clear out 5 of them for an old Toad?"],
				"reward": {"coins": 30, "xp": 15, "items": {"mushroom": 2}},
				"thanks": "Splendid! The road to the market is safe again. Do take these."},
			{"goal": "team", "count": 1, "text": "Get a partner to join you.",
				"ask": ["No hero travels alone! Talk to the folk around town and the Outskirts.",
					"Ask someone to join your party, then come and tell me."],
				"reward": {"coins": 40, "xp": 20, "items": {"syrup": 2}},
				"thanks": "A fine companion! The two of you will go far."},
			{"goal": "talk", "talk": "hoohoo_greeter", "text": "Take Toadsworth's letter to the greeter in Hoohoo Village.",
				"ask": ["Might I trouble you with a letter? It's for my pen pal in Hoohoo Village.",
					"Go east through the Outskirts, past Stardust Fields. The greeter by the village gate is the one."],
				"say": ["Hoo? A letter from Toadsworth! Hoohoo, how lovely!", "Tell him the carvings he asked about are nearly done. Hoo!"],
				"reward": {"coins": 60, "xp": 40, "items": {"super_mushroom": 2}},
				"thanks": "The carvings are nearly done? Wonderful news! You've been ever so helpful."},
			{"goal": "boss", "text": "Beat one of the bosses.",
				"ask": ["One last thing. Fearsome bosses roam the kingdom, and folk are afraid to travel.",
					"Beat one of them, and the whole town will sleep easier!"],
				"reward": {"coins": 150, "xp": 80, "items": {"heart_badge": 1, "ultra_mushroom": 1}},
				"thanks": "You did it! Here, a Heart Badge, the finest reward an old Toad can give. Thank you, hero!"},
		],
	},
	"evil": {
		"name": "Orders from the Border Bro",
		"giver": "bowser_gatekeeper",
		"giver_name": "Border Bro",
		"home": "Bowser's Castle",
		"steps": [
			{"goal": "team", "count": 1, "text": "Recruit an enemy to your side.",
				"ask": ["New recruit, eh? Bowser's army needs muscle.",
					"Beat an enemy out in the Outskirts and ask it to join you. Then report back!"],
				"reward": {"coins": 30, "xp": 15, "items": {"mushroom": 2}},
				"thanks": "Ha! Now that's a minion. Here's your pay."},
			{"goal": "defeat", "count": 6, "map": "outskirts", "text": "Defeat 6 enemies in the Beanbean Outskirts.",
				"ask": ["Some of the locals in the Outskirts won't bow to Bowser.",
					"Teach 6 of them a lesson!"],
				"reward": {"coins": 40, "xp": 20, "items": {"red_pepper": 1}},
				"thanks": "They'll think twice before crossing Bowser now. Nice work!"},
			{"goal": "talk", "talk": "border_bro", "text": "Get the password from the Border Bro in Stardust Fields.",
				"ask": ["My brother guards the path to Hoohoo Village, in Stardust Fields east of the Outskirts.",
					"He's got this week's secret password. Go get it from him."],
				"say": ["Psst. You're from the castle? The password is... \"Koopa Kopa Kabana\".", "Don't tell the Bros on the good side!"],
				"reward": {"coins": 60, "xp": 40, "items": {"super_mushroom": 2}},
				"thanks": "\"Koopa Kopa Kabana\"... that's the one! You're a natural."},
			{"goal": "boss", "text": "Beat one of the bosses.",
				"ask": ["Final test. There are bosses out there who think they're tougher than Bowser.",
					"Beat one! Maybe it'll even join you."],
				"reward": {"coins": 150, "xp": 80, "items": {"power_badge": 1, "ultra_mushroom": 1}},
				"thanks": "You beat a boss?! Bowser himself will hear about this. Take this Power Badge, general!"},
		],
	},
}


## Your quest state on your current side (made if missing).
static func state() -> Dictionary:
	var p: Dictionary = Game.player
	if typeof(p.get("quests")) != TYPE_DICTIONARY:
		p["quests"] = {}
	var side: String = p.get("side", "good")
	if typeof(p["quests"].get(side)) != TYPE_DICTIONARY:
		p["quests"][side] = {"step": -1, "count": 0, "done": false, "finished": false}
	var s: Dictionary = p["quests"][side]
	for key in ["step", "count"]:
		s[key] = int(s.get(key, 0))
	return s


static func line() -> Dictionary:
	return LINES.get(Game.player.get("side", "good"), LINES["good"])


## The step you're on, or {} if you haven't started or you're finished.
static func current() -> Dictionary:
	var s := state()
	var steps: Array = line()["steps"]
	if s.get("finished", false) or s["step"] < 0 or s["step"] >= steps.size():
		return {}
	return steps[s["step"]]


## True if the line's giver has something for you (a new step or a reward).
static func giver_has_news() -> bool:
	var s := state()
	return not s.get("finished", false) and (s["step"] < 0 or s.get("done", false))


## What the pause menu's Quests page says.
static func summary() -> String:
	var l := line()
	var s := state()
	if s.get("finished", false):
		return "%s: all done! Thanks for your help." % l["name"]
	if s["step"] < 0:
		return "%s: talk to %s in %s to start." % [l["name"], l["giver_name"], l["home"]]
	var step := current()
	var text: String = "%s (%d/%d): %s" % [l["name"], s["step"] + 1, l["steps"].size(), step["text"]]
	if s.get("done", false):
		return text + " Done! Go back to %s." % l["giver_name"]
	if step["goal"] == "defeat":
		text += " (%d/%d)" % [s["count"], step["count"]]
	return text


# --- Progress -------------------------------------------------------------------

## A battle was won: `types` are the enemies beaten, on `map`.
static func on_defeat(types: Array, map: String) -> void:
	var step := current()
	if step.is_empty() or step["goal"] != "defeat" or state().get("done", false):
		return
	if step.has("map") and step["map"] != map:
		return
	var foes := types.filter(func(t): return not Game.BOSSES.has(str(t)))
	if foes.is_empty():
		return
	var s := state()
	s["count"] = mini(s["count"] + foes.size(), step["count"])
	if s["count"] >= step["count"]:
		_step_done()
	else:
		_note("Quest: %d/%d enemies beaten." % [s["count"], step["count"]])


static func on_boss() -> void:
	var step := current()
	if not step.is_empty() and step["goal"] == "boss" and not state().get("done", false):
		_step_done()


## Re-checks goals that depend on what you have (team size, level).
static func check() -> void:
	if Game.player.is_empty():
		return
	var step := current()
	if step.is_empty() or state().get("done", false):
		return
	match step["goal"]:
		"team":
			if Game.player.get("party", []).size() + Game.bench().size() >= int(step["count"]):
				_step_done()
		"level":
			if int(Game.player.get("level", 1)) >= int(step["count"]):
				_step_done()


static func _step_done() -> void:
	state()["done"] = true
	_note("Quest step done! Go back to %s for your reward." % line()["giver_name"])


static func _note(text: String) -> void:
	Game.quest_notes.append(text)


# --- Talking ----------------------------------------------------------------------

## What talking to `talk_id` should do for your quest, if anything:
##   {"kind": "offer", "pages": [...]}   the giver offers the next step (Accept / Not now)
##   {"kind": "reward", "pages": [...]}  the giver hands over the reward
##   {"kind": "remind", "pages": [...]}  the giver reminds you what to do
##   {"kind": "talk", "pages": [...]}    a talk step's NPC (finishes the step)
## {} means talk as usual.
static func talk_event(talk_id: String) -> Dictionary:
	var l := line()
	var s := state()
	if s.get("finished", false):
		return {}
	var step := current()
	if talk_id == l["giver"]:
		if s["step"] < 0:
			return {"kind": "offer", "pages": l["steps"][0]["ask"]}
		if s.get("done", false):
			var pages: Array = [step["thanks"]]
			var next: int = s["step"] + 1
			if next < l["steps"].size():
				pages += l["steps"][next]["ask"]
			return {"kind": "reward", "pages": pages}
		return {"kind": "remind", "pages": ["Remember: %s" % step["text"]]}
	if not step.is_empty() and step["goal"] == "talk" and step["talk"] == talk_id and not s.get("done", false):
		return {"kind": "talk", "pages": step["say"]}
	return {}


## Starts the line's first step (you accepted it).
static func accept() -> void:
	var s := state()
	if s["step"] < 0:
		s["step"] = 0
		s["count"] = 0
		s["done"] = false
	check()


## The talk step's NPC was talked to.
static func talked() -> void:
	_step_done()


## Gives the current step's reward and moves on. Returns the lines to show.
static func claim() -> Array:
	var s := state()
	var step := current()
	if step.is_empty() or not s.get("done", false):
		return []
	var r: Dictionary = step.get("reward", {})
	var out: Array = []
	var coins := int(r.get("coins", 0))
	var xp := int(r.get("xp", 0))
	Game.player["coins"] = int(Game.player["coins"]) + coins
	var levels := Game.gain_xp(xp)
	out.append("Got %d coins and %d XP!" % [coins, xp])
	var items: Dictionary = r.get("items", {})
	for id in items:
		var got := Game.add_item(id, int(items[id]))
		if got > 0:
			var item_name: String = Game.goods(id).get("name", id)
			out.append("Got %s!" % (Game.with_article(item_name) if got == 1 else "%d %ss" % [got, item_name]))
	if levels > 0:
		out.append("Level up! %s is now level %d!" % [Game.character_name(), Game.player["level"]])
	s["step"] += 1
	s["count"] = 0
	s["done"] = false
	if s["step"] >= line()["steps"].size():
		s["finished"] = true
		out.append("%s complete!" % line()["name"])
	else:
		check()  # the next step may already be done (you have a partner, say)
	return out
