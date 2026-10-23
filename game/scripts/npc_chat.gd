class_name NpcChat
extends RefCounted
## In-game NPC dialogue knowledge base and interactive free-chat response engine for Kingdom characters.

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


static func has_topics(talk_id: String) -> bool:
	return TOPICS.has(talk_id)


static func get_topics(talk_id: String) -> Dictionary:
	return TOPICS.get(talk_id, {})


## Extracts the subject from queries like "how do you feel about onions?" or "what do you think of X?"
static func extract_subject(query: String) -> String:
	var q := query.strip_edges().to_lower()
	# Strip ending punctuation
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


## Generates a contextual, in-character response to any specific query or question.
static func get_reply(talk_id: String, speaker: String, text: String) -> String:
	var raw_q := text.strip_edges()
	var q := raw_q.to_lower()
	var tid := talk_id.to_lower()
	var spk := speaker.to_lower()
	var subject := extract_subject(raw_q)
	var is_opinion_query := subject != ""

	# Cleaned subject for matching
	var s := subject.to_lower()

	# --- TOADSWORTH ---
	if "toadsworth" in tid or "toadsworth" in spk:
		if s == "onion" or s == "onions":
			return "Good heavens! Onions, you say? While I cannot deny they lend a certain robust zest to a royal stew, the pungent vapors are simply dreadful for my spectacles! Slicing them reduces me to an embarrassing puddle of weeping! I much prefer the soothing serenity of a finely prepared Mushroom soup."
		if "mushroom" in s or "mushrooms" in s:
			return "Bless my mushroom cap! Mushrooms are the finest restorative delicacy in the entire universe! 10 HP of pure mushroom magic in every single bite!"
		if "syrup" in s:
			return "Ah, Syrup! Sweet, rejuvenating, and absolutely essential for keeping your SP replenished during arduous royal missions!"
		if "pepper" in s or "spicy" in s:
			return "Good heavens! Far too fiery for my gentle palate! My tongue feels scorched at the mere mention of peppers!"
		if "tea" in s or "coffee" in s:
			return "A proper cup of freshly steeped Earl Grey tea is the hallmark of any civilized afternoon. Coffee is rather too frantic for my heart!"
		if "peach" in s or "princess" in s:
			return "Princess Peach's safety is our paramount concern! I tremble at the thought of her facing any distress in this foreign realm."
		if "bowser" in s:
			return "That dreadful Koopa brute! Always causing unmentionable distress for our dear Princess Peach! We must remain on high alert!"
		if "mario" in s or "luigi" in s or "bros" in s:
			return "The finest heroes the Mushroom Kingdom could ever ask for! Master Mario's valor and Master Luigi's loyal heart never fail us!"
		if is_opinion_query:
			return "Good heavens! Regarding '%s', while it may not strictly adhere to traditional Mushroom Kingdom court etiquette, I suppose every novelty has its place—provided it causes no distress to Princess Peach!" % subject

		# General greetings / queries
		if _matches_any(q, ["hello", "hi", "hey", "howdy", "greetings", "good day", "morning"]):
			return "Good heavens! Ah, Master {character}! A splendid day to you! Do ensure your mustache is well groomed."
		if _matches_any(q, ["battle", "fight", "action", "command", "strike", "hit"]):
			return "Bless my spectacles! In battle, timing is of the essence! Strike right as your attack connects for an Excellent rating!"
		if _matches_any(q, ["item", "mushroom", "syrup", "heal", "herb"]):
			return "A prepared gentleman always keeps Mushrooms and Syrup tucked neatly in his waistcoat pockets!"
		if _matches_any(q, ["quest", "errand", "mission", "bounty", "task", "job"]):
			return "The realm depends on valiant heroes like yourself! Clearing out ruffians in the Outskirts would be ever so helpful to our travelers."
		return "Good heavens! \"%s\", you say? Most intriguing! Do take care on your travels through the Beanbean Kingdom, dear boy!" % raw_q

	# --- PROF. E. GADD ---
	if "e_gadd" in tid or "gadd" in spk or "professor" in spk:
		if s == "onion" or s == "onions":
			return "Gya-ha-ha! Onions?! Fascinating botanical specimens! Did you know the sulfuric compounds in allium vegetables can be distilled into an organic spectral repellant? Great jumpin' jellybeans, I should load an onion slurry into the Poltergust nozzle!"
		if "ghost" in s or "boo" in s or "spectral" in s:
			return "Great jumpin' jellybeans! Boos are full of concentrated paranormal ectoplasm! Capture their residue and we can power miraculous inventions!"
		if "coffee" in s or "bean" in s or "starbean" in s:
			return "Ho ho! Chuckola blend coffee stimulates the intellect like nothing else! One sip and revolutionary inventions start bubbling in my brain!"
		if "poltergust" in s or "vacuum" in s or "fludd" in s:
			return "Gya-ha-ha! My vacuum mechanics are calibrated to perfection! 120 PSI of pure paranormal suction power!"
		if is_opinion_query:
			return "Gya-ha-ha! '%s'?! Great jumpin' jellybeans, that has fascinating scientific applications! I wonder how it reacts under high-frequency spectral resonance?!" % subject

		if _matches_any(q, ["hello", "hi", "hey", "howdy", "greetings"]):
			return "Gya-ha-ha! Welcome, {character}! Watch your step around the high-voltage spectral conduits!"
		if _matches_any(q, ["battle", "fight", "gear", "badge"]):
			return "Combat is simply applied physics! Time your hammer swings and jumps with algorithmic precision!"
		return "Gya-ha-ha! \"%s\"? An electrifying hypothesis! Let me jot that down in my research notes!" % raw_q

	# --- BOWSER / BORDER BRO / KOOPA GUARDS ---
	if "bowser" in tid or "border" in tid or "koopa" in tid:
		if s == "onion" or s == "onions":
			return "GWAHAHA! Onions?! A real Koopa King roasts 'em whole with fiery breath until they're charred black! None of that mild, diced stuff Peach serves—give me pungent, smoky fire-roasted onions to stoke my flame breath! Gwahaha!"
		if "peach" in s or "princess" in s:
			return "Peach?! Gwahaha! Someday she'll realize Bowser's Castle is ten times grander than her wimpy Mushroom Kingdom!"
		if "mario" in s or "luigi" in s or "bros" in s or "plumber" in s:
			return "Those overalls-wearing pests! Every time I have a genius plan, they jump on my head! But next time, I'm stomping them flat!"
		if "password" in s or "secret" in s:
			return "Psst! The secret password is 'Koopa Kopa Kabana'! Don't let those good-side chumps overhear!"
		if "fire" in s or "flame" in s:
			return "GWAHAHA! My fire breath is the hottest in the universe! It can melt boulders and barbecue any monster in the kingdom!"
		if is_opinion_query:
			return "GWAHAHA! '%s'?! If it doesn't make my minions stronger or my fire breath hotter, who cares?! But if it can crush plumbers, I'm all for it!" % subject

		if _matches_any(q, ["hello", "hi", "hey", "howdy"]):
			return "Gwahaha! What do you want, chump?! Stand up straight when you address the Koopa Troop!"
		if _matches_any(q, ["battle", "fight", "strong", "power", "streak"]):
			return "Bwahaha! Strength rules all in Bowser's army! Keep up the fight and build your winning streak!"
		return "Bwahaha! You talk bold with \"%s\"! Get back out there and crush some enemies for Bowser!" % raw_q

	# --- QUEEN BEAN / LADY LIMA ---
	if "queen" in tid or "lima" in tid or "queen" in spk:
		if s == "onion" or s == "onions":
			return "As ruler of the agricultural heartland of the Beanbean Kingdom, all bounties of the soil are welcome—though crisp Beanish sprouts and royal beans hold a far higher place in my royal pantry than pungent onions!"
		if "beanstar" in s or "star" in s:
			return "The Beanstar is our most sacred treasure. Its radiant slumber keeps our kingdom fertile and peaceful."
		if is_opinion_query:
			return "On the matter of '%s', the crown maintains an open and benevolent mind. All curious things are welcome under the gentle light of the Beanstar!" % subject

	# --- CAFE BARISTA ---
	if "barista" in tid or "cafe" in tid:
		if "coffee" in s or "bean" in s or "brew" in s or "drink" in s:
			return "Welcome to Starbeans Cafe! Bring me Woo beans, Chuckle beans, and Teehee beans to brew rare stat-boosting drinks!"
		if is_opinion_query:
			return "Hmm, '%s'? If it can be ground into a fine powder and steeped in boiling mineral water, I can probably brew a drink out of it!" % subject

	# --- SHOPKEEPERS ---
	if "shop" in tid or "store" in tid or "trader" in tid:
		if "price" in s or "coin" in s or "money" in s or "gold" in s:
			return "Coins make the kingdom go round! Spend them on items, badges, or trade with traveling companions!"
		if is_opinion_query:
			return "Well, if '%s' sells for good coin or helps adventurers survive out in the Outskirts, I'm all for stocking it!" % subject

	# --- GENERAL TOWNSFOLK, GUARDS & TRAVELERS ---
	if s == "onion" or s == "onions":
		return "Oh, onions? Chop 'em up with some Outskirts herbs and fresh mushrooms for a hearty stamina broth! Just keep a cloth handy for the tears!"
	if "weather" in s or "rain" in s or "sun" in s:
		return "The weather in the Beanbean Kingdom is always ripe for adventure—sunny skies in town, windy peaks up on Hoohoo Mountain!"
	if "monster" in s or "danger" in s or "boss" in s:
		return "Folk say fearsome bosses roam the high summits and deep caves. Make sure your party is well leveled!"
	if "food" in s or "eat" in s or "dinner" in s:
		return "Nothing beats a steaming bowl of Chuckola stew after a hard day of monster battling in the Outskirts!"
	if is_opinion_query:
		return "Well, about '%s'... you hear all sorts of opinions in town, but I reckon as long as it doesn't cause trouble, it's alright by me!" % subject

	if _matches_any(q, ["hello", "hi", "hey", "howdy", "sup"]):
		return "Hey there, {character}! Nice day for an adventure, isn't it?"
	if _matches_any(q, ["where", "direction", "map", "path", "road"]):
		return "The castle is to the north, and both town gates lead out to the Beanbean Outskirts. Watch out for roaming monsters!"
	if _matches_any(q, ["battle", "fight", "jump", "hammer"]):
		return "Timing your hits is everything in battle! Press your action command right as you land to deal maximum damage!"
	if _matches_any(q, ["joke", "funny", "laugh"]):
		return "Haha! Master Chucklerator down at the winery would love that one! Laughter is the finest seasoning."
	if _matches_any(q, ["help", "advice", "tip"]):
		return "Always carry a few Mushrooms and Syrup in your bag, and recruit a good battle partner to watch your back!"

	# Fallback in-character conversational reply
	return "Ah, \"%s\"? Well said, traveler! Safe journeys through the Beanbean Kingdom!" % raw_q


static func _matches_any(text: String, keywords: Array) -> bool:
	for kw in keywords:
		if kw in text:
			return true
	return false
