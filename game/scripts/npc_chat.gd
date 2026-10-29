class_name NpcChat
extends RefCounted
## In-game NPC dialogue knowledge base, interactive free-chat response engine,
## sentiment & friendship meter, gift-giving system, and rumors/secret passwords.

const TOPICS := {
	"toadsworth": {
		"name": "Toadsworth",
		"questions": ["Princess Peach", "Battle Advice", "Kingdom Quests", "Nothing"],
		"answers": [
			"Good heavens, Master Mario! Princess Peach is resting safely, but do mind the rogues in the Outskirts!",
			"Bless my spectacles! In battle, timing is paramount! Press right as your strike lands for extra power, and always carry Mushrooms!",
			"Splendid! Talk to folk across the Outskirts and clear out the ruffians—the realm relies on you!",
			"Toodle-oo, dear boy! Stay safe out there!"
		]
	},
	"e_gadd": {
		"name": "Prof. E. Gadd",
		"questions": ["New Inventions", "Ghostly Boos", "Gear Upgrades", "Nothing"],
		"answers": [
			"Gya-ha-ha! I'm currently calibrating a new spectral vacuum mechanism! Pure genius, I tell you!",
			"Great jumpin' jellybeans! Keep your eyes peeled for Boos—their ethereal residue powers my finest gadgets!",
			"Ho ho! Bring me rare Chuckola beans and volcanic stones, and we can craft marvelous badges!",
			"Off to the lab I go! Science never sleeps!"
		]
	},
	"bowser_gatekeeper": {
		"name": "Border Bro",
		"questions": ["Bowser's Army", "Battle Streaks", "Password", "Nothing"],
		"answers": [
			"Bwahaha! Bowser's Castle is the toughest fortress around. Only the strongest minions get recruited!",
			"Win consecutive battles out in the Outskirts to build your damage streak—Bowser rewards power!",
			"The password is 'Koopa Kopa Kabana'! Don't let the good side hear you!",
			"Move along, recruit!"
		]
	}
}

## Favorite items per NPC category and the milestone gear reward unlocked at 50+ Friendship.
const GIFT_PREFS := {
	"toadsworth": {
		"favorites": ["mushroom", "super_mushroom", "ultra_mushroom", "max_mushroom", "refreshing_herb"],
		"reward_gear": "heart_badge",
		"thanks_fav": "Good heavens! A pristine %s?! How remarkably thoughtful of you, dear boy! My mushroom cap is positively brimming with joy!",
		"thanks_normal": "Why thank you, Master {character}! This %s will certainly come in handy around the castle."
	},
	"e_gadd": {
		"favorites": ["chuckola_cola", "syrup", "super_syrup", "max_syrup"],
		"reward_gear": "sp_badge",
		"thanks_fav": "Gya-ha-ha! Great jumpin' jellybeans! This %s has the exact molecular density I needed for my lab experiments!",
		"thanks_normal": "Ho ho! A %s! I'll toss this right into the spectral analyzer!"
	},
	"bowser": {
		"favorites": ["red_pepper", "fire_flower", "bob_omb_item", "ultra_mushroom"],
		"reward_gear": "spiny_badge",
		"thanks_fav": "GWAHAHA! Now THAT'S a tribute fit for the Koopa King! This %s packs some serious heat!",
		"thanks_normal": "Bwahaha! A %s? Not bad, recruit! Keep bringing tribute to Bowser's army!"
	},
	"cafe": {
		"favorites": ["chuckola_cola", "nut", "super_nut", "syrup", "super_syrup"],
		"reward_gear": "guard_badge",
		"thanks_fav": "Aha! Ha-ha-ha! This %s has world-class aroma! The Starbeans and Chuckola barrels are bubbling with delight!",
		"thanks_normal": "Ooh, thank you for the %s! That'll pair wonderfully with a fresh roast!"
	},
	"shop": {
		"favorites": ["chuckola_cola", "super_mushroom", "ultra_mushroom", "super_syrup"],
		"reward_gear": "power_badge",
		"thanks_fav": "Whoa, a top-shelf %s! You really know how to treat a merchant! Enjoy a special friend discount at my counter!",
		"thanks_normal": "Thanks for the %s! I always appreciate a generous customer!"
	},
	"default": {
		"favorites": ["mushroom", "super_mushroom", "chuckola_cola", "nut"],
		"reward_gear": "heart_badge",
		"thanks_fav": "Whoa, for me?! I love %s! You're the best traveler in the Beanbean Kingdom!",
		"thanks_normal": "Thanks so much for the %s, {character}! That's mighty kind of you!"
	}
}

## Riddles NPCs can ask and the keywords that solve them.
const RIDDLES := [
	{
		"q": "What has a red or green cap, heals 10 HP, and grows all across the Kingdom?",
		"answers": ["mushroom", "mushrooms", "super mushroom"],
		"hint": "Think of the classic healing snack you carry in your bag!"
	},
	{
		"q": "I bubble in oak barrels for 1,000 years and only taste sweet when you tell me a joke. What am I?",
		"answers": ["chuckola", "cola", "chuckola cola", "soda", "wine"],
		"hint": "Master Chucklerator brews it in the woods!"
	},
	{
		"q": "I sleep inside Beanbean Castle and grant wishes only to a pure voice. What am I?",
		"answers": ["beanstar", "bean star", "the beanstar"],
		"hint": "Queen Bean guards this sacred star!"
	},
	{
		"q": "Press Z right as you land on a foe's head to deal double damage. What is this technique called?",
		"answers": ["action command", "timed hit", "jump", "excellent", "timing"],
		"hint": "It's the heart of Superstar Saga combat timing!"
	}
]

## Rumors dropped by friendly NPCs.
const RUMORS := [
	"Rumor has it that telling a hilarious joke or saying the daily secret code 'CHUCKOLA-99' in Free Chat unlocks a hidden stash of coins!",
	"Folk say if you reach Good Friend status (♥♥♡, 50+ Affinity) with townsfolk by gifting them snacks, they'll hand you rare Badges!",
	"Merchants in Beanbean Castle Town give up to a 25% discount on all items and gear if you befriend them first!",
	"Wandering partners in town are guaranteed to join your party on the first ask if you give them a gift they like!",
	"Deep in the Teehee Ruins, a golden prize block refills every single day at midnight UTC with Ultra Mushrooms and coins!"
]


static func has_topics(talk_id: String) -> bool:
	return TOPICS.has(talk_id)


static func get_topics(talk_id: String) -> Dictionary:
	return TOPICS.get(talk_id, {})


# --- Friendship & Affinity System --------------------------------------------

static func _npc_key(talk_id: String, speaker: String) -> String:
	var k := talk_id.strip_edges().to_lower()
	if k == "":
		k = speaker.strip_edges().to_lower()
	return k


static func get_affinity(talk_id: String, speaker := "") -> int:
	var p: Dictionary = Game.player
	var aff = p.get("npc_affinity", {})
	if typeof(aff) != TYPE_DICTIONARY:
		return 0
	return clampi(int(aff.get(_npc_key(talk_id, speaker), 0)), 0, 100)


static func add_affinity(talk_id: String, speaker: String, delta: int) -> int:
	var p: Dictionary = Game.player
	if typeof(p.get("npc_affinity")) != TYPE_DICTIONARY:
		p["npc_affinity"] = {}
	var key := _npc_key(talk_id, speaker)
	var before := get_affinity(talk_id, speaker)
	var after := clampi(before + delta, 0, 100)
	p["npc_affinity"][key] = after
	Game.save()
	return after - before


static func hearts_text(affinity: int) -> String:
	if affinity >= 80:
		return "♥♥♥"
	if affinity >= 50:
		return "♥♥♡"
	if affinity >= 20:
		return "♥♡♡"
	return "♡♡♡"


static func rank_title(affinity: int) -> String:
	if affinity >= 80:
		return "Best Friend"
	if affinity >= 50:
		return "Good Friend"
	if affinity >= 20:
		return "Buddy"
	return "Stranger"


static func status_tag(talk_id: String, speaker := "") -> String:
	var aff := get_affinity(talk_id, speaker)
	return "%s %d/100 (%s)" % [hearts_text(aff), aff, rank_title(aff)]


## Shop discount multiplier based on friendship with the shopkeeper (up to 25% off).
static func shop_discount_multiplier(talk_id: String, speaker := "") -> float:
	var aff := get_affinity(talk_id, speaker)
	if aff >= 80:
		return 0.75
	if aff >= 50:
		return 0.80
	if aff >= 20:
		return 0.90
	return 1.0


static func shop_discount_percent(talk_id: String, speaker := "") -> int:
	return int(round((1.0 - shop_discount_multiplier(talk_id, speaker)) * 100.0))


## Bonus added to partner recruitment probability (0.0 to +1.0) based on friendship.
static func recruit_bonus(talk_id: String, speaker := "") -> float:
	var aff := get_affinity(talk_id, speaker)
	if aff >= 80:
		return 1.0  # Guaranteed recruit!
	if aff >= 50:
		return 0.35
	if aff >= 20:
		return 0.15
	return 0.0


# --- Gift-Giving System ------------------------------------------------------

static func _gift_profile(talk_id: String, speaker: String) -> Dictionary:
	var tid := talk_id.to_lower()
	var spk := speaker.to_lower()
	if "toadsworth" in tid or "toadsworth" in spk:
		return GIFT_PREFS["toadsworth"]
	if "e_gadd" in tid or "gadd" in spk or "professor" in spk:
		return GIFT_PREFS["e_gadd"]
	if "bowser" in tid or "border" in tid or "koopa" in tid:
		return GIFT_PREFS["bowser"]
	if "barista" in tid or "cafe" in tid or "chuck" in tid:
		return GIFT_PREFS["cafe"]
	if "shop" in tid or "store" in tid or "trader" in tid:
		return GIFT_PREFS["shop"]
	return GIFT_PREFS["default"]


## Processes giving `item_id` to an NPC. Deducts 1 of the item, raises affinity,
## and checks for 50+ Friendship Milestone Badge/Gear rewards.
## Returns Array of dialogue pages to show.
static func give_gift(talk_id: String, speaker: String, item_id: String) -> Array:
	if Game.item_count(item_id) <= 0:
		return ["You don't have any of that item left!"]
	var item_info: Dictionary = Game.goods(item_id)
	var item_name: String = item_info.get("name", item_id)
	Game.add_item(item_id, -1)

	var profile := _gift_profile(talk_id, speaker)
	var favs: Array = profile.get("favorites", [])
	var is_fav := item_id in favs
	var gain := 25 if is_fav else 15
	var actual_gain := add_affinity(talk_id, speaker, gain)
	var new_aff := get_affinity(talk_id, speaker)

	var pages: Array = []
	var tpl: String = profile["thanks_fav"] if is_fav else profile["thanks_normal"]
	var msg := (tpl % item_name) if "%s" in tpl else tpl
	pages.append("%s  [Friendship +%d! %s %d/100]" % [msg, actual_gain, hearts_text(new_aff), new_aff])

	# Check 50+ Friendship Milestone Reward (once per NPC)
	var key := _npc_key(talk_id, speaker)
	if typeof(Game.player.get("npc_gifts")) != TYPE_DICTIONARY:
		Game.player["npc_gifts"] = {}
	if new_aff >= 50 and not Game.player["npc_gifts"].get(key, false):
		var reward_id: String = profile.get("reward_gear", "heart_badge")
		if Game.add_item(reward_id, 1) > 0:
			Game.player["npc_gifts"][key] = true
			var r_name: String = Game.goods(reward_id).get("name", reward_id)
			pages.append("Since we're such good friends now (%s), please take this special %s as a token of my gratitude!" % [hearts_text(new_aff), r_name])
		else:
			Game.player["npc_gifts"][key] = true
			Game.player["coins"] = clampi(int(Game.player.get("coins", 0)) + 75, 0, 99999)
			pages.append("Since we're such good friends now (%s), take these 75 coins as my thanks!" % hearts_text(new_aff))
	elif new_aff >= 80:
		pages.append("Here's a Best Friend secret rumor: %s" % get_rumor(talk_id))

	Game.save()
	return pages


# --- Sentiment, Rumors & Secret Passwords in Free Chat -----------------------

static func get_rumor(talk_id: String) -> String:
	var idx := absi(talk_id.hash() + int(Time.get_unix_time_from_system() / 3600)) % RUMORS.size()
	return RUMORS[idx]


static func get_riddle(talk_id: String) -> Dictionary:
	var idx := absi(talk_id.hash()) % RIDDLES.size()
	return RIDDLES[idx]


## Evaluates sentiment of free-chat text and returns affinity delta.
static func analyze_sentiment(talk_id: String, text: String) -> int:
	var q := text.strip_edges().to_lower()
	var tid := talk_id.to_lower()

	# Check if they solved any riddle or typed a secret password
	for r in RIDDLES:
		for ans in r["answers"]:
			if ans in q:
				return 15
	if _matches_any(q, ["chuckola-99", "koopa kopa kabana", "beanstar-77"]):
		return 20

	# Jokes (especially loved by Chucklerator, Barista, and Toads)
	if _matches_any(q, ["joke", "knock knock", "why did the", "funny", "haha", "hehe", "laugh", "pun"]):
		return 15

	# Kind / complimentary words
	if _matches_any(q, ["thank", "thanks", "please", "awesome", "great", "love", "like you", "friend", "best", "cool", "amazing", "smart", "brave", "hero", "respect", "admire", "wonderful", "splendid"]):
		return 12

	# Rude words (Bowser actually likes fiery trash talk!)
	if _matches_any(q, ["stupid", "dumb", "hate", "ugly", "idiot", "worst", "shut up", "loser", "boring"]):
		if "bowser" in tid or "koopa" in tid:
			return 8  # Bowser respects fiery attitude!
		return -5

	# Normal conversation gives +5 friendship
	return 5


## Extracts the subject from queries like "how do you feel about onions?" or "what do you think of X?"
static func extract_subject(query: String) -> String:
	var q := query.strip_edges().to_lower()
	while q.ends_with("?") or q.ends_with("!") or q.ends_with("."):
		q = q.substr(0, q.length() - 1).strip_edges()

	var prefixes := [
		"how do you feel about ",
		"how do you feel on ",
		"what do you think of ",
		"what do you think about ",
		"what are your thoughts on ",
		"what is your thought on ",
		"what are your feelings on ",
		"what are your feelings about ",
		"what is your opinion on ",
		"what is your opinion of ",
		"tell me about ",
		"tell me your thoughts on ",
		"do you like ",
		"do you love ",
		"do you hate ",
		"do you enjoy ",
		"have you heard of ",
		"what do you know about ",
		"what is ",
		"who is ",
		"where is ",
		"how about "
	]

	for prefix in prefixes:
		if q.begins_with(prefix):
			var sub := q.substr(prefix.length()).strip_edges()
			if sub.begins_with("the "):
				sub = sub.substr(4).strip_edges()
			return sub

	return ""


## Checks if the player typed a secret password or solved a riddle, and awards bonus coins/items!
static func _check_secret_or_riddle(talk_id: String, speaker: String, q: String) -> String:
	var p: Dictionary = Game.player
	if typeof(p.get("npc_secrets")) != TYPE_DICTIONARY:
		p["npc_secrets"] = {}

	# Secret code check
	if _matches_any(q, ["chuckola-99", "koopa kopa kabana", "beanstar-77"]):
		if not p["npc_secrets"].get("code_claimed", false):
			p["npc_secrets"]["code_claimed"] = true
			p["coins"] = clampi(int(p.get("coins", 0)) + 60, 0, 99999)
			Game.add_item("chuckola_cola", 1)
			Game.save()
			return "Whoa!! You know the secret Kingdom code! Here is the hidden stash: 60 Coins and a vintage Chuckola Cola!"
		return "Haha, you already claimed the secret code stash, fellow insider!"

	# Asking for a riddle
	if _matches_any(q, ["riddle", "quiz", "puzzle", "test me"]):
		var r := get_riddle(talk_id)
		return "Ooh, you want a riddle? Listen closely: \"%s\" (Type the answer in Free Chat!)" % r["q"]

	# Asking for a rumor or secret
	if _matches_any(q, ["rumor", "rumors", "gossip", "secret", "clue", "hint", "treasure"]):
		return "Psst! Lean in close... %s" % get_rumor(talk_id)

	# Telling a joke to NPCs
	if _matches_any(q, ["knock knock", "why did the", "tell you a joke", "here is a joke", "a funny joke"]):
		var key := "joke_" + _npc_key(talk_id, speaker)
		if not p["npc_secrets"].get(key, false):
			p["npc_secrets"][key] = true
			p["coins"] = clampi(int(p.get("coins", 0)) + 25, 0, 99999)
			Game.save()
			return "BWAHAHA! Oh my stars, that joke had me rolling on the cobblestones! Take these 25 coins for making my day!"
		return "Hahaha! That's a classic! A good belly laugh always brightens up the Beanbean Kingdom!"

	return ""


## Generates a contextual, in-character response to any specific query or question,
## while also updating NPC Friendship sentiment!
static func get_reply(talk_id: String, speaker: String, text: String) -> String:
	var raw_q := text.strip_edges()
	var q := raw_q.to_lower()
	var tid := talk_id.to_lower()
	var spk := speaker.to_lower()

	# Update sentiment affinity
	var delta := analyze_sentiment(talk_id, raw_q)
	var gained := add_affinity(talk_id, speaker, delta)
	var aff := get_affinity(talk_id, speaker)
	var tag := ""
	if gained > 0:
		tag = "  [+%d ♥ (%d/100)]" % [gained, aff]
	elif gained < 0:
		tag = "  [%d ♥ (%d/100)]" % [gained, aff]

	# Check secrets, riddles, rumors, and jokes first
	var secret_reply := _check_secret_or_riddle(talk_id, speaker, q)
	if secret_reply != "":
		return secret_reply + tag

	var subject := extract_subject(raw_q)
	var is_opinion_query := subject != ""
	var s := subject.to_lower()

	# --- TOADSWORTH ---
	if "toadsworth" in tid or "toadsworth" in spk:
		if s == "onion" or s == "onions" or "onion" in q:
			return "Good heavens! Onions, you say? While I cannot deny they lend a certain robust zest to a royal stew, the pungent vapors are simply dreadful for my spectacles! Slicing them reduces me to an embarrassing puddle of weeping! I much prefer the soothing serenity of a finely prepared Mushroom soup." + tag
		if "mushroom" in s or "mushrooms" in s:
			return "Bless my mushroom cap! Mushrooms are the finest restorative delicacy in the entire universe! 10 HP of pure mushroom magic in every single bite!" + tag
		if "syrup" in s:
			return "Ah, Syrup! Sweet, rejuvenating, and absolutely essential for keeping your SP replenished during arduous royal missions!" + tag
		if "pepper" in s or "spicy" in s:
			return "Good heavens! Far too fiery for my gentle palate! My tongue feels scorched at the mere mention of peppers!" + tag
		if "tea" in s or "coffee" in s:
			return "A proper cup of freshly steeped Earl Grey tea is the hallmark of any civilized afternoon. Coffee is rather too frantic for my heart!" + tag
		if "peach" in s or "princess" in s:
			return "Princess Peach's safety is our paramount concern! I tremble at the thought of her facing any distress in this foreign realm." + tag
		if "bowser" in s:
			return "That dreadful Koopa brute! Always causing unmentionable distress for our dear Princess Peach! We must remain on high alert!" + tag
		if "mario" in s or "luigi" in s or "bros" in s:
			return "The finest heroes the Mushroom Kingdom could ever ask for! Master Mario's valor and Master Luigi's loyal heart never fail us!" + tag
		if is_opinion_query:
			return ("Good heavens! Regarding '%s', while it may not strictly adhere to traditional Mushroom Kingdom court etiquette, I suppose every novelty has its place—provided it causes no distress to Princess Peach!" % subject) + tag

		if _matches_any(q, ["hello", "hi", "hey", "howdy", "greetings", "good day", "morning"]):
			return "Good heavens! Ah, Master {character}! A splendid day to you! Do ensure your mustache is well groomed." + tag
		if _matches_any(q, ["battle", "fight", "action", "command", "strike", "hit"]):
			return "Bless my spectacles! In battle, timing is of the essence! Strike right as your attack connects for an Excellent rating!" + tag
		if _matches_any(q, ["item", "mushroom", "syrup", "heal", "herb"]):
			return "A prepared gentleman always keeps Mushrooms and Syrup tucked neatly in his waistcoat pockets!" + tag
		if _matches_any(q, ["quest", "errand", "mission", "bounty", "task", "job"]):
			return "The realm depends on valiant heroes like yourself! Clearing out ruffians in the Outskirts would be ever so helpful to our travelers." + tag
		return ("Good heavens! \"%s\", you say? Most intriguing! Do take care on your travels through the Beanbean Kingdom, dear boy!" % raw_q) + tag

	# --- PROF. E. GADD ---
	if "e_gadd" in tid or "gadd" in spk or "professor" in spk:
		if s == "onion" or s == "onions" or "onion" in q:
			return "Gya-ha-ha! Onions?! Fascinating botanical specimens! Did you know the sulfuric compounds in allium vegetables can be distilled into an organic spectral repellant? Great jumpin' jellybeans, I should load an onion slurry into the Poltergust nozzle!" + tag
		if "ghost" in s or "boo" in s or "spectral" in s:
			return "Great jumpin' jellybeans! Boos are full of concentrated paranormal ectoplasm! Capture their residue and we can power miraculous inventions!" + tag
		if "coffee" in s or "bean" in s or "starbean" in s:
			return "Ho ho! Chuckola blend coffee stimulates the intellect like nothing else! One sip and revolutionary inventions start bubbling in my brain!" + tag
		if "poltergust" in s or "vacuum" in s or "fludd" in s:
			return "Gya-ha-ha! My vacuum mechanics are calibrated to perfection! 120 PSI of pure paranormal suction power!" + tag
		if is_opinion_query:
			return ("Gya-ha-ha! '%s'?! Great jumpin' jellybeans, that has fascinating scientific applications! I wonder how it reacts under high-frequency spectral resonance?!" % subject) + tag

		if _matches_any(q, ["hello", "hi", "hey", "howdy", "greetings"]):
			return "Gya-ha-ha! Welcome, {character}! Watch your step around the high-voltage spectral conduits!" + tag
		if _matches_any(q, ["battle", "fight", "gear", "badge"]):
			return "Combat is simply applied physics! Time your hammer swings and jumps with algorithmic precision!" + tag
		return ("Gya-ha-ha! \"%s\"? An electrifying hypothesis! Let me jot that down in my research notes!" % raw_q) + tag

	# --- BOWSER / BORDER BRO / KOOPA GUARDS ---
	if "bowser" in tid or "border" in tid or "koopa" in tid:
		if s == "onion" or s == "onions" or "onion" in q:
			return "GWAHAHA! Onions?! A real Koopa King roasts 'em whole with fiery breath until they're charred black! None of that mild, diced stuff Peach serves—give me pungent, smoky fire-roasted onions to stoke my flame breath! Gwahaha!" + tag
		if "peach" in s or "princess" in s:
			return "Peach?! Gwahaha! Someday she'll realize Bowser's Castle is ten times grander than her wimpy Mushroom Kingdom!" + tag
		if "mario" in s or "luigi" in s or "bros" in s or "plumber" in s:
			return "Those overalls-wearing pests! Every time I have a genius plan, they jump on my head! But next time, I'm stomping them flat!" + tag
		if "password" in s or "secret" in s:
			return "Psst! The secret password is 'Koopa Kopa Kabana'! Don't let those good-side chumps overhear!" + tag
		if "fire" in s or "flame" in s:
			return "GWAHAHA! My fire breath is the hottest in the universe! It can melt boulders and barbecue any monster in the kingdom!" + tag
		if is_opinion_query:
			return ("GWAHAHA! '%s'?! If it doesn't make my minions stronger or my fire breath hotter, who cares?! But if it can crush plumbers, I'm all for it!" % subject) + tag

		if _matches_any(q, ["hello", "hi", "hey", "howdy"]):
			return "Gwahaha! What do you want, chump?! Stand up straight when you address the Koopa Troop!" + tag
		if _matches_any(q, ["battle", "fight", "strong", "power", "streak"]):
			return "Bwahaha! Strength rules all in Bowser's army! Keep up the fight and build your winning streak!" + tag
		return ("Bwahaha! You talk bold with \"%s\"! Get back out there and crush some enemies for Bowser!" % raw_q) + tag

	# --- QUEEN BEAN / LADY LIMA ---
	if "queen" in tid or "lima" in tid or "queen" in spk:
		if s == "onion" or s == "onions" or "onion" in q:
			return "As ruler of the agricultural heartland of the Beanbean Kingdom, all bounties of the soil are welcome—though crisp Beanish sprouts and royal beans hold a far higher place in my royal pantry than pungent onions!" + tag
		if "beanstar" in s or "star" in s:
			return "The Beanstar is our most sacred treasure. Its radiant slumber keeps our kingdom fertile and peaceful." + tag
		if is_opinion_query:
			return ("On the matter of '%s', the crown maintains an open and benevolent mind. All curious things are welcome under the gentle light of the Beanstar!" % subject) + tag

	# --- CAFE BARISTA ---
	if "barista" in tid or "cafe" in tid:
		if "coffee" in s or "bean" in s or "brew" in s or "drink" in s:
			return "Welcome to Starbeans Cafe! Bring me Woo beans, Chuckle beans, and Teehee beans to brew rare stat-boosting drinks!" + tag
		if is_opinion_query:
			return ("Hmm, '%s'? If it can be ground into a fine powder and steeped in boiling mineral water, I can probably brew a drink out of it!" % subject) + tag

	# --- SHOPKEEPERS ---
	if "shop" in tid or "store" in tid or "trader" in tid:
		if "price" in s or "coin" in s or "money" in s or "gold" in s or "discount" in q:
			return "Coins make the kingdom go round! Give me a gift or chat with me to raise our friendship—I give up to 25% off to my best friends!" + tag
		if is_opinion_query:
			return ("Well, if '%s' sells for good coin or helps adventurers survive out in the Outskirts, I'm all for stocking it!" % subject) + tag

	# --- GENERAL TOWNSFOLK, GUARDS & TRAVELERS ---
	if s == "onion" or s == "onions" or "onion" in q:
		return "Oh, onions? Chop 'em up with some Outskirts herbs and fresh mushrooms for a hearty stamina broth! Just keep a cloth handy for the tears!" + tag
	if "weather" in s or "rain" in s or "sun" in s:
		return "The weather in the Beanbean Kingdom is always ripe for adventure—sunny skies in town, windy peaks up on Hoohoo Mountain!" + tag
	if "monster" in s or "danger" in s or "boss" in s:
		return "Folk say fearsome bosses roam the high summits and deep caves. Make sure your party is well leveled!" + tag
	if "food" in s or "eat" in s or "dinner" in s:
		return "Nothing beats a steaming bowl of Chuckola stew after a hard day of monster battling in the Outskirts!" + tag
	if is_opinion_query:
		return ("Well, about '%s'... you hear all sorts of opinions in town, but I reckon as long as it doesn't cause trouble, it's alright by me!" % subject) + tag

	if _matches_any(q, ["hello", "hi", "hey", "howdy", "sup"]):
		return "Hey there, {character}! Nice day for an adventure, isn't it?" + tag
	if _matches_any(q, ["where", "direction", "map", "path", "road"]):
		return "The castle is to the north, and both town gates lead out to the Beanbean Outskirts. Watch out for roaming monsters!" + tag
	if _matches_any(q, ["battle", "fight", "jump", "hammer"]):
		return "Timing your hits is everything in battle! Press your action command right as you land to deal maximum damage!" + tag
	if _matches_any(q, ["joke", "funny", "laugh"]):
		return "Haha! Master Chucklerator down at the winery would love that one! Laughter is the finest seasoning." + tag
	if _matches_any(q, ["help", "advice", "tip"]):
		return "Always carry a few Mushrooms and Syrup in your bag, and recruit a good battle partner to watch your back!" + tag

	return ("Ah, \"%s\"? Well said, traveler! Safe journeys through the Beanbean Kingdom!" % raw_q) + tag


static func _matches_any(text: String, keywords: Array) -> bool:
	for kw in keywords:
		if kw in text:
			return true
	return false
