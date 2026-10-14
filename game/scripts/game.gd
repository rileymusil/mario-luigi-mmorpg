extends Node
## Global game state (autoloaded as "Game"): data tables, the player's save,
## and moving between the title, the world maps and battles.

const TITLE_SCENE := "res://scenes/title.tscn"
const WORLD_SCENE := "res://scenes/world.tscn"
const BATTLE_SCENE := "res://scenes/battle.tscn"
const PVP_SCENE := "res://scenes/pvp_battle.tscn"
const COOP_SCENE := "res://scenes/coop_battle.tscn"        # you started it, your partner joins
const COOP_GUEST_SCENE := "res://scenes/coop_guest.tscn"   # your partner's battle, seen from your side
const SAVE_PATH := "user://save.json"
const MAX_LEVEL := 50
const MAX_PARTY := 2

## Sprite sheets live in res://assets/characters/<id>.png: 3 rows (down,
## right, up) of `frames` cells. Built by tools/slice_sprites.py.
## Each side lists the design roster first (this is the character select
## order), then the extra Superstar Saga-style customs.
const CHARACTERS := {
	"mario": {"name": "Mario", "side": "good", "frames": 8, "hp": 20, "sp": 10, "pow": 5, "def": 2,
		"special": "fire_jump"},
	"luigi": {"name": "Luigi", "side": "good", "frames": 8, "hp": 22, "sp": 10, "pow": 4, "def": 3,
		"special": "thunderhand"},
	"peach": {"name": "Princess Peach", "side": "good", "frames": 8, "hp": 18, "sp": 14, "pow": 4, "def": 2,
		"special": "peach_heart"},
	"egadd": {"name": "Professor E. Gadd", "side": "good", "frames": 8, "hp": 18, "sp": 12, "pow": 4, "def": 2,
		"special": "poltergust_pull"},
	"vivian": {"name": "Vivian", "side": "good", "frames": 2, "hp": 19, "sp": 12, "pow": 5, "def": 2,
		"special": "shade_veil"},
	"waluigi": {"name": "Waluigi", "side": "good", "frames": 5, "hp": 21, "sp": 10, "pow": 5, "def": 2,
		"special": "wicked_whirl"},
	"rosalina": {"name": "Rosalina", "side": "good", "frames": 7, "hp": 18, "sp": 14, "pow": 4, "def": 2,
		"special": "star_spin"},
	"toadette": {"name": "Toadette", "side": "good", "frames": 8, "hp": 17, "sp": 12, "pow": 4, "def": 2,
		"special": "pickaxe_pound"},
	"bowser": {"name": "Bowser", "side": "evil", "frames": 5, "hp": 26, "sp": 10, "pow": 6, "def": 3,
		"special": "fire_breath"},
	"rookie_bowser": {"name": "Rookie Bowser", "side": "evil", "frames": 8, "hp": 24, "sp": 10, "pow": 6, "def": 3,
		"special": "rookie_rush"},
	"grodus": {"name": "Grodus", "side": "evil", "frames": 5, "hp": 21, "sp": 14, "pow": 5, "def": 2,
		"special": "grodus_bolt"},
	"koopa_bros": {"name": "Koopa Bros.", "side": "evil", "frames": 5, "hp": 22, "sp": 12, "pow": 5, "def": 3,
		"special": "bros_tower"},
	"bowser_jr": {"name": "Bowser Jr.", "side": "evil", "frames": 1, "hp": 22, "sp": 12, "pow": 5, "def": 2,
		"special": "goop_paint"},
	"shadow_mario": {"name": "Shadow Mario", "side": "evil", "frames": 1, "hp": 20, "sp": 12, "pow": 5, "def": 2,
		"special": "shadow_drain"},
}

## Characters that were taken out of the game, and who old saves with them
## play as now (see load_save).
const REMOVED_CHARACTERS := {"dimentio": "bowser", "mimi": "bowser"}

## Signature moves (battle.gd _special), each a timed press. {a} in an info
## line names the A button: Z on keys, A on touch (battle.gd _keys).
const SPECIALS := {
	"fire_jump": {"name": "Fire Jump", "sp": 4, "info": "Jump that burns the enemy for 3 turns."},
	"thunderhand": {"name": "Thunderhand", "sp": 4, "info": "Electric punch. Great timing stuns."},
	"peach_heart": {"name": "Peach's Heart", "sp": 5, "info": "Heals the whole party. Good timing heals more."},
	"poltergust_pull": {"name": "Poltergust Pull", "sp": 5,
		"info": "Sucks HP out of an enemy. Excellent also steals its item."},
	"shade_veil": {"name": "Shade Veil", "sp": 5,
		"info": "Hide in the shadows, dodge the next attack, then hit back with fire."},
	"fire_breath": {"name": "Fire Breath", "sp": 5, "info": "Fire hits every enemy at once."},
	"rookie_rush": {"name": "Rookie Rush", "sp": 5,
		"info": "Up to 3 shell bashes; {a} as each hits. Excellents in a row hit harder."},
	"grodus_bolt": {"name": "Grodus Bolt", "sp": 6, "info": "Lightning hits every enemy and lowers their DEF."},
	"bros_tower": {"name": "Bros. Tower", "sp": 6,
		"info": "{a} as each brother lands on the stack, then the tower spins into the enemy."},
	"wicked_whirl": {"name": "Wicked Whirl", "sp": 5, "info": "Hits every enemy. Excellent stuns all."},
	"star_spin": {"name": "Star Spin", "sp": 5, "info": "Hits one enemy, heals the party a bit."},
	"pickaxe_pound": {"name": "Pickaxe Pound", "sp": 4, "info": "Heavy hit that ignores defense."},
	"goop_paint": {"name": "Goop Paint", "sp": 4, "info": "Goopy hit. Great timing stuns."},
	"shadow_drain": {"name": "Shadow Drain", "sp": 5, "info": "Steals HP from an enemy."},
}

## What partners and recruited enemies do on their own turn (battle.gd
## _partner_move). Enemies are known for theirs.
## kind: "tackle" (Z in the gold zone, then run in), "stomp" (jump, Z as you
## land), "throw" (Z in the gold zone, something flies at the enemy), "blast"
## (hits every enemy) or "multi" (up to `hits` hits, a press each; a miss
## stops it). Optional: bonus (added to POW), ignore_def, color (of a throw),
## and extras an Excellent adds: stun, burn (turns), def_down (DEF lost),
## heal (party HP), pierce (the next enemy is hit too).
const MOVES := {
	"mushroom_toss": {"name": "Mushroom Toss", "kind": "throw", "color": Color(0.95, 0.25, 0.2), "heal": 3,
		"info": "Throws a Mushroom. Excellent also heals the party 3 HP."},
	"pianta_slam": {"name": "Pianta Slam", "kind": "tackle", "bonus": 1, "info": "A heavy belly slam."},
	"bomb": {"name": "Bomb", "kind": "blast", "info": "Explodes and hits every enemy."},
	"smack": {"name": "Smack", "kind": "multi", "hits": 3, "info": "Up to 3 slaps, {a} in the gold zone for each."},
	"bob_ombast": {"name": "Bob-ombast", "kind": "blast", "bonus": 1, "burn": 2,
		"info": "Huge blast on every enemy. Excellent sets them on fire."},
	"headbonk": {"name": "Headbonk", "kind": "stomp", "info": "Jump on the enemy. {a} as you land for a 2nd hit."},
	"shell_toss": {"name": "Shell Toss", "kind": "throw", "color": Color(0.3, 0.75, 0.25), "pierce": true,
		"info": "A shell slides into an enemy. Excellent hits the next one too."},
	"gulp": {"name": "Gulp", "kind": "tackle", "ignore_def": true,
		"info": "Gulps the enemy down and spits it out. Ignores DEF."},
	"rose_toss": {"name": "Rose Toss", "kind": "throw", "color": Color(1.0, 0.45, 0.6), "def_down": 2,
		"info": "Tosses a rose. Excellent charms the enemy: DEF down."},
	"ground_pound": {"name": "Ground Pound", "kind": "stomp", "stun": true,
		"info": "Flutter up and pound. {a} as you land; Excellent stuns."},
	"rolling_bump": {"name": "Rolling Bump", "kind": "tackle", "info": "Rolls into the enemy."},
	"bean_bash": {"name": "Bean Bash", "kind": "tackle", "stun": true,
		"info": "Pops out of the ground. Excellent stuns."},
	"shy_spin": {"name": "Shy Spin", "kind": "multi", "hits": 2, "info": "Up to 2 spinning hits."},
	"shell_spin": {"name": "Shell Spin", "kind": "tackle", "def_down": 1,
		"info": "Hard shell spin. Excellent lowers the enemy's DEF."},
	"bone_toss": {"name": "Bone Toss", "kind": "throw", "color": Color(0.95, 0.93, 0.85), "bonus": 1,
		"info": "Throws a bone."},
	# Bosses that joined an evil party (BOSSES "partner").
	"sack_swipe": {"name": "Sack Swipe", "kind": "multi", "hits": 2, "bonus": 1,
		"info": "Up to 2 sack swipes, {a} in the gold zone for each."},
	"spike_toss": {"name": "Spike Toss", "kind": "throw", "color": Color(0.55, 0.55, 0.6), "bonus": 1, "pierce": true,
		"info": "Throws a spike ball. Excellent hits the next enemy too."},
	"dragon_fire": {"name": "Dragon Fire", "kind": "blast", "bonus": 1, "burn": 2,
		"info": "Fire on every enemy. Excellent sets them burning."},
	"bubble_blast": {"name": "Bubble Blast", "kind": "blast", "bonus": 2, "stun": true,
		"info": "Bubbles hit every enemy. Excellent stuns them."},
}

## Partners (good side) and recruitable enemies (evil side). `recruit` is the
## base chance that asking works; it goes up as the enemy gets weaker, and
## stronger enemies start lower. `move` is their turn in battle (MOVES),
## `line` what a partner says when you talk to them.
const PARTNERS := {
	"toad": {"name": "Toad", "frames": 8, "hp": 14, "pow": 3, "def": 1, "recruit": 0.5, "move": "mushroom_toss",
		"line": "Going out to the Outskirts? It's dangerous out there..."},
	"pianta": {"name": "Pianta", "frames": 3, "hp": 20, "pow": 4, "def": 2, "recruit": 0.35, "move": "pianta_slam",
		"line": "Whoa, a traveler! Need some muscle out there?"},
	"bombette": {"name": "Bombette", "frames": 4, "hp": 14, "pow": 4, "def": 1, "recruit": 0.45, "move": "bomb",
		"line": "Hi, I'm Bombette! I get a little explosive once I get going!"},
	"bow": {"name": "Bow", "frames": 4, "hp": 14, "pow": 3, "def": 1, "recruit": 0.4, "move": "smack",
		"line": "Hmph. I am Lady Bow. I suppose I could slap a few Goombas for you."},
	"bobbery": {"name": "Bobbery", "frames": 3, "hp": 18, "pow": 5, "def": 1, "recruit": 0.3, "move": "bob_ombast",
		"line": "Ahoy! Admiral Bobbery here. These old fuses still pack a blast!"},
	"goombella": {"name": "Goombella", "frames": 5, "hp": 14, "pow": 3, "def": 1, "recruit": 0.5, "move": "headbonk",
		"line": "Hi! I'm Goombella, archaeology student. Want some company?"},
	"koops": {"name": "Koops", "frames": 9, "hp": 15, "pow": 4, "def": 2, "recruit": 0.45, "move": "shell_toss",
		"line": "H-hi, I'm Koops. I want to be brave... Maybe you could help?"},
	"yoshi_kid": {"name": "Yoshi Kid", "frames": 9, "hp": 13, "pow": 3, "def": 1, "recruit": 0.5, "move": "gulp",
		"line": "Yo! I'm the toughest Yoshi around. You need me, right?"},
	"peasley": {"name": "Prince Peasley", "frames": 8, "hp": 18, "pow": 5, "def": 2, "recruit": 0.3,
		"move": "rose_toss", "line": "Greetings! I am Prince Peasley of the Beanbean Kingdom. Shall we ride out?"},
	"yoshi": {"name": "Yoshi", "frames": 8, "hp": 18, "pow": 4, "def": 1, "recruit": 0.4, "move": "ground_pound",
		"line": "Yoshi! Yoshi! (He looks ready for an adventure.)"},
}

const ENEMIES := {
	"goomba": {"name": "Goomba", "frames": 8, "hp": 10, "pow": 4, "def": 0, "xp": 4, "coins": 3,
		"recruit": 0.4, "move": "headbonk"},
	"beanie": {"name": "Beanie", "frames": 8, "hp": 14, "pow": 5, "def": 1, "xp": 6, "coins": 5,
		"recruit": 0.3, "move": "bean_bash"},
	"galoomba": {"name": "Galoomba", "frames": 8, "hp": 9, "pow": 3, "def": 0, "xp": 3, "coins": 2,
		"recruit": 0.45, "move": "rolling_bump"},
	"koopa": {"name": "Koopa Troopa", "frames": 5, "hp": 14, "pow": 4, "def": 2, "xp": 6, "coins": 4,
		"recruit": 0.35, "move": "shell_toss"},
	"shy_guy": {"name": "Shy Guy", "frames": 6, "hp": 12, "pow": 5, "def": 1, "xp": 5, "coins": 4,
		"recruit": 0.35, "move": "shy_spin"},
	"buzzy_beetle": {"name": "Buzzy Beetle", "frames": 8, "hp": 12, "pow": 4, "def": 4, "xp": 7, "coins": 5,
		"recruit": 0.3, "move": "shell_spin"},
	"dry_bones": {"name": "Dry Bones", "frames": 5, "hp": 16, "pow": 5, "def": 2, "xp": 10, "coins": 7,
		"recruit": 0.25, "move": "bone_toss"},
}

## Townsfolk you can talk to (sheets cut by tools/slice_sprites.py, same
## layout as everyone else). What they say lives in res://data/dialogue.json.
const NPCS := {
	"bean_elder": {"name": "Beanish Elder", "frames": 1},
	"bean_villager": {"name": "Beanish", "frames": 1},
	"bean_kid": {"name": "Beanish Kid", "frames": 1},
	"bean_girl": {"name": "Beanette", "frames": 1},
	"bean_guard": {"name": "Beanbean Guard", "frames": 8},
	"shopkeeper": {"name": "Shopkeeper", "frames": 5},
	"toad_blue": {"name": "Toad", "frames": 8},
	"toadsworth": {"name": "Toadsworth", "frames": 8},
	"dr_toad": {"name": "Dr. Toad", "frames": 8},
	"lady_lima": {"name": "Lady Lima", "frames": 5},
	"queen_bean": {"name": "Queen Bean", "frames": 1},
	"koopa_troop": {"name": "Koopa Troop", "frames": 8},
	"koopa_troop_red": {"name": "Koopa Troop", "frames": 8},
	"border_bro": {"name": "Border Bro", "frames": 4},
	"hoohoo_villager": {"name": "Hoohoo Villager", "frames": 5},
	"hoohoo_villager_b": {"name": "Hoohoo Villager", "frames": 5},
}

## Items: the save keeps how many of each you carry (Game.player["items"],
## id -> count; see item_count / add_item). Pictures are
## res://assets/items/<id>.png (tools/slice_items.py). `price` is what shops
## charge (they buy back at half). What an item does:
##   hp: heals one ally that much;  sp: refills your SP that much
##   revive: brings a partner who is down back with that share of their HP
##   cure: clears burns and dizziness;  pow / def: raise one ally's stat for
##   the rest of the battle.
## `battle`: only works in battle (greyed out in the pause menu).
const ITEMS := {
	"mushroom": {"name": "Mushroom", "price": 8, "hp": 10, "info": "Restores 10 HP."},
	"super_mushroom": {"name": "Super Mushroom", "price": 20, "hp": 25, "info": "Restores 25 HP."},
	"ultra_mushroom": {"name": "Ultra Mushroom", "price": 40, "hp": 50, "info": "Restores 50 HP."},
	"syrup": {"name": "Syrup", "price": 10, "sp": 10, "info": "Restores 10 SP."},
	"super_syrup": {"name": "Super Syrup", "price": 25, "sp": 25, "info": "Restores 25 SP."},
	"one_up": {"name": "1-Up Mushroom", "price": 30, "revive": 0.5, "battle": true,
		"info": "Revives a fallen ally with half HP."},
	"refreshing_herb": {"name": "Refreshing Herb", "price": 12, "cure": true, "battle": true,
		"info": "Cures burns and dizziness."},
	"red_pepper": {"name": "Red Pepper", "price": 18, "pow": 3, "battle": true,
		"info": "POW +3 until the battle ends."},
	"green_pepper": {"name": "Green Pepper", "price": 18, "def": 3, "battle": true,
		"info": "DEF +3 until the battle ends."},
}
## Menus list items in this order.
const ITEM_ORDER := ["mushroom", "super_mushroom", "ultra_mushroom", "syrup", "super_syrup", "one_up",
	"refreshing_herb", "red_pepper", "green_pepper"]
const MAX_ITEM := 99  # most of one item you can carry

## What enemies sometimes leave behind after a battle: [item, chance].
const DROPS := {
	"goomba": ["mushroom", 0.15],
	"galoomba": ["mushroom", 0.15],
	"beanie": ["syrup", 0.15],
	"koopa": ["mushroom", 0.2],
	"shy_guy": ["refreshing_herb", 0.15],
	"buzzy_beetle": ["green_pepper", 0.12],
	"dry_bones": ["super_mushroom", 0.15],
}

## Bosses (phase 7). Each stands on its map (`map`, `pos`, `face`) and you
## talk to it to fight; world.gd shows them, battle.gd runs their attacks
## (BOSS_ATTACKS). A boss stays beaten in the save (player["bosses"]: id ->
## wins) and can be fought again for smaller rewards. `level`: the level we
## suggest. `reward` / `rematch_reward`: [item, count] on top of xp and coins
## (halved for a rematch). `attacks` are used from the start, `phase2` joins
## them once the boss is down to half HP (it also gets stronger and faster).
## Evil players can ask a beaten boss to join (one boss per party);
## `partner` is what it brings to the party then.
const BOSSES := {
	"popple": {"name": "Popple", "frames": 5, "hp": 64, "pow": 6, "def": 1, "xp": 40, "coins": 40, "level": 3,
		"map": "outskirts", "pos": Vector2(1300, 222), "face": "left", "battle_bg": "outskirts",
		"reward": ["super_mushroom", 2], "rematch_reward": ["mushroom", 1], "recruit": 0.05,
		"attacks": ["sack_snatch", "bobomb_toss"], "phase2": "hammer_leap",
		"intro": ["Hold it! I'm Popple, the Shadow Thief, see?",
			"Everything in these Outskirts is mine to swipe, including your coins! Hand 'em over!"],
		"rematch": ["You again?! Popple never forgets a mark, see? Ready for another round?"],
		"battle_line": "Popple: Your coins are as good as mine!",
		"phase_line": "Popple is fired up! His hammer comes out!",
		"won_line": "Popple: Nyeh! This ain't over, see?",
		"partner": {"hp": 22, "pow": 6, "def": 2, "move": "sack_swipe"}},
	"tolstar": {"name": "Tolstar", "frames": 10, "hp": 96, "pow": 8, "def": 2, "xp": 70, "coins": 60, "level": 7,
		"map": "stardust_fields", "pos": Vector2(440, 352), "face": "left", "battle_bg": "sand_bird",
		"reward": ["super_syrup", 2], "rematch_reward": ["syrup", 1], "recruit": 0.04,
		"attacks": ["spike_ball", "belly_flop"], "phase2": "star_fall",
		"intro": ["HOLD IT! I am Tolstar, keeper of every star in these fields!",
			"Nobody walks on MY stardust without paying a toll. You'll pay in bruises!"],
		"rematch": ["Back to pay the toll again? Tolstar always collects!"],
		"battle_line": "Tolstar: Pay the toll, small fry!",
		"phase_line": "Tolstar is furious! The stars begin to fall!",
		"won_line": "Tolstar: My stars... my precious stardust...",
		"partner": {"hp": 30, "pow": 7, "def": 3, "move": "spike_toss"}},
	"dragohoho": {"name": "Dragohoho", "frames": 9, "hp": 128, "pow": 10, "def": 3, "xp": 110, "coins": 80, "level": 11,
		"map": "hoohoo_village", "pos": Vector2(586, 140), "face": "left", "battle_bg": "hoohoo_mountain",
		"reward": ["ultra_mushroom", 1], "rematch_reward": ["red_pepper", 1], "recruit": 0.03,
		"attacks": ["fire_breath_boss", "horn_charge"], "phase2": "hoho_rockfall",
		"intro": ["HOOHOO! I am Dragohoho, the flame of Hoohoo Mountain!",
			"The path to the summit is mine. Turn back, or be roasted!"],
		"rematch": ["HOOHOO! You climbed all the way back up? Then burn again!"],
		"battle_line": "Dragohoho: HOOHOO! Feel my fire!",
		"phase_line": "Dragohoho roars! The mountain shakes and Hoho stones start to fall!",
		"won_line": "Dragohoho: Hoo... hoo... the flame... goes out...",
		"partner": {"hp": 34, "pow": 8, "def": 3, "move": "dragon_fire"}},
	"wart": {"name": "Wart", "frames": 7, "hp": 170, "pow": 12, "def": 4, "xp": 160, "coins": 120, "level": 15,
		"map": "bowser_castle", "pos": Vector2(205, 160), "face": "down", "battle_bg": "wart_throne",
		"reward": ["one_up", 1], "rematch_reward": ["super_mushroom", 1], "recruit": 0.03,
		"attacks": ["bubble_spray", "royal_stomp"], "phase2": "bubble_storm",
		"intro": ["GWAH HA HA! King Wart has taken over this castle!",
			"Bowser? He's out. This throne is MINE now, and so is the Beanbean Kingdom!"],
		"rematch": ["GWAH! You want another taste of my royal bubbles?"],
		"battle_line": "Wart: Bow before the king of Subcon!",
		"phase_line": "Wart is livid! Bubbles everywhere!",
		"won_line": "Wart: I... hate... vegetables... GWAAAH!",
		"partner": {"hp": 38, "pow": 9, "def": 4, "move": "bubble_blast"}},
}
## Boss attacks (battle.gd _boss_turn). kind: "dash" (runs at you: {a} to
## jump over it), "slam" (leaps onto you: {a} to jump out of the way),
## "volley" (`count` things thrown at you: {a} just before each hits to
## hammer it back at the boss) or "rain" (something falls on every ally:
## {a} to jump each). power: added to the boss's POW. steal: coins it grabs
## when it hits (you get them back if you win). burn: chance a hit burns.
const BOSS_ATTACKS := {
	"sack_snatch": {"name": "Sack Snatch", "kind": "dash", "power": 0, "steal": 4},
	"bobomb_toss": {"name": "Bob-omb Toss", "kind": "volley", "count": 2, "power": 1, "color": Color(0.95, 0.3, 0.45)},
	"hammer_leap": {"name": "Hammer Leap", "kind": "slam", "power": 3},
	"spike_ball": {"name": "Spike Ball", "kind": "volley", "count": 2, "power": 1, "color": Color(0.55, 0.55, 0.6)},
	"belly_flop": {"name": "Belly Flop", "kind": "slam", "power": 2},
	"star_fall": {"name": "Star Fall", "kind": "rain", "power": 1, "color": Color(1.0, 0.9, 0.3)},
	"fire_breath_boss": {"name": "Fire Breath", "kind": "volley", "count": 3, "power": 0, "burn": 0.3,
		"color": Color(1.0, 0.5, 0.1)},
	"horn_charge": {"name": "Horn Charge", "kind": "dash", "power": 2},
	"hoho_rockfall": {"name": "Hoho Rockfall", "kind": "rain", "power": 2, "color": Color(0.75, 0.5, 0.85)},
	"bubble_spray": {"name": "Bubble Spray", "kind": "volley", "count": 3, "power": 0, "color": Color(1.0, 0.6, 0.85)},
	"royal_stomp": {"name": "Royal Stomp", "kind": "slam", "power": 3},
	"bubble_storm": {"name": "Bubble Storm", "kind": "rain", "power": 2, "color": Color(1.0, 0.55, 0.8)},
}
## The chance a boss you just beat says yes when an evil player asks it to join.
const BOSS_JOIN_CHANCE := 0.35

## Maps: art and walk mask in res://assets/maps/ (built by tools/make_maps.py).
## battle_bg: res://assets/battle/backgrounds/<id>.png, behind battles started here.
## exits: walking into `rect` moves you to `to` at that map's `spawn` point.
## A `door` exit (a building's door) only opens while you push up into it.
## npcs: {id, pos, talk (dialogue id, defaults to id), face ("down", "left",
## "right" or "up"), fixed (stand exactly at pos, e.g. behind a counter),
## reach (talking distance, for counters)}.
const MAPS := {
	"castle_town": {
		"name": "Beanbean Castle Town", "battle_bg": "castle_town", "safe": true,
		"spawns": {"start": Vector2(320, 560), "east_gate": Vector2(1350, 409), "west_gate": Vector2(70, 409),
			"palace": Vector2(340, 135), "house_nw": Vector2(100, 272), "shop_badge": Vector2(500, 310),
			"house_sw": Vector2(147, 562), "house_s": Vector2(579, 547), "cafe": Vector2(902, 540),
			"house_ne_w": Vector2(1016, 205), "house_ne_e": Vector2(1146, 205), "shop_mushroom": Vector2(1096, 392),
			"house_se": Vector2(1303, 562)},
		"exits": [
			{"rect": Rect2(1430, 380, 22, 60), "to": "outskirts", "spawn": "south_path"},
			{"rect": Rect2(0, 380, 22, 60), "to": "outskirts", "spawn": "south_path"},
			{"rect": Rect2(320, 116, 40, 12), "to": "castle_hall", "spawn": "entrance", "door": true},
			{"rect": Rect2(84, 258, 32, 12), "to": "house_nw", "spawn": "door", "door": true},
			{"rect": Rect2(484, 296, 32, 12), "to": "shop_badge", "spawn": "door", "door": true},
			{"rect": Rect2(131, 548, 32, 12), "to": "house_sw", "spawn": "door", "door": true},
			{"rect": Rect2(563, 533, 32, 12), "to": "house_s", "spawn": "door", "door": true},
			{"rect": Rect2(886, 525, 32, 12), "to": "starbeans_cafe", "spawn": "door", "door": true},
			{"rect": Rect2(1000, 190, 33, 12), "to": "house_ne", "spawn": "door_w", "door": true},
			{"rect": Rect2(1130, 190, 33, 12), "to": "house_ne", "spawn": "door_e", "door": true},
			{"rect": Rect2(1080, 378, 32, 12), "to": "shop_mushroom", "spawn": "door", "door": true},
			{"rect": Rect2(1287, 548, 33, 12), "to": "house_se", "spawn": "door", "door": true},
		],
		"enemies": [],
		"npcs": [
			{"id": "toad", "pos": Vector2(435, 311)}, {"id": "pianta", "pos": Vector2(560, 330)},
			{"id": "bombette", "pos": Vector2(150, 290)}, {"id": "goombella", "pos": Vector2(640, 220)},
			{"id": "bobbery", "pos": Vector2(1000, 230)}, {"id": "peasley", "pos": Vector2(1180, 215)},
			{"id": "koops", "pos": Vector2(1120, 430)}, {"id": "bow", "pos": Vector2(980, 470)},
			{"id": "bean_guard", "pos": Vector2(300, 150), "talk": "palace_guard"},
			{"id": "bean_guard", "pos": Vector2(382, 150), "talk": "palace_guard"},
			{"id": "bean_villager", "pos": Vector2(90, 420), "talk": "town_gate", "face": "right"},
			{"id": "bean_kid", "pos": Vector2(640, 450), "talk": "town_kid"},
			{"id": "bean_girl", "pos": Vector2(1180, 400), "talk": "town_girl", "face": "left"},
			{"id": "toadsworth", "pos": Vector2(1330, 420), "talk": "toadsworth", "face": "left"},
			{"id": "bean_villager", "pos": Vector2(250, 300), "talk": "town_gossip"},
		],
	},
	"outskirts": {
		"name": "Beanbean Outskirts", "battle_bg": "outskirts", "safe": false,
		"spawns": {"south_path": Vector2(800, 615), "east_bridge": Vector2(1420, 65), "east_path": Vector2(1425, 405),
			"pier": Vector2(381, 612)},
		"exits": [
			{"rect": Rect2(760, 630, 90, 7), "to": "castle_town", "spawn": "east_gate"},
			{"rect": Rect2(1455, 30, 10, 70), "to": "bowser_castle", "spawn": "bridge"},
			{"rect": Rect2(1452, 380, 13, 50), "to": "outskirts_east", "spawn": "west"},
			{"rect": Rect2(362, 630, 38, 7), "to": "outskirts_pier", "spawn": "north"},
		],
		"enemies": [
			{"type": "goomba", "pos": Vector2(628, 178)}, {"type": "goomba", "pos": Vector2(607, 345)},
			{"type": "beanie", "pos": Vector2(1046, 178)}, {"type": "goomba", "pos": Vector2(816, 492)},
			{"type": "beanie", "pos": Vector2(1004, 544)}, {"type": "beanie", "pos": Vector2(1318, 345)},
			{"type": "koopa", "pos": Vector2(700, 222)}, {"type": "shy_guy", "pos": Vector2(883, 302)},
			{"type": "buzzy_beetle", "pos": Vector2(1150, 250)}, {"type": "galoomba", "pos": Vector2(678, 545)},
			{"type": "dry_bones", "pos": Vector2(1250, 130)}, {"type": "koopa", "pos": Vector2(1240, 457)},
			{"type": "shy_guy", "pos": Vector2(1100, 600)}, {"type": "galoomba", "pos": Vector2(548, 447)},
			# The west islands, reached by jumping onto the hedge and the flat tree tops.
			{"type": "koopa", "pos": Vector2(380, 270)}, {"type": "beanie", "pos": Vector2(120, 215)},
			{"type": "galoomba", "pos": Vector2(100, 560)}, {"type": "shy_guy", "pos": Vector2(380, 590)},
		],
		"npcs": [{"id": "yoshi_kid", "pos": Vector2(765, 285)}, {"id": "yoshi", "pos": Vector2(1380, 180)}],
	},
	"bowser_castle": {
		"name": "Bowser's Castle", "battle_bg": "bowser_castle", "safe": true,
		"spawns": {"start": Vector2(205, 250), "bridge": Vector2(205, 580)},
		"exits": [{"rect": Rect2(170, 605, 70, 10), "to": "outskirts", "spawn": "east_bridge"}],
		"enemies": [],
		"npcs": [
			{"id": "koopa_troop", "pos": Vector2(140, 240), "talk": "koopa_guard", "face": "right"},
			{"id": "koopa_troop", "pos": Vector2(270, 240), "talk": "koopa_guard", "face": "left"},
			{"id": "koopa_troop_red", "pos": Vector2(125, 330), "talk": "koopa_shop", "face": "right"},
			{"id": "border_bro", "pos": Vector2(285, 330), "talk": "bowser_gatekeeper", "face": "left"},
		],
	},
	# Castle Town buildings. Each door mat leads back out to its door.
	"house_nw": {
		"name": "Elder's House", "safe": true,
		"spawns": {"door": Vector2(106, 216)},
		"exits": [{"rect": Rect2(92, 232, 28, 14), "to": "castle_town", "spawn": "house_nw"}],
		"enemies": [],
		"npcs": [{"id": "bean_elder", "pos": Vector2(60, 160), "talk": "elder_rest"}],
	},
	"house_sw": {
		"name": "Beanish House", "safe": true,
		"spawns": {"door": Vector2(106, 216)},
		"exits": [{"rect": Rect2(92, 232, 28, 14), "to": "castle_town", "spawn": "house_sw"}],
		"enemies": [],
		"npcs": [{"id": "bean_villager", "pos": Vector2(140, 170), "talk": "house_bean"}],
	},
	"house_s": {
		"name": "Toad Lodge", "safe": true,
		"spawns": {"door": Vector2(106, 216)},
		"exits": [{"rect": Rect2(92, 232, 28, 14), "to": "castle_town", "spawn": "house_s"}],
		"enemies": [],
		"npcs": [{"id": "toad_blue", "pos": Vector2(70, 170), "talk": "lodge_toad"}],
	},
	"house_se": {
		"name": "Dr. Toad's Clinic", "safe": true,
		"spawns": {"door": Vector2(106, 220)},
		"exits": [{"rect": Rect2(92, 236, 28, 14), "to": "castle_town", "spawn": "house_se"}],
		"enemies": [],
		"npcs": [{"id": "dr_toad", "pos": Vector2(106, 165), "talk": "dr_toad"}],
	},
	"house_ne": {
		"name": "Beanbean Town Hall", "safe": true,
		"spawns": {"door_w": Vector2(106, 212), "door_e": Vector2(314, 212)},
		"exits": [
			{"rect": Rect2(92, 228, 28, 14), "to": "castle_town", "spawn": "house_ne_w"},
			{"rect": Rect2(300, 228, 28, 14), "to": "castle_town", "spawn": "house_ne_e"},
		],
		"enemies": [],
		"npcs": [
			{"id": "bean_elder", "pos": Vector2(200, 165), "talk": "mayor"},
			{"id": "bean_kid", "pos": Vector2(300, 180), "talk": "town_hall_kid", "face": "left"},
		],
	},
	"shop_mushroom": {
		"name": "Mushroom Shop", "safe": true,
		"spawns": {"door": Vector2(56, 222)},
		"exits": [{"rect": Rect2(40, 238, 32, 14), "to": "castle_town", "spawn": "shop_mushroom"}],
		"enemies": [],
		"npcs": [{"id": "shopkeeper", "pos": Vector2(130, 96), "talk": "mushroom_shop", "fixed": true, "reach": 56.0}],
	},
	"shop_badge": {
		"name": "Badge Shop", "safe": true,
		"spawns": {"door": Vector2(57, 222)},
		"exits": [{"rect": Rect2(41, 238, 32, 14), "to": "castle_town", "spawn": "shop_badge"}],
		"enemies": [],
		"npcs": [{"id": "shopkeeper", "pos": Vector2(130, 96), "talk": "badge_shop", "fixed": true, "reach": 56.0}],
	},
	"starbeans_cafe": {
		"name": "Starbeans Cafe", "safe": true,
		"spawns": {"door": Vector2(248, 228)},
		"exits": [{"rect": Rect2(226, 250, 44, 14), "to": "castle_town", "spawn": "cafe"}],
		"enemies": [],
		"npcs": [
			{"id": "bean_villager", "pos": Vector2(300, 160), "talk": "cafe_barista", "face": "left"},
			{"id": "bean_girl", "pos": Vector2(130, 185), "talk": "cafe_customer", "face": "right"},
		],
	},
	"castle_hall": {
		"name": "Beanbean Castle", "safe": true,
		"spawns": {"entrance": Vector2(224, 286), "arch": Vector2(224, 125)},
		"exits": [
			{"rect": Rect2(192, 300, 65, 13), "to": "castle_town", "spawn": "palace"},
			{"rect": Rect2(198, 92, 52, 16), "to": "throne_room", "spawn": "south", "door": true},
		],
		"enemies": [],
		"npcs": [
			{"id": "bean_guard", "pos": Vector2(175, 135), "talk": "castle_guard"},
			{"id": "bean_guard", "pos": Vector2(275, 135), "talk": "castle_guard"},
			{"id": "lady_lima", "pos": Vector2(330, 240), "talk": "lady_lima", "face": "left"},
		],
	},
	"throne_room": {
		"name": "Throne Room", "safe": true,
		"spawns": {"south": Vector2(107, 435)},
		"exits": [{"rect": Rect2(82, 455, 50, 13), "to": "castle_hall", "spawn": "arch"}],
		"enemies": [],
		"npcs": [
			{"id": "queen_bean", "pos": Vector2(107, 225), "talk": "queen_bean"},
			{"id": "bean_guard", "pos": Vector2(60, 300), "talk": "throne_guard", "face": "right"},
		],
	},
	# Beyond the Outskirts: Stardust Fields (wild) and Hoohoo Village (a town).
	"stardust_fields": {
		"name": "Stardust Fields", "battle_bg": "stardust_fields", "safe": false,
		"spawns": {"west_low": Vector2(40, 590), "west_high": Vector2(30, 418), "north": Vector2(205, 30),
			"east": Vector2(495, 134)},
		"exits": [
			{"rect": Rect2(0, 568, 12, 36), "to": "outskirts_east", "spawn": "north"},
			{"rect": Rect2(0, 400, 12, 36), "to": "outskirts_east", "spawn": "north"},
			{"rect": Rect2(180, 0, 50, 10), "to": "hoohoo_village", "spawn": "south"},
			{"rect": Rect2(515, 118, 15, 32), "to": "hoohoo_village", "spawn": "west"},
		],
		"enemies": [
			{"type": "goomba", "pos": Vector2(60, 200)}, {"type": "koopa", "pos": Vector2(200, 232)},
			{"type": "shy_guy", "pos": Vector2(344, 160)}, {"type": "buzzy_beetle", "pos": Vector2(420, 300)},
			{"type": "dry_bones", "pos": Vector2(300, 380)}, {"type": "galoomba", "pos": Vector2(85, 338)},
			{"type": "beanie", "pos": Vector2(377, 123)}, {"type": "shy_guy", "pos": Vector2(230, 400)},
			{"type": "buzzy_beetle", "pos": Vector2(440, 200)}, {"type": "koopa", "pos": Vector2(140, 520)},
		],
		"npcs": [
			{"id": "border_bro", "pos": Vector2(160, 58), "talk": "border_bro"},
			{"id": "hoohoo_villager_b", "pos": Vector2(90, 600), "talk": "stardust_traveler", "face": "left"},
		],
	},
	"hoohoo_village": {
		"name": "Hoohoo Village", "battle_bg": "hoohoo_mountain", "safe": true,
		"spawns": {"west": Vector2(20, 112), "south": Vector2(527, 415), "hut_w": Vector2(233, 148),
			"hut_e": Vector2(456, 148)},
		"exits": [
			{"rect": Rect2(0, 92, 10, 40), "to": "stardust_fields", "spawn": "east"},
			{"rect": Rect2(508, 428, 40, 16), "to": "stardust_fields", "spawn": "north"},
			{"rect": Rect2(219, 134, 28, 12), "to": "hoohoo_hut_w", "spawn": "door", "door": true},
			{"rect": Rect2(442, 134, 28, 12), "to": "hoohoo_hut_e", "spawn": "door", "door": true},
		],
		"enemies": [],
		"npcs": [
			{"id": "hoohoo_villager", "pos": Vector2(90, 115), "talk": "hoohoo_greeter"},
			{"id": "hoohoo_villager_b", "pos": Vector2(345, 110), "talk": "hoohoo_deck"},
			{"id": "hoohoo_villager_b", "pos": Vector2(685, 215), "talk": "hoohoo_mountain", "face": "left"},
			{"id": "hoohoo_villager", "pos": Vector2(300, 400), "talk": "hoohoo_cave", "face": "left"},
		],
	},
	"hoohoo_hut_w": {
		"name": "Hoohoo Hut", "safe": true,
		"spawns": {"door": Vector2(161, 212)},
		"exits": [{"rect": Rect2(146, 228, 31, 14), "to": "hoohoo_village", "spawn": "hut_w"}],
		"enemies": [],
		"npcs": [{"id": "hoohoo_villager", "pos": Vector2(100, 180), "talk": "hut_rest"}],
	},
	"hoohoo_hut_e": {
		"name": "Hoohoo Hut", "safe": true,
		"spawns": {"door": Vector2(42, 212)},
		"exits": [{"rect": Rect2(26, 228, 32, 14), "to": "hoohoo_village", "spawn": "hut_e"}],
		"enemies": [],
		"npcs": [{"id": "hoohoo_villager_b", "pos": Vector2(100, 180), "talk": "hoohoo_shop"}],
	},
	# Phase 7: more of the Outskirts (tools/make_maps.py cuts them so their
	# edges meet the Outskirts map).
	"outskirts_east": {
		"name": "Outskirts Meadow", "battle_bg": "outskirts", "safe": false,
		"spawns": {"west": Vector2(30, 450), "north": Vector2(383, 30), "south": Vector2(197, 505)},
		"exits": [
			{"rect": Rect2(0, 413, 8, 79), "to": "outskirts", "spawn": "east_path"},
			{"rect": Rect2(351, 0, 64, 8), "to": "stardust_fields", "spawn": "west_low"},
			{"rect": Rect2(139, 530, 117, 8), "to": "outskirts_woods", "spawn": "north"},
		],
		"enemies": [
			{"type": "goomba", "pos": Vector2(300, 350)}, {"type": "beanie", "pos": Vector2(520, 300)},
			{"type": "koopa", "pos": Vector2(560, 420)}, {"type": "galoomba", "pos": Vector2(900, 400)},
			{"type": "shy_guy", "pos": Vector2(1100, 380)}, {"type": "buzzy_beetle", "pos": Vector2(1180, 260)},
			{"type": "koopa", "pos": Vector2(860, 120)},
		],
		"npcs": [
			{"id": "bean_villager", "pos": Vector2(330, 250), "talk": "meadow_bean"},
			{"id": "toad_blue", "pos": Vector2(1200, 200), "talk": "beach_toad", "face": "right"},
		],
	},
	"outskirts_woods": {
		"name": "Outskirts Woods", "battle_bg": "outskirts", "safe": false,
		"spawns": {"north": Vector2(133, 25)},
		"exits": [{"rect": Rect2(75, 0, 118, 8), "to": "outskirts_east", "spawn": "south"}],
		"enemies": [
			{"type": "goomba", "pos": Vector2(300, 150)}, {"type": "shy_guy", "pos": Vector2(480, 200)},
			{"type": "dry_bones", "pos": Vector2(660, 120)}, {"type": "galoomba", "pos": Vector2(100, 520)},
			{"type": "buzzy_beetle", "pos": Vector2(400, 550)}, {"type": "beanie", "pos": Vector2(560, 520)},
		],
		"npcs": [{"id": "bean_kid", "pos": Vector2(60, 180), "talk": "woods_kid"}],
	},
	"outskirts_pier": {
		"name": "Outskirts Pier", "battle_bg": "outskirts", "safe": true,
		"spawns": {"north": Vector2(233, 22)},
		"exits": [{"rect": Rect2(220, 0, 26, 6), "to": "outskirts", "spawn": "pier"}],
		"enemies": [],
		"npcs": [
			{"id": "shopkeeper", "pos": Vector2(350, 468), "talk": "pier_shop", "fixed": true, "reach": 56.0},
			{"id": "bean_elder", "pos": Vector2(100, 470), "talk": "pier_rest", "face": "right"},
		],
	},
}

const HOME_MAP := {"good": "castle_town", "evil": "bowser_castle"}

var player := {}          # the saved player, see new_player()
var pending_battle := {}  # set by the world right before a battle starts
var defeated := {}        # "map:index" -> time it was beaten (enemies respawn)
const RESPAWN_SECONDS := 45.0


func _ready() -> void:
	_add_action("move_left", [KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT])
	_add_action("move_right", [KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT])
	_add_action("move_up", [KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP])
	_add_action("move_down", [KEY_DOWN, KEY_S], [JOY_BUTTON_DPAD_DOWN])
	_add_action("action", [KEY_Z, KEY_J, KEY_SPACE], [JOY_BUTTON_A])  # jump, confirm, timed hits
	_add_action("talk", [KEY_X, KEY_K], [JOY_BUTTON_B])  # talk / ask, cancel in menus
	_add_action("menu", [KEY_ENTER, KEY_ESCAPE], [JOY_BUTTON_START])
	_add_action("chat", [KEY_T, KEY_SLASH], [])


func _add_action(action: String, keys: Array, buttons: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
	for button in buttons:
		var jev := InputEventJoypadButton.new()
		jev.button_index = button
		InputMap.action_add_event(action, jev)


# --- Player ---------------------------------------------------------------

func new_player(character_id: String, username := "") -> void:
	var c: Dictionary = CHARACTERS[character_id]
	player = {
		"username": clean_username(username), "uid": new_uid(), "character": character_id, "side": c["side"], "level": 1, "xp": 0, "coins": 20,
		"max_hp": c["hp"], "hp": c["hp"], "max_sp": c["sp"], "sp": c["sp"], "pow": c["pow"], "def": c["def"],
		"items": {"mushroom": 3}, "party": [], "map": HOME_MAP[c["side"]], "spawn": "start", "position": null,
		"wins": 0,
	}
	save()


# --- Items ------------------------------------------------------------------

func item_count(id: String) -> int:
	return int(player.get("items", {}).get(id, 0))


## Adds (or with a negative amount, takes away) items; returns how many were
## actually added (you can carry up to MAX_ITEM of each).
func add_item(id: String, amount := 1) -> int:
	if not ITEMS.has(id):
		return 0
	if not player.has("items"):
		player["items"] = {}
	var before := item_count(id)
	var after := clampi(before + amount, 0, MAX_ITEM)
	if after == 0:
		player["items"].erase(id)
	else:
		player["items"][id] = after
	return after - before


## The ids of the items you carry, in menu order.
func owned_items() -> Array:
	return ITEM_ORDER.filter(func(id): return item_count(id) > 0)


## "a Mushroom", "an Ultra Mushroom".
func with_article(item_name: String) -> String:
	return ("an " if item_name.left(1).to_lower() in ["a", "e", "i", "o", "u"] else "a ") + item_name


## What a shop pays for one of an item.
func sell_price(id: String) -> int:
	return maxi(1, int(ITEMS[id]["price"]) / 2)


## Rolls the item drops for beaten enemies (types); adds them to the
## inventory and returns their ids (one per drop).
func roll_drops(types: Array) -> Array:
	var got := []
	for t in types:
		var d: Array = DROPS.get(t, [])
		if not d.is_empty() and randf() < float(d[1]) and add_item(d[0]) > 0:
			got.append(d[0])
	return got


## Old saves counted Mushrooms only ("mushrooms": n). Moves that into the
## inventory and drops anything that isn't a known item.
func _migrate_items(data: Dictionary) -> void:
	var items := {}
	var saved = data.get("items", {})
	if typeof(saved) == TYPE_DICTIONARY:
		for id in saved:
			if ITEMS.has(id) and int(saved[id]) > 0:
				items[id] = mini(int(saved[id]), MAX_ITEM)
	if data.has("mushrooms"):
		var old := int(data["mushrooms"])
		if old > 0:
			items["mushroom"] = mini(int(items.get("mushroom", 0)) + old, MAX_ITEM)
		data.erase("mushrooms")
	data["items"] = items


func character_name() -> String:
	return CHARACTERS[player["character"]]["name"]


## The name other players see over your head. Falls back to the character's
## name for saves made before usernames existed.
func username() -> String:
	var u: String = player.get("username", "")
	return u if u != "" else character_name()


## A random id that stays the same for this save, so your party partner can
## find you again on the next map.
func new_uid() -> String:
	var bytes := Crypto.new().generate_random_bytes(6)
	return bytes.hex_encode()


## Same rule as the server: letters, numbers, spaces and _ . ' - , max 16.
func clean_username(text: String) -> String:
	var re := RegEx.create_from_string("[^\\p{L}\\p{N} _.'-]")
	return re.sub(text, "", true).strip_edges().left(16)


func xp_to_next(level: int) -> int:
	return int(round(8.0 * pow(level, 1.5)))


## Adds XP; returns how many levels were gained.
func gain_xp(amount: int) -> int:
	var gained := 0
	player["xp"] += amount
	while player["level"] < MAX_LEVEL and player["xp"] >= xp_to_next(player["level"]):
		player["xp"] -= xp_to_next(player["level"])
		player["level"] += 1
		player["max_hp"] += 3
		player["max_sp"] += 2
		player["pow"] += 1
		if player["level"] % 2 == 0:
			player["def"] += 1
		player["hp"] = player["max_hp"]
		player["sp"] = player["max_sp"]
		for member in player["party"]:
			member["max_hp"] += 2
			member["hp"] = member["max_hp"]
			member["pow"] += 1
		gained += 1
	return gained


## Builds a party member from a partner or enemy id.
func make_member(kind: String, id: String) -> Dictionary:
	var src: Dictionary = PARTNERS[id] if kind == "partner" else ENEMIES.get(id, {})
	if kind == "boss":
		src = BOSSES[id]["partner"].merged({"name": BOSSES[id]["name"]})
	return {"kind": kind, "id": id, "name": src["name"], "max_hp": src["hp"], "hp": src["hp"],
		"pow": src["pow"], "def": src["def"]}


## The move (MOVES id) a party member uses on its turn, or an enemy is known for.
func move_of(kind: String, id: String) -> String:
	var src: Dictionary = PARTNERS.get(id, {}) if kind == "partner" else ENEMIES.get(id, {})
	if kind == "boss":
		src = BOSSES.get(id, {}).get("partner", {})
	return src.get("move", "rolling_bump")


func can_recruit() -> bool:
	return player["party"].size() < MAX_PARTY


func switch_side() -> void:
	# Prototype rule: switching sides swaps to the other side's first character
	# and sends you to that side's home. Levels, coins and items are kept.
	var other := "evil" if player["side"] == "good" else "good"
	for id in CHARACTERS:
		if CHARACTERS[id]["side"] == other:
			player["character"] = id
			break
	player["side"] = other
	player["party"] = []
	if Net.party_id != "":
		Net.leave_party()  # good and evil can't be a party (the server ends it too)
	go_to_map(HOME_MAP[other], "start")


# --- Moving between scenes ---------------------------------------------------

func go_to_map(map_id: String, spawn: String) -> void:
	player["map"] = map_id
	player["spawn"] = spawn
	player["position"] = null
	save()
	get_tree().call_deferred("change_scene_to_file", WORLD_SCENE)


func start_battle(enemies: Array, defeated_key: String, overworld_position: Vector2) -> void:
	player["position"] = [overworld_position.x, overworld_position.y]
	pending_battle = {"enemies": enemies, "key": defeated_key}
	# With your partner on this map, they're pulled into the fight too.
	var scene := COOP_SCENE if Net.party_here and Net.is_online() else BATTLE_SCENE
	BattleTransition.into_battle(get_tree(), scene)


## Your partner started a battle and asked you in (see coop_guest.gd).
func join_coop(start: Dictionary, overworld_position: Vector2) -> void:
	player["position"] = [overworld_position.x, overworld_position.y]
	pending_battle = {"coop": start, "key": ""}
	# at_once: their battle sends its setup as soon as you say yes, so the
	# battle loads straight away and the swipe plays over a still of the map.
	BattleTransition.into_battle(get_tree(), COOP_GUEST_SCENE, true)


## What a foe sees of you in an online duel (sent through the server).
func pvp_stats() -> Dictionary:
	var out := {}
	for key in ["hp", "max_hp", "sp", "max_sp", "pow", "def", "level", "coins"]:
		out[key] = player[key]
	return out


## An online duel with another player. foe: {id, name, character, stats}.
func start_pvp(foe: Dictionary, first: bool, overworld_position: Vector2) -> void:
	player["position"] = [overworld_position.x, overworld_position.y]
	pending_battle = {"pvp": foe, "first": first, "key": ""}
	player["in_duel"] = true  # cleared when the duel ends; quitting mid-duel counts as a loss
	save()
	BattleTransition.into_battle(get_tree(), PVP_SCENE)


## Coins a player drops when they lose a duel (the winner picks them up).
func pvp_drop(coins: int) -> int:
	return coins - int(coins * 0.9)


## result: "won", "lost" or "fled".
func end_battle(result: String) -> void:
	player.erase("in_duel")
	if result == "won":
		defeated[pending_battle["key"]] = Time.get_ticks_msec() / 1000.0
	if result == "lost":
		# Back to your home town with a few coins lost; items and levels stay.
		player["coins"] = int(player["coins"] * 0.9)
		player["hp"] = player["max_hp"]
		player["sp"] = player["max_sp"]
		for member in player["party"]:
			member["hp"] = member["max_hp"]
		pending_battle = {}
		go_to_map(HOME_MAP[player["side"]], "start")
		return
	pending_battle = {}
	save()
	get_tree().call_deferred("change_scene_to_file", WORLD_SCENE)


func is_defeated(key: String) -> bool:
	if not defeated.has(key):
		return false
	if Time.get_ticks_msec() / 1000.0 - defeated[key] > RESPAWN_SECONDS:
		defeated.erase(key)
		return false
	return true


# --- Bosses -------------------------------------------------------------------

## An enemy's or a boss's table entry (ENEMIES, then BOSSES).
func foe_info(type: String) -> Dictionary:
	return ENEMIES.get(type, BOSSES.get(type, {}))


## How many times you have beaten boss `id` (0: never). Old saves have none.
func boss_wins(id: String) -> int:
	var b = player.get("bosses", {})
	return int(b.get(id, 0)) if typeof(b) == TYPE_DICTIONARY else 0


func mark_boss_beaten(id: String) -> void:
	if typeof(player.get("bosses")) != TYPE_DICTIONARY:
		player["bosses"] = {}
	player["bosses"][id] = boss_wins(id) + 1


## True if a boss is already in your party (each party can have one).
func has_boss_partner() -> bool:
	return player.get("party", []).any(func(m): return m.get("kind", "") == "boss")


## Starts a fight with boss `id` (from talking to it on the map).
func start_boss(id: String, overworld_position: Vector2) -> void:
	start_battle([id], "boss:" + id, overworld_position)
	pending_battle["boss"] = id
	pending_battle["battle_bg"] = BOSSES[id].get("battle_bg", "outskirts")


# --- Saving (browser storage on the web build) -------------------------------

func save() -> void:
	if player.is_empty():
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(player))


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_save() -> bool:
	if not has_save():
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if not CHARACTERS.has(data.get("character", "")):
		# A character that left the game (Dimentio): play on as Bowser, or
		# whoever leads that side's list, keeping levels and items.
		var id: String = REMOVED_CHARACTERS.get(data.get("character", ""), "")
		if id == "":
			for c in CHARACTERS:
				if CHARACTERS[c]["side"] == data.get("side", ""):
					id = c
					break
		if id == "":
			return false
		data["character"] = id
		data["side"] = CHARACTERS[id]["side"]
	# JSON numbers come back as floats; keep whole-number stats as ints.
	for key in ["level", "xp", "coins", "max_hp", "hp", "max_sp", "sp", "pow", "def", "wins"]:
		data[key] = int(data.get(key, 0))
	_migrate_items(data)
	if typeof(data.get("bosses")) != TYPE_DICTIONARY:
		data.erase("bosses")  # boss wins (see boss_wins); old saves have none
	for member in data["party"]:
		for key in ["max_hp", "hp", "pow", "def"]:
			member[key] = int(member[key])
	if not data.has("uid"):
		data["uid"] = new_uid()
	if data.get("in_duel", false):
		# Closed the game mid-duel: that's a loss (coins dropped, back home).
		data.erase("in_duel")
		data["coins"] -= pvp_drop(data["coins"])
		data["hp"] = data["max_hp"]
		data["map"] = HOME_MAP.get(data.get("side", "good"), "castle_town")
		data["spawn"] = "start"
		data["position"] = null
	player = data
	return true


func continue_game() -> void:
	get_tree().call_deferred("change_scene_to_file", WORLD_SCENE)


## Returns the visible safe area rect in viewport canvas coordinates,
## accounting for phone screen notches, pills, rounded corners, and navigation bars.
func get_safe_rect() -> Rect2:
	var vp := get_viewport()
	if vp == null:
		return Rect2(0, 0, 384, 216)
	var vp_size := vp.get_visible_rect().size
	var safe := DisplayServer.get_display_safe_area()
	var win_size := DisplayServer.window_get_size()
	if win_size.x <= 0 or win_size.y <= 0 or safe.size.x <= 0:
		return Rect2(Vector2.ZERO, vp_size)
	var left_m := clampf(float(safe.position.x) / float(win_size.x), 0.0, 0.35)
	var top_m := clampf(float(safe.position.y) / float(win_size.y), 0.0, 0.35)
	var right_m := clampf(float(win_size.x - (safe.position.x + safe.size.x)) / float(win_size.x), 0.0, 0.35)
	var bottom_m := clampf(float(win_size.y - (safe.position.y + safe.size.y)) / float(win_size.y), 0.0, 0.35)
	return Rect2(
		vp_size.x * left_m,
		vp_size.y * top_m,
		vp_size.x * (1.0 - left_m - right_m),
		vp_size.y * (1.0 - top_m - bottom_m)
	)


## True if the screen is currently in portrait orientation (height > width).
func is_portrait() -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	var s := vp.get_visible_rect().size
	return s.y > s.x

