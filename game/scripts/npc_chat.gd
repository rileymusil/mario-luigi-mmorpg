class_name NpcChat
extends RefCounted
## In-game NPC dialogue knowledge base and interactive topic responses for major Kingdom characters.

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
