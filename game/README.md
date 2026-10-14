# Mario & Luigi MMO (Godot 4)

A Superstar Saga style RPG that runs in the browser. Play the latest build at
https://rileymusil.github.io/mario-luigi-mmorpg/ (every push to `main` redeploys).

## Open it
1. Install Godot 4.4 or newer (standard version, not .NET).
2. In the Project Manager choose **Import**, pick this folder's `project.godot`, then press **F5** to play.

## Controls
| Action | Keyboard | Gamepad | Touch screen |
|---|---|---|---|
| Move | Arrows / WASD | D-pad | Joystick (bottom left) |
| Jump, confirm, timed presses | Z, J or Space | A | Red **A** button |
| Talk, ask, back | X or K | B | Green **B** button |
| Menu | Enter or Esc | Start | **MENU** (top right) |
| Chat | T or / | | **Chat** button (bottom right) |

**Mouse and touch.** Every menu works with the mouse: point at an option to move the pointer, click it to pick it, right-click or click outside the menu to go back (where the menu has a way back). On a touch screen, tap an option to pick it (slide your finger off before lifting to change your mind) and tap outside the menu to go back. Click or tap anywhere to read on when someone is talking. Click or tap someone with a "!" over their head to talk to them, and click a partner's card in the party screen to pick them. Text boxes (username, chat) have OK and Back buttons.

**Phones and tablets.** Hold the phone sideways. The on-screen controls show on touch screens (or after your first touch) and hide when you press a key; several fingers work at once, so you can walk and jump together. Only the buttons that make sense show: none on the title screen (tap the menus), A and B in battle, all of them while walking around, and none while someone is talking. On Android, the corners button next to MENU goes full screen and keeps the game sideways; on iPhone, use Share > Add to Home Screen to play full screen. Typing (your username, or chat with the Chat button) opens the browser's own text box, so the phone's keyboard comes up.

## What you can do
- **Pick a side and a character** (eight good, six evil; the card on the right shows stats and the signature move).
  Good: Mario, Luigi, Princess Peach, Professor E. Gadd, Vivian, Waluigi, Rosalina, Toadette.
  Evil: Bowser, Rookie Bowser, Grodus, the Koopa Bros., Bowser Jr., Shadow Mario.
  Good players start in Beanbean Castle Town, evil players at Bowser's Castle.
- **Explore** maps built from the Superstar Saga map art (see *Maps* below): Castle Town with ten buildings you can walk into, Beanbean Outskirts, Stardust Fields, Hoohoo Village and Bowser's Castle. Walk up into a door to go in; walk down onto the door mat to go back out.
- **Jump up ledges.** Hedges, flat tree tops, plateaus and low walls are raised ground: walking into them stops you, so jump (Z) while walking into them to get up. Low steps take an ordinary jump; tall cliffs can't be climbed, only dropped down (walk off any ledge to drop). Your party jumps up and drops down behind you. In the Outskirts, the hedge west of the start and the flat tree tops beyond it are the way to the west islands; in Stardust Fields, the pink plateaus are a jump up from the violet ground; Castle Town's low terrace walls and the step by Hoohoo Village's mountain door can be hopped up.
- **Talk** to the townsfolk (X): they give hints, and some do more. Shops buy and sell items for coins (they buy back at half price): the Mushroom Shop (Mushrooms, Super Mushrooms, Syrup, Refreshing Herbs, 1-Up Mushrooms) and the Badge Shop (out of badges, so Peppers and Syrups) in Castle Town, the trader in the east Hoohoo hut (stronger stock: Ultra Mushrooms, Super Syrup, Peppers) and a Koopa at Bowser's Castle. Heroes pay extra at Bowser's, and villains pay extra everywhere else. The Elder, Dr. Toad, the Starbeans Cafe and the west Hoohoo hut heal your party for free.
- **Battle** enemies in the Outskirts and Stardust Fields (Goombas, Galoombas, Beanies, Koopa Troopas, Shy Guys, Buzzy Beetles and Dry Bones). Touch one to fight; jump on it first for a first strike.
  - *Jump*: press Z as you land for a second stomp (Good / Excellent).
  - *Special* (costs SP), each a timed press (Z in the gold zone unless it says otherwise):

    | Character | Special | What it does |
    |---|---|---|
    | Mario | Fire Jump | Jump (Z as you land) that burns the enemy for 3 turns (4 on Excellent). |
    | Luigi | Thunderhand | Electric punch. Excellent stuns (Good: half the time); a stunned enemy loses its next turn. |
    | Princess Peach | Peach's Heart | Heals the whole party 6 / 10 / 14 HP (Miss / Good / Excellent). |
    | Professor E. Gadd | Poltergust Pull | Sucks HP out of an enemy into E. Gadd. Excellent also steals its item: a Mushroom, then coins once it has nothing left. |
    | Vivian | Shade Veil | Vivian hides in the shadows: the next attack on her misses and she hits back with fire (Excellent also burns). If nobody attacks, the fire comes out at her next turn. |
    | Bowser | Fire Breath | Hits every enemy. |
    | Rookie Bowser | Rookie Rush | Up to 3 shell bashes, Z as each one hits. Every Excellent in a row adds 2 damage; a miss ends the rush. |
    | Grodus | Grodus Bolt | Lightning on every enemy; lowers their DEF for the battle (1 on Good, 2 on Excellent). |
    | Koopa Bros. | Bros. Tower | The other three brothers jump onto the stack, Z as each lands (a miss knocks him off); then the tower spins into the enemy. More brothers, more damage. |
    | Waluigi / Rosalina / Toadette | Wicked Whirl / Star Spin / Pickaxe Pound | Hits all and can stun all / hits and heals the party / ignores DEF. |
    | Bowser Jr. / Shadow Mario | Goop Paint / Shadow Drain | Can stun / steals HP. |

    The enemy box lists burn, stun and lowered DEF next to each enemy.
  - *Enemy turns*: press Z so whoever is attacked is in the air when it hits.
- **Recruit.** Good players talk to partners (X) and ask them to join: Toad, the Pianta, Bombette, Goombella, Bobbery, Prince Peasley, Koops and Bow in Castle Town, Yoshi Kid and Yoshi in the Outskirts. Evil players use *Ask to join* in battle on any enemy; hurt enemies say yes more often and stronger ones less. Up to 2 follow you and fight on their own turn with their own timed move:

  | Partner / recruit | Move | Kind |
  |---|---|---|
  | Toad | Mushroom Toss | Throw; Excellent also heals the party 3 HP. |
  | Pianta | Pianta Slam | Heavy tackle. |
  | Bombette | Bomb | Hits every enemy. |
  | Bow | Smack | Up to 3 slaps, a press each. |
  | Bobbery | Bob-ombast | Hits every enemy; Excellent burns them. |
  | Goombella, Goomba | Headbonk | Jump, Z as you land for a 2nd hit. |
  | Koops, Koopa Troopa | Shell Toss | Throw; Excellent hits the next enemy too. |
  | Yoshi Kid | Gulp | Tackle that ignores DEF. |
  | Prince Peasley | Rose Toss | Throw; Excellent lowers DEF by 2. |
  | Yoshi | Ground Pound | Jump; Excellent stuns. |
  | Beanie | Bean Bash | Tackle; Excellent stuns. |
  | Galoomba | Rolling Bump | Tackle. |
  | Shy Guy | Shy Spin | Up to 2 hits. |
  | Buzzy Beetle | Shell Spin | Tackle; Excellent lowers DEF by 1. |
  | Dry Bones | Bone Toss | Throw. |
  - Pick a command block over whoever's turn it is (arrows and Z, point and click, or tap it), then a target (X, B, a right click or a tap on nobody goes back). Timed-press hints name the A button when you play by touch. Each map has its own battle background.
- **Items.** Use them from *Items* in the pause menu (Enter) or the *Items* block in battle (it takes that turn; partners have one too):

  | Item | Does | Price |
  |---|---|---|
  | Mushroom / Super Mushroom / Ultra Mushroom | Heals one ally 10 / 25 / 50 HP. | 8 / 20 / 40 |
  | Syrup / Super Syrup | Refills 10 / 25 of your SP. | 10 / 25 |
  | 1-Up Mushroom | Battle: revives a fallen ally with half their HP. | 30 |
  | Refreshing Herb | Battle: cures a burn or dizziness (Dry Bones can burn you; Beanies and Shy Guys can make you dizzy, losing a turn). | 12 |
  | Red Pepper / Green Pepper | Battle: one ally's POW / DEF +3 until the battle ends. | 18 |

  Beaten enemies drop coins, and sometimes an item. In a partner's co-op battle you can use HP and SP items and Red Peppers on yourself; the rest are greyed out there.
- **Grow.** XP and levels (cap 50), coins, items. Losing sends you home with a few coins lost.
- **Switch sides** any time from the menu. **Saves** go to the browser automatically.

## Project layout
- `scenes/title.tscn` (main scene), `scenes/world.tscn` (any map), `scenes/battle.tscn`.
- `scripts/game.gd` (autoload `Game`): all data tables (characters, specials, battle moves of partners and recruits, partners, enemies, maps with exits, spawns, enemies and NPCs), the save, and scene changes. Most tuning happens here.
- `scripts/world.gd`: map loading, walking on the walk mask, doors and exits, followers, enemies, talking (choices, shops, heals), pause menu.
- `data/dialogue.json` and `scripts/dialogue_data.gd`: what NPCs say (see *Dialogue* below).
- `scripts/map_props.gd`: trees, buildings and other tall things you can walk behind (props), the walk mask loader. `scripts/map_editor.gd`: the debug-only map editor (F2).
- `scripts/battle.gd`: battle flow, timed presses, specials, recruiting, XP. `ui/command_blocks.gd` and
  `ui/target_picker.gd` are its command blocks and target pointer; `scripts/battle_transition.gd` is the
  star swipe into battles and the fade out of them.
- `scripts/character_sprite.gd`, `scripts/choice_menu.gd`: shared sprite and menu box (keys, mouse and touch).
- `ui/touch_controls.gd` (autoload `TouchControls`): the on-screen joystick (`ui/touch_stick.gd`) and buttons (`ui/touch_button.gd`). They press the same input actions as the keys, so game code just reads `Input` as usual. Anything that should hide them while it is open joins the `touch_blockers` group (the speech balloon and text box do). `ui/pointer.gd` has small helpers that treat a click and a tap alike.
- `ui/theme.tres`: the project's default theme (Superstar Saga font, speech-balloon panels and the
  `NavyPanel`, `StripPanel`, `NotebookPanel`, `RedCard`/`GreenCard`, `FlatPanel` and
  `LightLabel`, `InfoLabel`, `TitleLabel`, `OutlineLabel`, `GoldLabel` variations).
  `ui/` also holds the reusable pieces: `dialogue_box` (typed-in speech balloon), `hud`,
  `area_banner`, `pause_screen` (notebook), `party_screen` (stat cards) and `gold_number`.
- `assets/ui/`: menu art and the bitmap fonts (`mlss_font.fnt`, `mlss_font_outline.fnt`).
- `assets/battle/`: battle art. `backgrounds/<id>.png` are 240x160 battle backgrounds; a map's `battle_bg` in `MAPS` picks one (falls back to `outskirts`).
- `assets/characters/`: walk sheets, 3 rows (down, right, up). `assets/maps/`: map art, `<map>_mask.png` (the ground: white = walkable) and `<map>_props.json` (trees and buildings, see below).

## Maps
| Map id | Name | Kind | Exits |
|---|---|---|---|
| `castle_town` | Beanbean Castle Town | town | gates to the Outskirts; doors into the palace and nine buildings |
| `house_nw` | Elder's House | inside | door to Castle Town |
| `house_sw` | Beanish House | inside | door to Castle Town |
| `house_s` | Toad Lodge | inside | door to Castle Town |
| `house_se` | Dr. Toad's Clinic | inside | door to Castle Town |
| `house_ne` | Beanbean Town Hall | inside | two doors to Castle Town |
| `shop_mushroom` | Mushroom Shop | inside | door to Castle Town |
| `shop_badge` | Badge Shop | inside | door to Castle Town |
| `starbeans_cafe` | Starbeans Cafe | inside | door to Castle Town |
| `castle_hall` | Beanbean Castle | inside | palace door to Castle Town, arch to the throne room |
| `throne_room` | Throne Room | inside | back to the castle hall |
| `outskirts` | Beanbean Outskirts | wild | south path to Castle Town, east bridge to Bowser's Castle, east path to Stardust Fields |
| `stardust_fields` | Stardust Fields | wild | west paths to the Outskirts, north path and east edge to Hoohoo Village |
| `hoohoo_village` | Hoohoo Village | town | west and south to Stardust Fields, doors into two huts |
| `hoohoo_hut_w`, `hoohoo_hut_e` | Hoohoo Hut | inside | door to Hoohoo Village |
| `bowser_castle` | Bowser's Castle | evil home | rail bridge to the Outskirts |

Towns and insides are `safe` (no enemies, no duels). The online server takes any map id made of `a-z`, `0-9` and `_` (up to 32), so new maps need no server change.

### Adding an area or a building inside
1. Add the map to `MAPS` in `tools/make_maps.py` (its sheet, crop box and how to find the floor, plus hand `walk`/`block` boxes) and run `python3 tools/make_maps.py "<Mario&LuigiMMO folder>" <id>`; or drop `<id>.png` and `<id>_mask.png` into `assets/maps/` yourself. Add `<id>_props.json` for anything to walk behind. Run `godot --headless --path game --import`.
2. Add an entry to `MAPS` in `scripts/game.gd`: `name`, `safe`, `battle_bg` (wild maps), `spawns` (named points where you arrive), `exits`, `enemies` and `npcs`.
3. Join it up: each exit is `{"rect": Rect2(...), "to": map, "spawn": name}`. For a building, put a `"door": true` exit over the door in the outside map (it only opens while you push up into it) and a plain exit over the inside door mat; give each side a spawn just in front of the other's exit (not inside it), so going in and back out lands you where you started.
4. Check that every spawn, NPC and enemy stands on walkable ground and every exit can be reached, jumping where needed (open the map editor with F2 to see the mask and heights). Rooms smaller than the screen are centred on black.

NPC keys: `id` (sprite sheet: an entry in `NPCS`, `PARTNERS`, `CHARACTERS` or `ENEMIES`), `pos`, `talk` (dialogue id; defaults to `id`), `face` (`down`, `up`, `left`, `right`), `fixed` (stand exactly at `pos`, e.g. behind a counter) and `reach` (how close you must be to talk; shopkeepers use 56 to talk over the counter).

### Dialogue
`data/dialogue.json` maps a talk id to `{"name"?: speaker, "branches": [...]}`. The first branch whose `if` matches the player is used:
```json
"mushroom_shop": {"name": "Shopkeeper", "branches": [
  {"if": {"side": "evil"}, "say": ["It costs more for you!"], "choices": [...], "shop": [...]},
  {"say": ["Welcome to the Mushroom Shop! What can I get you?"],
   "choices": [{"text": "Shop", "do": "shop"}, {"text": "Just looking"}],
   "shop": [{"item": "mushroom", "thanks": "Thank you!"}, {"item": "mushroom", "count": 3, "price": 21}]}
]}
```
- `say`: pages shown in turn (`"random": true` picks one). With `choices`, the last page stays up as the question.
- Conditions in `if`: `side` (`good`/`evil`), `min_level`, `max_level`, `party_full` (true/false).
- A choice can `say` more pages and `do` one of `recruit` (partners only), `shop` (a Buy / Sell counter for the branch's `shop` list: `item` is an id from `ITEMS` in game.gd, `count` a bundle size, `price` defaults to the item's own price times the branch's `markup`, `thanks` is said after buying; anything you carry can be sold for half its price) or `heal` (full HP and SP for the party; `done` is the line shown after).
- `{name}` and `{character}` in any line become the player's name and character.
- Partners need no entry: they say their `line` from `PARTNERS` and offer to join (and back away from evil players). An entry with their id overrides that.

## Maps: ground, props and the map editor
Each map is one picture plus its data files:
- **`<map>_mask.png`** says where the *ground* is walkable (white) or blocked (black): water, lava, cliffs, ledges, walls and the map edge. It does not block trees or buildings.
- **`<map>_props.json`** lists the tall things: trees, houses, shops, lamp posts, statues, pillars. Each prop is a rectangle of the map picture, a **base line** (the y where its trunk or wall meets the ground) and an optional **footprint** (a small rectangle that blocks walking: a trunk, the front wall of a house). The game redraws each prop over the characters, sorted at its base line, so anyone whose feet are above the base line is behind it. The prop fades to half see-through while it hides the player, like in Superstar Saga. `shape` is `rect` for buildings and posts or `tree` for a rounded canopy with a trunk.
- **`<map>_height.png`** (outdoor maps, optional) is the **height layer**: how high the ground is. Black is level 0, each step of 50 brighter is one level up (50 = level 1, 100 = level 2, up to 200 = level 4), and white (255) marks a **ledge face**, the drawn side of raised ground. Walking onto ground one level higher needs a jump at least 16px high (13 with the slack); two levels up is a cliff. Walking onto lower ground just drops you. A ledge face is never walkable: walking *up the screen* into one climbs it if your jump is as high as the face is tall (a 10px terrace wall is easy, a 28px hedge needs a full jump, a 70px cliff can't be done), and walking *down the screen* into one drops you to the ground below it. Sideways, a face is a wall. Your feet move across the face in one step and the jump height changes by the same amount, so the sprite stays put and it looks like landing on top or falling off (`world.gd`, "Height"). Followers walk the leader's path: they jump where the leader jumped, wait at the bottom of a ledge until their own jump is high enough, and drop where the leader dropped. Enemies never change level, and only touch you on their own level. A map without the file is flat.
- Everyone (player, followers, enemies) collides with a 10px-wide box at their feet; other online players are shown on the nearest walkable ground.

### Map editor (debug builds only)
Run the game from the Godot editor (F5), walk to a map and press **F2**. Players never see it: the published web game is a release build. (A release build started with `-- --map-editor` also has it.)
- The mask shows tinted red where the ground is blocked. Props show as green boxes, the base line in pink and the footprint in orange.
- **1** paints walkable ground, **2** paints blocked ground (left mouse; right mouse paints the opposite). **[** and **]** change the brush size.
- **3** edits props: click a prop to select it and drag to move it (base line and footprint move with it). Drag the yellow corner squares to resize, the pink line to move just the base line, the orange box to move the footprint (its corner square resizes it). **N** adds a tree at the mouse, **C** copies the selected prop, **Delete** removes it, **T** switches tree/rectangle shape, **F** adds or removes the footprint.
- **4** paints the height layer, which is drawn over the map: level 1 yellow, 2 orange, 3 pink, 4 purple (level 0 clear) and ledge faces hatched cyan. Left mouse paints the current level, right mouse picks the level under the mouse, **-** and **=** step through levels 0-4 and "ledge face". **H** hides or shows the heights. The status line says what is under the mouse. Painting a level doesn't change the walk mask (paint ground with 1 too if it was blocked); a face is never walkable whatever the mask says.
- Arrow keys or WASD pan, the mouse wheel zooms. **Ctrl+S** saves `<map>_mask.png`, `<map>_height.png` (if the map has one or you painted heights) and `<map>_props.json` straight into `assets/maps/` (in an exported debug build they go to `user://maps/` instead and are used from there). **F2** closes the editor; the game uses your edits right away.
- After saving, commit the files (and run `godot --headless --path game --import` for a new height file). `tools/make_maps.py` rebuilds masks from scratch and would overwrite hand edits, so only re-run it for a new map. It keeps an existing `<map>_height.png` and says so; pass `--heights` to rebuild it from the `height` entry in its `MAPS` table (raised boxes, colour flood fills, ledge face boxes and automatic faces found by wall colour).

## Adding art
The tools read the original sheets from the `Mario&LuigiMMO` art folder (not in this repo):
- `python3 tools/slice_sprites.py "<Mario&LuigiMMO folder>" [ids]` cuts walk cycles. Add a character with the pixel boxes of its down, side and up rows (options for white backgrounds and drawn-on shadows are described at the top of the script), then add it to `CHARACTERS`, `PARTNERS` or `ENEMIES` in `game.gd`.
- `python3 tools/slice_ui.py "<Mario&LuigiMMO folder>"` cuts the menu art (speech balloons, notebook, stat cards, gold digits, icons, title art, the touch A / B buttons and joystick) into `assets/ui/` and builds the two bitmap fonts from the MLSS alphabet. Re-run `godot --headless --import` afterwards.
- `python3 tools/slice_items.py "<Mario&LuigiMMO folder>"` cuts the item pictures into `assets/items/<id>.png` (one per id in `ITEMS`; add an item with its box on the Items sheet).
- `python3 tools/slice_battle.py "<Mario&LuigiMMO folder>"` cuts the battle art into `assets/battle/`: backgrounds (add one by giving its id and spot on the sheet in `BACKGROUNDS`), command blocks and their pictures, A-button badges, rating word art, status icons and the battle start swipe.
- `python3 tools/make_maps.py "<Mario&LuigiMMO folder>" [ids]` crops a map and guesses its walk mask from colours, opening up the ground behind the props in `<map>_props.json` (`python3 tools/make_maps.py --mask-only [ids]` rebuilds just the masks from the art in the repo). Touch up masks and props in the map editor (or `_mask.png` in any paint program: white = walk, black = blocked); re-running the tool overwrites hand-painted masks.

## Publishing
`export_presets.cfg` has a **Web** preset with thread support off, so the build runs on plain static hosting like GitHub Pages. Its head include stops pinch zoom and page scrolling on phones, asks to turn portrait phones sideways, and turns the game sideways when it goes full screen on Android. The game keeps its 384x216 picture and scales it to fit (black bars at the sides on extra-wide phones), because the menus and battles are laid out for that size. `.github/workflows/deploy-pages.yml` (repo root) exports and publishes it on every push to `main`.

## Screenshot
![prototype](screenshot.png)
