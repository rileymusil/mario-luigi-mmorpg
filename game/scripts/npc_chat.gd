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


## Generates a contextual, in-character response when the player types free chat to an NPC.
static func get_reply(talk_id: String, speaker: String, text: String) -> String:
	var q := text.strip_edges().to_lower()
	var tid := talk_id.to_lower()
	var spk := speaker.to_lower()

	# --- TOADSWORTH ---
	if "toadsworth" in tid or "toadsworth" in spk:
		if _matches_any(q, ["hello", "hi", "hey", "howdy", "greetings", "good day", "morning"]):
			return "Good heavens! Ah, Master {character}! A splendid day to you! Do ensure your mustache is well groomed."
		if _matches_any(q, ["peach", "princess"]):
			return "Princess Peach's safety is our paramount concern! I tremble at the mere thought of her facing any distress in this foreign realm."
		if _matches_any(q, ["battle", "fight", "action", "command", "strike", "hit"]):
			return "Bless my spectacles! In battle, timing is of the essence! Strike right as your attack connects for an Excellent rating!"
		if _matches_any(q, ["item", "mushroom", "syrup", "heal", "herb"]):
			return "A prepared gentleman always keeps Mushrooms and Syrup tucked neatly in his waistcoat pockets!"
		if _matches_any(q, ["quest", "errand", "mission", "bounty", "task", "job"]):
			return "The realm depends on valiant heroes like yourself! Clearing out ruffians in the Outskirts would be ever so helpful to our travelers."
		if _matches_any(q, ["luigi", "brother"]):
			return "Ah, Master Luigi! A bit timid at times, perhaps, but a hero of noble stature nonetheless!"
		if _matches_any(q, ["bowser", "cackletta", "fawful", "evil", "villain"]):
			return "Those wicked fiends! Keep your wits sharp and your hammer ready, Master {character}!"
		return "Good heavens! \"%s\", you say? Most intriguing! Do take care on your travels through the Beanbean Kingdom, dear boy!" % text

	# --- PROF. E. GADD ---
	if "e_gadd" in tid or "gadd" in spk or "professor" in spk:
		if _matches_any(q, ["hello", "hi", "hey", "howdy", "greetings"]):
			return "Gya-ha-ha! Welcome, {character}! Watch your step around the high-voltage spectral conduits!"
		if _matches_any(q, ["invention", "gadget", "poltergust", "fludd", "machine", "build"]):
			return "Gya-ha-ha! My latest Poltergust vacuum prototype is running at 110% capacity! Pure genius, I tell you!"
		if _matches_any(q, ["ghost", "boo", "spectral", "haunt"]):
			return "Great jumpin' jellybeans! If you spot any ghostly residue in the fields, bring it straight to my lab for distillation!"
		if _matches_any(q, ["coffee", "beans", "brew", "starbeans"]):
			return "Ho ho! Chuckola blend coffee stimulates the intellect like nothing else! One sip and ideas start bubbling!"
		if _matches_any(q, ["battle", "fight", "gear", "badge"]):
			return "Combat is simply applied physics! Time your hammer swings and jumps with algorithmic precision!"
		return "Gya-ha-ha! \"%s\"? An electrifying hypothesis! Let me jot that down in my research notes!" % text

	# --- BOWSER / BORDER BRO / KOOPA GUARDS ---
	if "bowser" in tid or "border" in tid or "koopa" in tid:
		if _matches_any(q, ["hello", "hi", "hey", "howdy"]):
			return "Gwahaha! What do you want, chump?! Stand up straight when you address the Koopa Troop!"
		if _matches_any(q, ["password", "secret", "code"]):
			return "Psst! The secret password is 'Koopa Kopa Kabana'! Don't let those plumber chumps hear you!"
		if _matches_any(q, ["battle", "fight", "strong", "power", "streak"]):
			return "Bwahaha! Strength rules all in Bowser's army! Keep up the fight and build your winning streak!"
		if _matches_any(q, ["mario", "luigi", "bros"]):
			return "Those plumbers think they're so clever with their little jumps! Koopa muscle always flattens them in the end!"
		if _matches_any(q, ["peach", "princess"]):
			return "Princess Peach will soon witness the glory of Bowser's mighty castle! Gwahaha!"
		return "Bwahaha! You talk bold with \"%s\"! Get back out there and crush some enemies for Bowser!" % text

	# --- QUEEN BEAN / LADY LIMA ---
	if "queen" in tid or "lima" in tid or "queen" in spk:
		if _matches_any(q, ["peach", "princess"]):
			return "Princess Peach is an esteemed diplomatic guest in our realm. Our royal guards stand vigilant to safeguard her peace."
		if _matches_any(q, ["beanstar", "star", "treasure"]):
			return "The Beanstar is our most sacred treasure. Its radiant slumber keeps our kingdom fertile and peaceful."
		if _matches_any(q, ["cackletta", "fawful", "evil", "threat"]):
			return "We shall not bow to chaotic schemers! With loyal protectors like you, justice shall triumph in the Beanbean Kingdom."
		return "The crown appreciates your words, {character}. May fortune and valor guide your steps throughout our realm."

	# --- CAFE BARISTA ---
	if "barista" in tid or "cafe" in tid:
		if _matches_any(q, ["coffee", "bean", "brew", "drink", "blend"]):
			return "Welcome to Starbeans Cafe! Bring me Woo beans, Chuckle beans, and Teehee beans to brew rare stat-boosting drinks!"
		return "A warm cup of Starbeans brew will revive your spirits after a long trek through the Outskirts!"

	# --- SHOPKEEPERS ---
	if "shop" in tid or "store" in tid or "trader" in tid:
		if _matches_any(q, ["buy", "sell", "coin", "price", "stock", "item"]):
			return "Welcome! We have the freshest Mushrooms, Syrup bottles, and protective badges in stock today!"
		return "Coins well spent are battles well won! Let me know if you need to stock up on battle items."

	# --- GENERAL TOWNSFOLK, GUARDS & TRAVELERS ---
	if _matches_any(q, ["hello", "hi", "hey", "howdy", "sup"]):
		return "Hey there, {character}! Nice day for an adventure, isn't it?"
	if _matches_any(q, ["where", "direction", "map", "path", "road"]):
		return "The castle is to the north, and both town gates lead out to the Beanbean Outskirts. Watch out for roaming monsters!"
	if _matches_any(q, ["battle", "fight", "jump", "hammer"]):
		return "Timing your hits is everything in battle! Press your action command right as you land to deal maximum damage!"
	if _matches_any(q, ["boss", "monster", "danger"]):
		return "Folk say fearsome bosses roam the high summits and deep caves. Make sure your party is well leveled!"
	if _matches_any(q, ["joke", "funny", "laugh"]):
		return "Haha! Master Chucklerator down at the winery would love that one! Laughter is the finest seasoning."
	if _matches_any(q, ["help", "advice", "tip"]):
		return "Always carry a few Mushrooms and Syrup in your bag, and recruit a good battle partner to watch your back!"

	# Fallback in-character conversational reply
	return "Ah, \"%s\"? Well said, traveler! Safe journeys through the Beanbean Kingdom!" % text


static func _matches_any(text: String, keywords: Array) -> bool:
	for kw in keywords:
		if kw in text:
			return true
	return false
