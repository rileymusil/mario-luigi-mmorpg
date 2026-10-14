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
const MAX_BENCH := 12  # partners or recruits waiting at your home base

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
	"bean_chomp": {"name": "Bean Chomp", "kind": "tackle", "bonus": 1,
		"info": "A big leafy chomp."},
	"crab_pinch": {"name": "Crab Pinch", "kind": "multi", "hits": 2, "bonus": 1,
		"info": "Up to 2 pinches, {a} in the gold zone for each."},
	"piranha_flame": {"name": "Piranha Flame", "kind": "throw", "color": Color(1.0, 0.45, 0.15), "burn": 2,
		"info": "Spits fire. Excellent burns the enemy."},
	"chain_chomp_toss": {"name": "Chain Toss", "kind": "throw", "color": Color(0.85, 0.2, 0.2), "bonus": 2, "pierce": true,
		"info": "Swings a chain ball. Excellent hits the next enemy too."},
	"chuckola_slash": {"name": "Chuckola Slash", "kind": "multi", "hits": 3,
		"info": "Up to 3 slashes, {a} in the gold zone for each."},
	"hoo_pillar": {"name": "Hoo Pillar", "kind": "stomp", "stun": true, "bonus": 1,
		"info": "Drops a stone pillar. {a} as it lands; Excellent stuns."},
	"trunk_slam": {"name": "Trunk Slam", "kind": "tackle", "bonus": 2,
		"info": "A huge trunk punch."},
	"egg_toss": {"name": "Egg Toss", "kind": "throw", "color": Color(1.0, 1.0, 0.95), "bonus": 2, "heal": 4,
		"info": "Shoots an egg. Excellent heals the party 4 HP."},
	"bowletta_breath": {"name": "Bowletta Breath", "kind": "blast", "bonus": 3, "burn": 2,
		"info": "Fire on every enemy. Excellent burns them."},
	"hypno_spark": {"name": "Hypno Spark", "kind": "throw", "color": Color(1.0, 0.5, 0.85), "stun": true,
		"info": "A dizzying spark. Excellent stuns."},
	"magic_bolt": {"name": "Magic Bolt", "kind": "throw", "color": Color(0.45, 0.6, 1.0), "ignore_def": true,
		"info": "A magic bolt that ignores DEF."},
	"frost_wand": {"name": "Frost Wand", "kind": "throw", "color": Color(0.6, 0.95, 1.0), "def_down": 2,
		"info": "Freezing beam. Excellent lowers DEF."},
	"royal_fist": {"name": "Royal Fist", "kind": "tackle", "bonus": 3, "stun": true,
		"info": "A royal punch. Excellent stuns."},
	"larry_flame": {"name": "Wand Flame", "kind": "throw", "color": Color(0.35, 0.55, 1.0), "bonus": 2,
		"info": "A blue wand blast."},
	"circus_ball": {"name": "Circus Ball", "kind": "stomp", "bonus": 2,
		"info": "Bounces a ball onto the enemy. {a} as it lands for a 2nd hit."},
	"morton_stomp": {"name": "Morton Stomp", "kind": "stomp", "bonus": 3, "stun": true,
		"info": "A heavy stomp. {a} as you land; Excellent stuns."},
	"ludwig_shell": {"name": "Shell Spin", "kind": "tackle", "bonus": 3, "def_down": 2,
		"info": "Spinning shell. Excellent lowers DEF."},
	"candy_ring": {"name": "Candy Ring", "kind": "throw", "color": Color(1.0, 0.85, 0.2), "bonus": 3, "pierce": true,
		"info": "Throws a ring. Excellent hits the next enemy too."},
	"iggy_whirl": {"name": "Iggy Whirl", "kind": "multi", "hits": 3, "bonus": 2,
		"info": "Up to 3 spins, {a} in the gold zone for each."},
	"roy_bash": {"name": "Roy Bash", "kind": "tackle", "bonus": 4, "stun": true,
		"info": "A shell bash. Excellent stuns."},
	"bat_bolt": {"name": "Bat Bolt", "kind": "blast", "bonus": 3, "stun": true,
		"info": "Bats hit every enemy. Excellent stuns them."},
	"fury_beam": {"name": "Fury Beam", "kind": "throw", "color": Color(0.4, 1.0, 0.4), "bonus": 3, "ignore_def": true,
		"info": "A beam that ignores DEF."},
	"soul_flare": {"name": "Soul Flare", "kind": "blast", "bonus": 4, "def_down": 2,
		"info": "Ghost fire on every enemy. Excellent lowers DEF."},
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

## Equipment: one pair of pants and one badge at a time, like Superstar
## Saga. Wearing them adds their stats (hp, sp, pow, def) to yours; taking
## them off takes them away again (see equip / unequip). Gear you carry is
## Game.player["gear"] (id -> count), what you wear player["equip"] (slot ->
## id). Shops sell it like items (`price`); pictures are
## res://assets/items/<id>.png (tools/slice_gear.py).
const GEAR := {
	"thin_pants": {"name": "Thin Pants", "slot": "pants", "price": 30, "def": 1,
		"info": "Plain, light pants. DEF +1."},
	"work_pants": {"name": "Work Pants", "slot": "pants", "price": 80, "def": 2, "hp": 4,
		"info": "Tough canvas for long trips. DEF +2, HP +4."},
	"heart_jeans": {"name": "Heart Jeans", "slot": "pants", "price": 160, "def": 3, "hp": 8,
		"info": "Jeans with a big heart. DEF +3, HP +8."},
	"koopa_pants": {"name": "Koopa Pants", "slot": "pants", "price": 150, "def": 3, "pow": 1,
		"info": "Shell-hard pants from Bowser's Castle. DEF +3, POW +1."},
	"mountain_pants": {"name": "Mountain Pants", "slot": "pants", "price": 320, "def": 5, "hp": 10,
		"info": "Woven by the Hoohoo folk. DEF +5, HP +10."},
	"heart_badge": {"name": "Heart Badge", "slot": "badge", "price": 70, "hp": 8,
		"info": "A badge full of pep. HP +8."},
	"power_badge": {"name": "Power Badge", "slot": "badge", "price": 60, "pow": 2,
		"info": "Hit harder. POW +2."},
	"sp_badge": {"name": "SP Badge", "slot": "badge", "price": 60, "sp": 6,
		"info": "More SP for special moves. SP +6."},
	"guard_badge": {"name": "Guard Badge", "slot": "badge", "price": 70, "def": 2,
		"info": "Shrug off hits. DEF +2."},
	"spiny_badge": {"name": "Spiny Badge", "slot": "badge", "price": 220, "pow": 3, "def": 1,
		"info": "Bowser's favourite. POW +3, DEF +1."},
	"great_badge": {"name": "Great Badge", "slot": "badge", "price": 360, "pow": 4, "sp": 6,
		"info": "A treasure of the mountain. POW +4, SP +6."},
}
const GEAR_ORDER := ["thin_pants", "work_pants", "heart_jeans", "koopa_pants", "mountain_pants",
	"heart_badge", "power_badge", "sp_badge", "guard_badge", "spiny_badge", "great_badge"]
const GEAR_SLOTS := ["pants", "badge"]
const MAX_GEAR := 9  # most of one piece of gear you can carry

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
## suggest. `reward` / `rematch_reward`: [item, count], or a list of them, on
## top of xp and coins (halved for a rematch). `attacks` are used from the
## start, `phase2` joins them once the boss is down to half HP (it also gets
## stronger and faster). Evil players can ask a beaten boss to join (one boss
## per party); `partner` is what it brings to the party then.
## Sheets: `frames` columns; `idle` frames loop while it stands, and
## `attack` (if set) is a 4th row played when it attacks. Optional:
## `minions` (BOSS_MINIONS that fight beside it), `phase2_form` (BOSS_FORMS
## sheet it turns into at phase 2). Bosses on the Boss Tower floors
## (boss_tower_*) are fought floor by floor: a floor's stairs open once
## every boss on it is beaten (MAPS exit "needs").
const BOSSES := {
	"popple": {"name": "Popple", "frames": 5, "idle": 5, "hp": 64, "pow": 6, "def": 1, "xp": 40, "coins": 40, "level": 3,
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
	"tolstar": {"name": "Tolstar", "frames": 10, "idle": 10, "hp": 96, "pow": 8, "def": 2, "xp": 70, "coins": 60, "level": 7,
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
	"dragohoho": {"name": "Dragohoho", "frames": 9, "idle": 9, "hp": 128, "pow": 10, "def": 3, "xp": 110, "coins": 80, "level": 11,
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
	"wart": {"name": "Wart", "frames": 7, "idle": 7, "hp": 170, "pow": 12, "def": 4, "xp": 160, "coins": 120, "level": 15,
		"map": "bowser_castle", "pos": Vector2(168, 124), "face": "down", "battle_bg": "wart_throne",
		"reward": ["one_up", 1], "rematch_reward": ["super_mushroom", 1], "recruit": 0.03,
		"attacks": ["bubble_spray", "royal_stomp"], "phase2": "bubble_storm",
		"intro": ["GWAH HA HA! King Wart has taken over this castle!",
			"Bowser? He's out. This throne is MINE now, and so is the Beanbean Kingdom!"],
		"rematch": ["GWAH! You want another taste of my royal bubbles?"],
		"battle_line": "Wart: Bow before the king of Subcon!",
		"phase_line": "Wart is livid! Bubbles everywhere!",
		"won_line": "Wart: I... hate... vegetables... GWAAAH!",
		"partner": {"hp": 38, "pow": 9, "def": 4, "move": "bubble_blast"}},
	"piranha_bean": {"name": "Piranha Bean", "frames": 14, "idle": 8, "attack": 14, "hp": 52, "pow": 5, "def": 0, "xp": 22, "coins": 32, "level": 2,
		"map": "outskirts_east", "pos": Vector2(480, 230), "face": "left", "battle_bg": "bean_fields",
		"reward": [["super_mushroom", 2], ["syrup", 1]], "rematch_reward": [["mushroom", 2]], "recruit": 0.03,
		"attacks": ["seed_spit", "bean_lunge"], "phase2": "petal_burrow",
		"intro": ["Chomp chomp! A Piranha Bean sprouted right in the middle of the Meadow!", "It snaps at anything that walks by. Fight it?"],
		"rematch": ["The Piranha Bean grew back! It looks hungry. Fight it again?"],
		"battle_line": "Piranha Bean: CHOMP!",
		"phase_line": "The Piranha Bean digs its roots in!",
		"won_line": "The Piranha Bean wilts...",
		"partner": {"hp": 18, "pow": 4, "def": 1, "move": "bean_chomp"}},
	"hermie": {"name": "Hermie III", "frames": 10, "idle": 9, "attack": 10, "hp": 74, "pow": 7, "def": 1, "xp": 44, "coins": 48, "level": 4,
		"map": "outskirts_pier", "pos": Vector2(126, 545), "face": "right", "battle_bg": "gwarhar_lagoon",
		"reward": [["super_mushroom", 2], ["syrup", 1]], "rematch_reward": [["mushroom", 2]], "recruit": 0.03,
		"attacks": ["claw_pinch", "shell_bash"], "phase2": "hermit_bubbles",
		"intro": ["Hermie III, guardian of the shore! My shell is the finest on this beach!", "Nobody touches my pier without a pinch. Ready?"],
		"rematch": ["Back for another pinch? Hermie III never retreats!"],
		"battle_line": "Hermie III: Snip snip!",
		"phase_line": "Hermie III hides in his shell and blows bubbles!",
		"won_line": "Hermie III: My shell... is still the best...",
		"partner": {"hp": 20, "pow": 5, "def": 1, "move": "crab_pinch"}},
	"mom_piranha": {"name": "Mom Piranha", "frames": 9, "idle": 9, "attack": 8, "hp": 96, "pow": 8, "def": 1, "xp": 66, "coins": 64, "level": 6,
		"map": "outskirts_woods", "pos": Vector2(650, 350), "face": "left", "battle_bg": "chucklehuck_woods",
		"reward": [["super_mushroom", 2], ["super_syrup", 1]], "rematch_reward": [["super_mushroom", 1]], "recruit": 0.03,
		"attacks": ["vine_whip", "piranha_fire"], "phase2": "seed_storm",
		"intro": ["GRRRAAH! Mom Piranha rules these woods!", "You trampled my babies' garden. Now you get eaten!"],
		"rematch": ["GRRAAH! Back to bother my garden again?"],
		"battle_line": "Mom Piranha: Into my mouth you go!",
		"phase_line": "Mom Piranha is furious! Seeds rain from the trees!",
		"won_line": "Mom Piranha droops into the grass...",
		"partner": {"hp": 23, "pow": 6, "def": 2, "move": "piranha_flame"}},
	"yo_bro": {"name": "Yo Bro", "frames": 13, "idle": 13, "attack": 9, "hp": 118, "pow": 10, "def": 2, "xp": 88, "coins": 80, "level": 8,
		"map": "stardust_fields", "pos": Vector2(300, 240), "face": "left", "battle_bg": "stardust_fields",
		"reward": [["super_mushroom", 2], ["super_syrup", 1]], "rematch_reward": [["super_mushroom", 1]], "recruit": 0.03,
		"attacks": ["chain_ball", "bro_rush"], "phase2": "chain_storm",
		"intro": ["Yo yo YO! Yo Bro in the house! These star paths are my turf!", "You wanna pass? You gotta beat the Bro! Ready?"],
		"rematch": ["Yo! Rematch time, bro?"],
		"battle_line": "Yo Bro: Yo! Check this chain!",
		"phase_line": "Yo Bro swings his chain balls wildly!",
		"won_line": "Yo Bro: Yo... no...",
		"partner": {"hp": 25, "pow": 6, "def": 2, "move": "chain_chomp_toss"}},
	"chuckolator": {"name": "Chuckolator", "frames": 6, "idle": 6, "attack": 6, "hp": 129, "pow": 10, "def": 2, "xp": 99, "coins": 88, "level": 9,
		"map": "outskirts_woods", "pos": Vector2(470, 235), "face": "left", "battle_bg": "chucklehuck_woods",
		"reward": [["super_mushroom", 2], ["super_syrup", 1]], "rematch_reward": [["super_mushroom", 1]], "recruit": 0.03,
		"attacks": ["blade_swipe", "juice_blob"], "phase2": "chuckola_rain",
		"intro": ["I am Chuckolator, made of the finest Chuckola Reserve!", "You came to drink me? I'll slice you to pieces first!"],
		"rematch": ["Chuckolator returns! Still thirsty?"],
		"battle_line": "Chuckolator: Taste my blade!",
		"phase_line": "Chuckolator boils over! Chuckola rains down!",
		"won_line": "Chuckolator: Gurgle... I'm... just soda...",
		"partner": {"hp": 26, "pow": 7, "def": 2, "move": "chuckola_slash"}},
	"hoohooros": {"name": "Hoohooros", "frames": 13, "idle": 10, "attack": 13, "hp": 140, "pow": 11, "def": 2, "xp": 110, "coins": 96, "level": 10,
		"map": "hoohoo_village", "pos": Vector2(72, 168), "face": "right", "battle_bg": "hoohoo_mountain",
		"reward": [["super_mushroom", 2], ["super_syrup", 1]], "rematch_reward": [["super_mushroom", 1]], "recruit": 0.03,
		"attacks": ["hoo_burrow", "hoo_beam"], "phase2": "pillar_fall",
		"intro": ["HOOHOO... I am Hoohooros, guardian of the Hoo Stones!", "Only those with strong feet may pass. Show me!"],
		"rematch": ["HOOHOO... You return to be tested again?"],
		"battle_line": "Hoohooros: HOOOO!",
		"phase_line": "Hoohooros roars! Hoo pillars fall from the sky!",
		"won_line": "Hoohooros: Hoo... you pass the test...",
		"partner": {"hp": 28, "pow": 7, "def": 2, "move": "hoo_pillar"}},
	"trunkle": {"name": "Trunkle", "frames": 8, "idle": 7, "attack": 8, "hp": 151, "pow": 12, "def": 2, "xp": 121, "coins": 104, "level": 11,
		"map": "outskirts_east", "pos": Vector2(1040, 400), "face": "left", "battle_bg": "outskirts",
		"reward": [["super_mushroom", 2], ["super_syrup", 1]], "rematch_reward": [["super_mushroom", 1]], "recruit": 0.03,
		"attacks": ["trunk_punch", "rock_toss"], "phase2": "rolling_rocks",
		"intro": ["TRUNKLE STRONG! TRUNKLE BIGGEST TREE ON BEACH!", "You want fight Trunkle? Trunkle squish!"],
		"rematch": ["Trunkle back! Trunkle want fight again!"],
		"battle_line": "Trunkle: SQUISH!",
		"phase_line": "Trunkle stomps! Rocks roll down the beach!",
		"won_line": "Trunkle: Trunkle... tired...",
		"partner": {"hp": 29, "pow": 7, "def": 2, "move": "trunk_slam"}},
	"birdo": {"name": "Birdo", "frames": 9, "idle": 9, "attack": 8, "hp": 162, "pow": 12, "def": 3, "xp": 132, "coins": 112, "level": 12,
		"map": "castle_hall", "pos": Vector2(60, 160), "face": "right", "battle_bg": "castle_town",
		"reward": [["ultra_mushroom", 1], ["super_syrup", 1], ["red_pepper", 1]], "rematch_reward": [["super_mushroom", 1], ["syrup", 1]], "recruit": 0.03,
		"attacks": ["egg_shot", "birdo_dash"], "phase2": "egg_roll",
		"intro": ["Oh, hello! I'm the princess. Totally. Don't look at the bow.", "...Fine! It's Birdo! And you're about to get egged!"],
		"rematch": ["Birdo is back, darling! Ready for more eggs?"],
		"battle_line": "Birdo: Eat my eggs!",
		"phase_line": "Birdo is livid! Eggs roll everywhere!",
		"won_line": "Birdo: My bow... is ruined...",
		"partner": {"hp": 30, "pow": 8, "def": 3, "move": "egg_toss"}},
	"bowletta": {"name": "Bowletta", "frames": 10, "idle": 7, "attack": 10, "hp": 371, "pow": 22, "def": 6, "xp": 286, "coins": 224, "level": 26,
		"map": "bowser_castle", "pos": Vector2(60, 280), "face": "right", "battle_bg": "bowser_castle_lava",
		"reward": [["ultra_mushroom", 2], ["one_up", 1], ["green_pepper", 1]], "rematch_reward": [["ultra_mushroom", 1]], "recruit": 0.03,
		"attacks": ["flaret_spit", "bowletta_chomp"], "phase2": "bowletta_fire",
		"intro": ["Kehhh heh heh! Bowser's body is mine now! I am BOWLETTA!", "This castle, this kingdom, ALL of it is mine! Feel the flames of Bowletta!"],
		"rematch": ["Kehh heh! Back for another roasting?"],
		"battle_line": "Bowletta: Kehhh heh heh!",
		"phase_line": "Bowletta breathes a storm of fire!",
		"won_line": "Bowletta: Nooo! This body... won't... listen...",
		"partner": {"hp": 47, "pow": 12, "def": 5, "move": "bowletta_breath"}},
	"psycho_kamek": {"name": "Psycho Kamek", "frames": 5, "idle": 5, "attack": 4, "hp": 85, "pow": 8, "def": 1, "xp": 55, "coins": 56, "level": 5,
		"map": "boss_tower_1", "pos": Vector2(75, 145), "face": "right", "battle_bg": "little_fungitown",
		"reward": [["super_mushroom", 2], ["syrup", 1]], "rematch_reward": [["mushroom", 2]], "recruit": 0.03,
		"attacks": ["hypno_wave", "kamek_summon"], "phase2": "star_shower",
		"intro": ["Welcome to the Boss Tower, traveler. I am Psycho Kamek.", "Let me read your mind... I see... a beating! Yours!"],
		"rematch": ["Hmm... I predicted you'd come back. Shall we?"],
		"battle_line": "Psycho Kamek: Look into my eyes...",
		"phase_line": "Psycho Kamek's eyes glow! Stars fall!",
		"won_line": "Psycho Kamek: I... did not foresee this...",
		"partner": {"hp": 22, "pow": 5, "def": 1, "move": "hypno_spark"}},
	"magikoopa": {"name": "Magikoopa", "frames": 16, "idle": 6, "attack": 16, "hp": 107, "pow": 9, "def": 1, "xp": 77, "coins": 72, "level": 7,
		"map": "boss_tower_1", "pos": Vector2(360, 145), "face": "left", "battle_bg": "koopa_cruiser",
		"reward": [["super_mushroom", 2], ["super_syrup", 1]], "rematch_reward": [["super_mushroom", 1]], "recruit": 0.03,
		"attacks": ["magic_blast", "koopa_summon"], "phase2": "magic_swoop",
		"intro": ["Kehh! A Magikoopa never loses a duel of magic!", "I'll shrink you, zap you, and call in the troops!"],
		"rematch": ["Kehh! More magic coming your way!"],
		"battle_line": "Magikoopa: Abra-ka-zap!",
		"phase_line": "Magikoopa takes to the air on his broom!",
		"won_line": "Magikoopa: My... magic...",
		"partner": {"hp": 24, "pow": 6, "def": 2, "move": "magic_bolt"}},
	"jojora": {"name": "Jojora", "frames": 12, "idle": 8, "attack": 12, "hp": 162, "pow": 12, "def": 3, "xp": 132, "coins": 112, "level": 12,
		"map": "boss_tower_1", "pos": Vector2(75, 245), "face": "right", "battle_bg": "jokes_end",
		"reward": [["ultra_mushroom", 1], ["super_syrup", 1], ["red_pepper", 1]], "rematch_reward": [["super_mushroom", 1], ["syrup", 1]], "recruit": 0.03,
		"attacks": ["ice_wand", "jojora_swoop"], "phase2": "ice_shard", "minions": ["jojora_friend"],
		"intro": ["Hohoho! I am Jojora, finest of the Jokes End witches!", "And this is my dear friend! We'll freeze you solid together!"],
		"rematch": ["Hohoho! My friend and I missed you!"],
		"battle_line": "Jojora: Hohoho! Freeze!",
		"phase_line": "Jojora is angry! Ice shards fall!",
		"won_line": "Jojora: How... how could you?!",
		"partner": {"hp": 30, "pow": 8, "def": 3, "move": "frost_wand"}},
	"queen_bean_boss": {"name": "Queen Bean", "frames": 12, "idle": 12, "attack": 11, "hp": 184, "pow": 14, "def": 3, "xp": 154, "coins": 128, "level": 14,
		"map": "boss_tower_1", "pos": Vector2(360, 245), "face": "left", "battle_bg": "castle_town",
		"reward": [["ultra_mushroom", 1], ["super_syrup", 1], ["red_pepper", 1]], "rematch_reward": [["super_mushroom", 1], ["syrup", 1]], "recruit": 0.03,
		"attacks": ["queen_punch", "royal_slam"], "phase2": "fist_barrage",
		"intro": ["(This is Queen Bean's training arena. She has been waiting for a worthy foe.)", "Queen Bean: HOO HOO! Show me the strength of a true hero! Fight me!"],
		"rematch": ["Queen Bean: Back for more royal training? HOO!"],
		"battle_line": "Queen Bean: Feel my royal fists!",
		"phase_line": "Queen Bean's muscles bulge! Punches fly!",
		"won_line": "Queen Bean: Marvelous! What a fight!",
		"partner": {"hp": 32, "pow": 8, "def": 3, "move": "royal_fist"}},
	"larry": {"name": "Larry", "frames": 10, "idle": 6, "attack": 10, "hp": 195, "pow": 14, "def": 3, "xp": 165, "coins": 136, "level": 15,
		"map": "boss_tower_2", "pos": Vector2(75, 145), "face": "right", "battle_bg": "bowser_castle",
		"reward": [["ultra_mushroom", 1], ["super_syrup", 1], ["red_pepper", 1]], "rematch_reward": [["super_mushroom", 1], ["syrup", 1]], "recruit": 0.03,
		"attacks": ["koopaling_fire", "wand_rush"], "phase2": "koopa_flames",
		"intro": ["Hey! Larry Koopa here! First Koopaling to beat you!", "Bowser's castle is OUR castle. Get out!"],
		"rematch": ["Larry wants a rematch! Let's go!"],
		"battle_line": "Larry: Take that!",
		"phase_line": "Larry waves his wand! Flames rain down!",
		"won_line": "Larry: No fair! You cheated!",
		"partner": {"hp": 34, "pow": 9, "def": 3, "move": "larry_flame"}},
	"lemmy": {"name": "Lemmy", "frames": 8, "idle": 8, "attack": 8, "hp": 211, "pow": 15, "def": 4, "xp": 176, "coins": 144, "level": 16,
		"map": "boss_tower_2", "pos": Vector2(360, 145), "face": "left", "battle_bg": "bowser_castle",
		"reward": [["ultra_mushroom", 1], ["super_syrup", 1], ["red_pepper", 1]], "rematch_reward": [["super_mushroom", 1], ["syrup", 1]], "recruit": 0.03,
		"attacks": ["ball_bounce", "koopaling_fire"], "phase2": "circus_barrage",
		"intro": ["Hee hee! Lemmy's circus is in town!", "Watch me bounce on your head!"],
		"rematch": ["Hee hee! Encore! Encore!"],
		"battle_line": "Lemmy: Hee hee hee!",
		"phase_line": "Lemmy juggles circus balls at you!",
		"won_line": "Lemmy: Aww, show's over...",
		"partner": {"hp": 35, "pow": 9, "def": 3, "move": "circus_ball"}},
	"morton": {"name": "Morton", "frames": 8, "idle": 8, "attack": 8, "hp": 227, "pow": 16, "def": 4, "xp": 187, "coins": 152, "level": 17,
		"map": "boss_tower_2", "pos": Vector2(75, 245), "face": "right", "battle_bg": "bowser_castle",
		"reward": [["ultra_mushroom", 1], ["super_syrup", 1], ["red_pepper", 1]], "rematch_reward": [["super_mushroom", 1], ["syrup", 1]], "recruit": 0.03,
		"attacks": ["morton_leap", "koopaling_fire"], "phase2": "morton_quake",
		"intro": ["Morton Koopa Jr.! Biggest! Strongest! Loudest!", "I'm gonna smash you flat flat FLAT!"],
		"rematch": ["Morton's back! Morton smash again!"],
		"battle_line": "Morton: SMASH!",
		"phase_line": "Morton stomps! The whole tower shakes!",
		"won_line": "Morton: Ugh... Morton needs a nap...",
		"partner": {"hp": 36, "pow": 9, "def": 3, "move": "morton_stomp"}},
	"ludwig": {"name": "Ludwig", "frames": 8, "idle": 8, "attack": 8, "hp": 243, "pow": 17, "def": 4, "xp": 198, "coins": 160, "level": 18,
		"map": "boss_tower_2", "pos": Vector2(360, 245), "face": "left", "battle_bg": "bowser_castle",
		"reward": [["ultra_mushroom", 1], ["super_syrup", 1], ["red_pepper", 1]], "rematch_reward": [["super_mushroom", 1], ["syrup", 1]], "recruit": 0.03,
		"attacks": ["ludwig_spin", "koopaling_fire"], "phase2": "ludwig_rain",
		"intro": ["I am Ludwig von Koopa, genius composer and eldest Koopaling.", "Your defeat shall be my finest symphony!"],
		"rematch": ["Ah, an encore. How delightful."],
		"battle_line": "Ludwig: A crescendo of fire!",
		"phase_line": "Ludwig conducts a storm of flames!",
		"won_line": "Ludwig: Such... a sour note...",
		"partner": {"hp": 37, "pow": 10, "def": 4, "move": "ludwig_shell"}},
	"wendy": {"name": "Wendy", "frames": 10, "idle": 8, "attack": 10, "hp": 259, "pow": 17, "def": 4, "xp": 209, "coins": 168, "level": 19,
		"map": "boss_tower_3", "pos": Vector2(75, 145), "face": "right", "battle_bg": "bowser_castle",
		"reward": [["ultra_mushroom", 1], ["super_syrup", 1], ["red_pepper", 1]], "rematch_reward": [["super_mushroom", 1], ["syrup", 1]], "recruit": 0.03,
		"attacks": ["ring_toss", "koopaling_fire"], "phase2": "wendy_rain",
		"intro": ["Ugh, you AGAIN? I'm Wendy O. Koopa, and this floor is MINE!", "Prepare to be ringed!"],
		"rematch": ["Hmph! Fine, one more time!"],
		"battle_line": "Wendy: Catch!",
		"phase_line": "Wendy throws a tantrum! Rings rain down!",
		"won_line": "Wendy: Hmph! I wasn't even trying!",
		"partner": {"hp": 38, "pow": 10, "def": 4, "move": "candy_ring"}},
	"iggy": {"name": "Iggy", "frames": 10, "idle": 10, "attack": 8, "hp": 275, "pow": 18, "def": 5, "xp": 220, "coins": 176, "level": 20,
		"map": "boss_tower_3", "pos": Vector2(360, 145), "face": "left", "battle_bg": "bowser_castle",
		"reward": [["ultra_mushroom", 2], ["one_up", 1], ["green_pepper", 1]], "rematch_reward": [["ultra_mushroom", 1]], "recruit": 0.03,
		"attacks": ["iggy_spin", "koopaling_fire"], "phase2": "iggy_rain",
		"intro": ["HYAHAHA! Iggy's here! Iggy's crazy! Iggy spins!", "Can you keep up?! HYAHAHA!"],
		"rematch": ["HYAHAHA! Spin again!"],
		"battle_line": "Iggy: HYAHAHA!",
		"phase_line": "Iggy goes wild! Rainbow flames!",
		"won_line": "Iggy: So... dizzy...",
		"partner": {"hp": 40, "pow": 10, "def": 4, "move": "iggy_whirl"}},
	"roy": {"name": "Roy", "frames": 9, "idle": 8, "attack": 9, "hp": 291, "pow": 19, "def": 5, "xp": 231, "coins": 184, "level": 21,
		"map": "boss_tower_3", "pos": Vector2(75, 245), "face": "right", "battle_bg": "bowser_castle",
		"reward": [["ultra_mushroom", 2], ["one_up", 1], ["green_pepper", 1]], "rematch_reward": [["ultra_mushroom", 1]], "recruit": 0.03,
		"attacks": ["shell_dash", "koopaling_fire"], "phase2": "roy_slam",
		"intro": ["Roy's the toughest Koopaling, punk. No way you're getting past me.", "Let's go!"],
		"rematch": ["Back for more, punk?"],
		"battle_line": "Roy: Out of my way!",
		"phase_line": "Roy is mad! He jumps to pound you flat!",
		"won_line": "Roy: Not... cool...",
		"partner": {"hp": 41, "pow": 11, "def": 4, "move": "roy_bash"}},
	"cackletta": {"name": "Cackletta", "frames": 12, "idle": 12, "attack": 8, "hp": 307, "pow": 19, "def": 5, "xp": 242, "coins": 192, "level": 22,
		"map": "boss_tower_3", "pos": Vector2(360, 245), "face": "left", "battle_bg": "woohoo_hooniversity",
		"reward": [["ultra_mushroom", 2], ["one_up", 1], ["green_pepper", 1]], "rematch_reward": [["ultra_mushroom", 1]], "recruit": 0.03,
		"attacks": ["bat_swarm", "shadow_sink"], "phase2": "cackle_bolt",
		"intro": ["Ehh heh heh! So YOU climbed my tower? How charming.", "I am Cackletta! I'll take your voice and your life!"],
		"rematch": ["Ehh heh heh! Back to be cackled at?"],
		"battle_line": "Cackletta: Ehh heh heh heh!",
		"phase_line": "Cackletta spreads her wings! Lightning strikes!",
		"won_line": "Cackletta: Impossible! I... am... Cackletta!",
		"partner": {"hp": 42, "pow": 11, "def": 4, "move": "bat_bolt"}},
	"fawful": {"name": "Fawful", "frames": 7, "idle": 6, "attack": 7, "hp": 339, "pow": 21, "def": 6, "xp": 264, "coins": 208, "level": 24,
		"map": "boss_tower_top", "pos": Vector2(50, 330), "face": "right", "battle_bg": "bowser_castle",
		"reward": [["ultra_mushroom", 2], ["one_up", 1], ["green_pepper", 1]], "rematch_reward": [["ultra_mushroom", 1]], "recruit": 0.03,
		"attacks": ["headgear_chomp", "fawful_beam"], "phase2": "fawful_bombs", "phase2_form": "fawful_2",
		"intro": ["I HAVE FURY! I am Fawful, and this tower is my mustard of doom!", "You are fools who will be eaten like bread!"],
		"rematch": ["Fawful is back with the fury! Fink-rat!"],
		"battle_line": "Fawful: I HAVE FURY!",
		"phase_line": "Fawful's headgear breaks! He fights on with fury bombs!",
		"won_line": "Fawful: This is... not... the end! I HAVE... fury...",
		"partner": {"hp": 44, "pow": 12, "def": 5, "move": "fury_beam"}},
	"cackletta_soul": {"name": "Cackletta's Soul", "frames": 8, "idle": 8, "attack": 8, "hp": 435, "pow": 25, "def": 7, "xp": 330, "coins": 256, "level": 30,
		"map": "boss_tower_top", "pos": Vector2(107, 250), "face": "down", "battle_bg": "bowser_castle_lava",
		"reward": [["ultra_mushroom", 3], ["one_up", 2], ["super_syrup", 2]], "rematch_reward": [["ultra_mushroom", 1]], "recruit": 0.03,
		"attacks": ["soul_swipe", "soul_beam"], "phase2": "soul_storm",
		"intro": ["Ehh... heh... heh... So you reached the top of my tower.", "My body is gone, but my SOUL burns on! Now I'll take YOURS!"],
		"rematch": ["Ehh heh... Again you come to the top. Again you will fall!"],
		"battle_line": "Cackletta's Soul: Your souls are MINE!",
		"phase_line": "Cackletta's Soul howls! The tower trembles!",
		"won_line": "Cackletta's Soul: Nooooooooo...!",
		"partner": {"hp": 52, "pow": 14, "def": 6, "move": "soul_flare"}},
}
## Boss attacks (battle.gd _boss_turn). kind: "dash" (runs at you: {a} to
## jump over it), "slam" (leaps onto you: {a} to jump out of the way),
## "volley" (`count` things thrown at you: {a} just before each hits to
## hammer it back at the boss), "rain" (something falls on every ally: {a}
## to jump each), "barrage" (`count` things roll along the ground at you,
## quick and uneven: {a} to jump each), "burrow" (it digs under you and
## bursts out, sometimes after a fake rumble: {a} as it bursts), "swoop" (it
## flies up and dives, sometimes faking the first dive: {a} as it lands) or
## "summon" (calls a `minion` enemy into the battle). A dash with `count`
## runs at you that many times. power: added to the boss's POW. steal: coins
## it grabs when it hits (you get them back if you win). burn: chance a hit
## burns.
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
	"seed_spit": {"name": "Seed Spit", "kind": "volley", "count": 2, "power": 0, "color": Color(0.45, 0.8, 0.3)},
	"bean_lunge": {"name": "Bean Lunge", "kind": "dash", "power": 1},
	"petal_burrow": {"name": "Root Burrow", "kind": "burrow", "power": 2},
	"claw_pinch": {"name": "Claw Pinch", "kind": "dash", "count": 2, "power": 0},
	"shell_bash": {"name": "Shell Bash", "kind": "slam", "power": 2},
	"hermit_bubbles": {"name": "Bubble Roll", "kind": "barrage", "count": 3, "power": 1, "color": Color(0.6, 0.85, 1.0)},
	"vine_whip": {"name": "Vine Whip", "kind": "dash", "power": 1},
	"piranha_fire": {"name": "Fire Spit", "kind": "volley", "count": 3, "power": 0, "burn": 0.25, "color": Color(1.0, 0.45, 0.15)},
	"seed_storm": {"name": "Seed Storm", "kind": "rain", "power": 2, "color": Color(0.5, 0.85, 0.3)},
	"chain_ball": {"name": "Chain Ball", "kind": "volley", "count": 2, "power": 1, "color": Color(0.85, 0.2, 0.2)},
	"bro_rush": {"name": "Bro Rush", "kind": "dash", "count": 2, "power": 0},
	"chain_storm": {"name": "Chain Storm", "kind": "barrage", "count": 4, "power": 1, "color": Color(0.3, 0.75, 0.3)},
	"blade_swipe": {"name": "Blade Swipe", "kind": "dash", "power": 2},
	"juice_blob": {"name": "Juice Blob", "kind": "volley", "count": 3, "power": 0, "color": Color(0.85, 0.15, 0.4)},
	"chuckola_rain": {"name": "Chuckola Rain", "kind": "rain", "power": 2, "color": Color(0.9, 0.2, 0.45)},
	"hoo_burrow": {"name": "Hoo Burrow", "kind": "burrow", "power": 2},
	"hoo_beam": {"name": "Hoo Beam", "kind": "volley", "count": 2, "power": 1, "color": Color(0.8, 0.5, 1.0)},
	"pillar_fall": {"name": "Pillar Fall", "kind": "rain", "power": 3, "color": Color(0.95, 0.55, 0.35)},
	"trunk_punch": {"name": "Trunk Punch", "kind": "dash", "power": 2},
	"rock_toss": {"name": "Rock Toss", "kind": "volley", "count": 3, "power": 0, "color": Color(0.6, 0.45, 0.3)},
	"rolling_rocks": {"name": "Rolling Rocks", "kind": "barrage", "count": 4, "power": 1, "color": Color(0.55, 0.42, 0.3)},
	"egg_shot": {"name": "Egg Shot", "kind": "volley", "count": 3, "power": 0, "color": Color(1.0, 1.0, 0.95)},
	"birdo_dash": {"name": "Birdo Dash", "kind": "dash", "power": 2},
	"egg_roll": {"name": "Egg Roll", "kind": "barrage", "count": 4, "power": 1, "color": Color(1.0, 0.75, 0.85)},
	"hypno_wave": {"name": "Hypno Wave", "kind": "volley", "count": 2, "power": 0, "color": Color(1.0, 0.5, 0.85)},
	"kamek_summon": {"name": "Goomba Call", "kind": "summon", "minion": "goomba"},
	"star_shower": {"name": "Star Shower", "kind": "rain", "power": 1, "color": Color(1.0, 0.9, 0.3)},
	"magic_blast": {"name": "Magic Blast", "kind": "volley", "count": 3, "power": 0, "color": Color(0.45, 0.6, 1.0)},
	"koopa_summon": {"name": "Koopa Call", "kind": "summon", "minion": "koopa"},
	"magic_swoop": {"name": "Broom Swoop", "kind": "swoop", "power": 2},
	"ice_wand": {"name": "Ice Wand", "kind": "volley", "count": 2, "power": 1, "color": Color(0.6, 0.95, 1.0)},
	"jojora_swoop": {"name": "Jojora Swoop", "kind": "swoop", "power": 1},
	"ice_shard": {"name": "Ice Shards", "kind": "rain", "power": 2, "color": Color(0.7, 0.95, 1.0)},
	"queen_punch": {"name": "Queen Punch", "kind": "dash", "count": 2, "power": 1},
	"royal_slam": {"name": "Royal Slam", "kind": "slam", "power": 3},
	"fist_barrage": {"name": "Fist Barrage", "kind": "barrage", "count": 4, "power": 1, "color": Color(0.5, 0.95, 0.35)},
	"koopaling_fire": {"name": "Fire Spit", "kind": "volley", "count": 3, "power": 0, "burn": 0.2, "color": Color(1.0, 0.5, 0.15)},
	"wand_rush": {"name": "Wand Rush", "kind": "dash", "power": 2},
	"koopa_flames": {"name": "Wand Flames", "kind": "rain", "power": 2, "color": Color(1.0, 0.4, 0.1)},
	"ball_bounce": {"name": "Ball Bounce", "kind": "slam", "power": 2},
	"circus_barrage": {"name": "Circus Balls", "kind": "barrage", "count": 4, "power": 1, "color": Color(0.95, 0.85, 0.3)},
	"morton_leap": {"name": "Morton Leap", "kind": "slam", "power": 3},
	"morton_quake": {"name": "Morton Quake", "kind": "rain", "power": 3, "color": Color(0.6, 0.45, 0.35)},
	"ludwig_spin": {"name": "Shell Spin", "kind": "dash", "count": 2, "power": 1},
	"ludwig_rain": {"name": "Ludwig's Overture", "kind": "rain", "power": 3, "color": Color(0.6, 0.4, 1.0)},
	"ring_toss": {"name": "Ring Toss", "kind": "barrage", "count": 3, "power": 1, "color": Color(1.0, 0.85, 0.2)},
	"wendy_rain": {"name": "Ring Rain", "kind": "rain", "power": 3, "color": Color(1.0, 0.8, 0.3)},
	"iggy_spin": {"name": "Iggy Spin", "kind": "dash", "count": 3, "power": 0},
	"iggy_rain": {"name": "Rainbow Flames", "kind": "rain", "power": 3, "color": Color(1.0, 0.5, 0.8)},
	"shell_dash": {"name": "Shell Dash", "kind": "dash", "count": 2, "power": 2},
	"roy_slam": {"name": "Roy Pound", "kind": "slam", "power": 5},
	"bat_swarm": {"name": "Bat Swarm", "kind": "barrage", "count": 4, "power": 1, "color": Color(0.3, 0.15, 0.3)},
	"shadow_sink": {"name": "Shadow Sink", "kind": "burrow", "power": 3},
	"cackle_bolt": {"name": "Cackle Bolt", "kind": "rain", "power": 4, "color": Color(1.0, 0.35, 0.75)},
	"headgear_chomp": {"name": "Headgear Chomp", "kind": "dash", "power": 3},
	"fawful_beam": {"name": "Fawful Beam", "kind": "volley", "count": 3, "power": 1, "color": Color(0.4, 1.0, 0.4)},
	"fawful_bombs": {"name": "Fury Bombs", "kind": "rain", "power": 4, "color": Color(1.0, 0.7, 0.2)},
	"flaret_spit": {"name": "Flaret Spit", "kind": "volley", "count": 3, "power": 1, "burn": 0.3, "color": Color(1.0, 0.6, 0.1)},
	"bowletta_chomp": {"name": "Chomp Charge", "kind": "dash", "count": 2, "power": 3},
	"bowletta_fire": {"name": "Fire Breath", "kind": "barrage", "count": 5, "power": 2, "burn": 0.2, "color": Color(1.0, 0.45, 0.1)},
	"soul_swipe": {"name": "Soul Swipe", "kind": "slam", "power": 5},
	"soul_beam": {"name": "Soul Beam", "kind": "volley", "count": 4, "power": 2, "color": Color(0.85, 0.3, 1.0)},
	"soul_storm": {"name": "Soul Storm", "kind": "rain", "power": 5, "color": Color(0.75, 0.25, 0.95)},
}
## Helpers that fight beside a boss (BOSSES "minions" join its battle; a
## "summon" attack can call one in too). They attack like ordinary enemies
## and can't be asked to join.
const BOSS_MINIONS := {
	"jojora_friend": {"name": "Jojora's Friend", "frames": 10, "idle": 8, "attack": 10, "hp": 60, "pow": 10, "def": 2, "xp": 40, "coins": 20, "recruit": 0.0},
}
## Sheets a boss turns into at phase 2 (BOSSES "phase2_form").
const BOSS_FORMS := {
	"fawful_2": {"frames": 8, "idle": 8, "attack": 8},
}
## The chance a boss you just beat says yes when an evil player asks it to join.
const BOSS_JOIN_CHANCE := 0.35

## The Boss Tower floors' bosses (see BOSSES); a floor's stairs need them all beaten.
const _TOWER_1 := ["psycho_kamek", "magikoopa", "jojora", "queen_bean_boss"]
const _TOWER_2 := ["larry", "lemmy", "morton", "ludwig"]
const _TOWER_3 := ["wendy", "iggy", "roy", "cackletta"]

## Maps: art and walk mask in res://assets/maps/ (built by tools/make_maps.py).
## battle_bg: res://assets/battle/backgrounds/<id>.png, behind battles started here.
## exits: walking into `rect` moves you to `to` at that map's `spawn` point.
## A `door` exit (a building's door) only opens while you push up into it.
## An exit with `needs` (boss ids) stays sealed until you have beaten them all.
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
		"spawns": {"start": Vector2(205, 250), "bridge": Vector2(205, 580), "tower": Vector2(205, 116)},
		"exits": [
			{"rect": Rect2(170, 605, 70, 10), "to": "outskirts", "spawn": "east_bridge"},
			{"rect": Rect2(186, 96, 40, 8), "to": "boss_tower_1", "spawn": "south", "door": true},
		],
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
	# The Boss Tower, through the castle door in Bowser's Castle (tools/make_tower.py
	# builds its floors). Its bosses (Game.BOSSES) stand round the walls; the
	# stairs up open once a floor's bosses are all beaten ("needs").
	"boss_tower_1": {
		"name": "Boss Tower 1F", "battle_bg": "bowser_castle", "safe": true,
		"spawns": {"south": Vector2(224, 286), "top": Vector2(224, 125)},
		"exits": [
			{"rect": Rect2(192, 300, 65, 13), "to": "bowser_castle", "spawn": "tower"},
			{"rect": Rect2(198, 92, 52, 16), "to": "boss_tower_2", "spawn": "south", "door": true, "needs": _TOWER_1},
		],
		"enemies": [],
		"npcs": [{"id": "toad_blue", "pos": Vector2(300, 275), "talk": "tower_rest", "face": "left"}],
	},
	"boss_tower_2": {
		"name": "Boss Tower 2F", "battle_bg": "bowser_castle", "safe": true,
		"spawns": {"south": Vector2(224, 286), "top": Vector2(224, 125)},
		"exits": [
			{"rect": Rect2(192, 300, 65, 13), "to": "boss_tower_1", "spawn": "top"},
			{"rect": Rect2(198, 92, 52, 16), "to": "boss_tower_3", "spawn": "south", "door": true, "needs": _TOWER_2},
		],
		"enemies": [],
		"npcs": [],
	},
	"boss_tower_3": {
		"name": "Boss Tower 3F", "battle_bg": "bowser_castle", "safe": true,
		"spawns": {"south": Vector2(224, 286), "top": Vector2(224, 125)},
		"exits": [
			{"rect": Rect2(192, 300, 65, 13), "to": "boss_tower_2", "spawn": "top"},
			{"rect": Rect2(198, 92, 52, 16), "to": "boss_tower_top", "spawn": "south", "door": true, "needs": _TOWER_3},
		],
		"enemies": [],
		"npcs": [{"id": "toad_blue", "pos": Vector2(300, 275), "talk": "tower_rest", "face": "left"}],
	},
	"boss_tower_top": {
		"name": "Boss Tower Summit", "battle_bg": "bowser_castle_lava", "safe": true,
		"spawns": {"south": Vector2(107, 435)},
		"exits": [{"rect": Rect2(82, 455, 50, 13), "to": "boss_tower_3", "spawn": "top"}],
		"enemies": [],
		"npcs": [],
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

## An item's or a piece of gear's table entry (ITEMS, then GEAR).
func goods(id: String) -> Dictionary:
	return ITEMS.get(id, GEAR.get(id, {}))


## How many of an item (or piece of gear, not counting what you wear) you carry.
func item_count(id: String) -> int:
	if GEAR.has(id):
		return int(player.get("gear", {}).get(id, 0))
	return int(player.get("items", {}).get(id, 0))


## Most of one item or piece of gear you can carry.
func max_count(id: String) -> int:
	return MAX_GEAR if GEAR.has(id) else MAX_ITEM


## Adds (or with a negative amount, takes away) items or gear; returns how
## many were actually added (you can carry up to max_count of each).
func add_item(id: String, amount := 1) -> int:
	if GEAR.has(id):
		if typeof(player.get("gear")) != TYPE_DICTIONARY:
			player["gear"] = {}
		var had := item_count(id)
		var now := clampi(had + amount, 0, MAX_GEAR)
		if now == 0:
			player["gear"].erase(id)
		else:
			player["gear"][id] = now
		return now - had
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


## What you can sell: items, then gear you carry but don't wear.
func sellable() -> Array:
	return owned_items() + GEAR_ORDER.filter(func(id): return item_count(id) > 0)


# --- Equipment ----------------------------------------------------------------

## The gear id worn in `slot` ("pants" or "badge"), or "".
func equipped(slot: String) -> String:
	var e = player.get("equip", {})
	return str(e.get(slot, "")) if typeof(e) == TYPE_DICTIONARY else ""


## Gear you carry or wear, in menu order.
func owned_gear() -> Array:
	return GEAR_ORDER.filter(func(id): return item_count(id) > 0 or equipped(GEAR[id]["slot"]) == id)


## Puts on a piece of gear you carry (taking off whatever was in its slot).
func equip(id: String) -> void:
	if not GEAR.has(id) or item_count(id) <= 0:
		return
	var slot: String = GEAR[id]["slot"]
	unequip(slot)
	add_item(id, -1)
	if typeof(player.get("equip")) != TYPE_DICTIONARY:
		player["equip"] = {}
	player["equip"][slot] = id
	_gear_stats(id, 1)


## Takes off what you wear in `slot` and puts it back in your bag.
func unequip(slot: String) -> void:
	var id := equipped(slot)
	if id == "":
		return
	player["equip"].erase(slot)
	if GEAR.has(id):
		_gear_stats(id, -1)
		player["gear"] = player.get("gear", {})
		player["gear"][id] = int(player["gear"].get(id, 0)) + 1  # may go past MAX_GEAR; that's fine


## Adds (dir 1) or removes (dir -1) a piece of gear's stats. HP and SP
## bonuses come with that much HP and SP when you put it on.
func _gear_stats(id: String, dir: int) -> void:
	var g: Dictionary = GEAR[id]
	player["pow"] += dir * int(g.get("pow", 0))
	player["def"] += dir * int(g.get("def", 0))
	for pair in [["hp", "max_hp"], ["sp", "max_sp"]]:
		var d := dir * int(g.get(pair[0], 0))
		player[pair[1]] += d
		player[pair[0]] = clampi(player[pair[0]] + maxi(d, 0), 1 if pair[0] == "hp" else 0, player[pair[1]])


## What your gear adds up to, e.g. "POW+2 DEF+3" ("" for nothing).
func gear_bonus_text() -> String:
	var total := {}
	for slot in GEAR_SLOTS:
		var id := equipped(slot)
		for k in ["hp", "sp", "pow", "def"]:
			if GEAR.has(id):
				total[k] = int(total.get(k, 0)) + int(GEAR[id].get(k, 0))
	var parts := []
	for k in ["hp", "sp", "pow", "def"]:
		if int(total.get(k, 0)) != 0:
			parts.append("%s+%d" % [k.to_upper(), total[k]])
	return " ".join(parts)


## "a Mushroom", "an Ultra Mushroom".
func with_article(item_name: String) -> String:
	return ("an " if item_name.left(1).to_lower() in ["a", "e", "i", "o", "u"] else "a ") + item_name


## What a shop pays for one of an item.
func sell_price(id: String) -> int:
	return maxi(1, int(goods(id)["price"]) / 2)


## Rolls the item drops for beaten enemies (types); adds them to the
## inventory and returns their ids (one per drop).
func roll_drops(types: Array) -> Array:
	var got := []
	for t in types:
		var d: Array = DROPS.get(t, [])
		if not d.is_empty() and randf() < float(d[1]) and add_item(d[0]) > 0:
			got.append(d[0])
	return got


## Keeps only known gear in the save; old saves have none.
func _clean_gear(data: Dictionary) -> void:
	var gear := {}
	var saved = data.get("gear", {})
	if typeof(saved) == TYPE_DICTIONARY:
		for id in saved:
			if GEAR.has(id) and int(saved[id]) > 0:
				gear[id] = int(saved[id])
	data["gear"] = gear
	var equip := {}
	var worn = data.get("equip", {})
	if typeof(worn) == TYPE_DICTIONARY:
		for slot in GEAR_SLOTS:
			if GEAR.has(str(worn.get(slot, ""))):
				equip[slot] = str(worn[slot])
	data["equip"] = equip


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


## True if someone new could join: in your party, or waiting at home.
func can_recruit() -> bool:
	return player["party"].size() < MAX_PARTY or bench().size() < MAX_BENCH


## Partners and recruits waiting at your home base (Castle Town for good,
## Bowser's Castle for evil). Each side only sees its own kind there.
func bench() -> Array:
	if typeof(player.get("bench")) != TYPE_ARRAY:
		player["bench"] = []
	return player["bench"]


## The side a party member fights for: partners are good, enemies and bosses evil.
static func member_side(m: Dictionary) -> String:
	return "good" if m.get("kind", "") == "partner" else "evil"


## Indexes into bench() of the members your side can take along.
func bench_for_side() -> Array:
	var out := []
	for i in bench().size():
		if member_side(bench()[i]) == player["side"]:
			out.append(i)
	return out


## Adds a new member to your party, or to the bench if the party is full.
## Returns "party" or "bench".
func add_member(m: Dictionary) -> String:
	if player["party"].size() < MAX_PARTY:
		player["party"].append(m)
		return "party"
	bench().append(m)
	return "bench"


## Sends party member i home to wait on the bench.
func send_home(i: int) -> void:
	bench().append(player["party"][i])
	player["party"].remove_at(i)


## Takes bench member j along (rested: full HP). Returns "" or why not:
## "full" (party is full), "boss" (one boss per party).
func take_from_bench(j: int) -> String:
	var m: Dictionary = bench()[j]
	if player["party"].size() >= MAX_PARTY:
		return "full"
	if m.get("kind", "") == "boss" and has_boss_partner():
		return "boss"
	bench().remove_at(j)
	m["hp"] = m["max_hp"]
	player["party"].append(m)
	return ""


## The name of your home base.
func home_name() -> String:
	return MAPS[HOME_MAP[player["side"]]]["name"]


func switch_side() -> void:
	# Prototype rule: switching sides swaps to the other side's first character
	# and sends you to that side's home. Levels, coins and items are kept.
	var other := "evil" if player["side"] == "good" else "good"
	for id in CHARACTERS:
		if CHARACTERS[id]["side"] == other:
			player["character"] = id
			break
	player["side"] = other
	bench().append_array(player["party"])  # they wait at their own side's home
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

## An enemy's, a boss's or a boss minion's table entry.
func foe_info(type: String) -> Dictionary:
	return ENEMIES.get(type, BOSSES.get(type, BOSS_MINIONS.get(type, {})))


## How many rows a character sheet has: 3 (down, side, up), plus an attack
## row for bosses that have one.
func sheet_rows(info: Dictionary) -> int:
	return 4 if int(info.get("attack", 0)) > 0 else 3


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
	start_battle([id] + BOSSES[id].get("minions", []), "boss:" + id, overworld_position)
	pending_battle["boss"] = id
	pending_battle["battle_bg"] = BOSSES[id].get("battle_bg", "outskirts")


# --- Saving (browser storage on the web build, and online: see Cloud) --------

func save() -> void:
	if player.is_empty():
		return
	player["saved_at"] = Time.get_unix_time_from_system()  # which copy is newer (see Cloud)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(player))
	Cloud.mark_dirty()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_save() -> bool:
	if not has_save():
		return false
	return use_save(JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH)))


## Makes `data` (a save read from this browser or from the server) the
## player, fixing up saves from older versions. False if it can't be used.
func use_save(data: Variant) -> bool:
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
	_clean_gear(data)
	if typeof(data.get("bosses")) != TYPE_DICTIONARY:
		data.erase("bosses")  # boss wins (see boss_wins); old saves have none
	if typeof(data.get("party")) != TYPE_ARRAY:
		data["party"] = []
	if typeof(data.get("bench")) != TYPE_ARRAY:
		data["bench"] = []
	for member in data["party"] + data["bench"]:
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

