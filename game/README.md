# Mario & Luigi MMO (Godot 4)

A Superstar Saga style RPG that runs in the browser. Play the latest build at
https://rileymusil.github.io/mario-luigi-mmorpg/ (every push to `main` redeploys).

## Open it
1. Install Godot 4.4 or newer (standard version, not .NET).
2. In the Project Manager choose **Import**, pick this folder's `project.godot`, then press **F5** to play.

## Controls
| Action | Keyboard | Gamepad |
|---|---|---|
| Move | Arrows / WASD | D-pad |
| Jump, confirm, timed presses | Z, J or Space | A |
| Talk, ask, back | X or K | B |
| Menu | Enter or Esc | Start |

## What you can do
- **Pick a side and a character.** Good: Mario, Luigi, Princess Peach, Waluigi, Rosalina, Toadette. Evil: Bowser, Bowser Jr., Shadow Mario.
  Good players start in Beanbean Castle Town, evil players at Bowser's Castle.
- **Explore three maps** built from the Superstar Saga map art: Castle Town, Beanbean Outskirts and Bowser's Castle, joined by exits at the town gates, the Outskirts' south path and east bridge, and the castle's rail bridge.
- **Battle** enemies in the Outskirts (Goombas, Galoombas, Beanies, Koopa Troopas, Shy Guys, Buzzy Beetles and Dry Bones). Touch one to fight; jump on it first for a first strike.
  - *Jump*: press Z as you land for a second stomp (Good / Excellent).
  - *Special* (costs SP): Mario's Fire Jump burns, Luigi's Thunderhand can stun, Peach's Heart heals the party, Bowser's Fire Breath hits every enemy, Waluigi's Wicked Whirl hits every enemy and can stun them, Rosalina's Star Spin hits and heals, Toadette's Pickaxe Pound ignores defense, Bowser Jr.'s Goop Paint can stun, Shadow Mario's Shadow Drain steals HP. Press Z in the gold zone.
  - *Enemy turns*: press Z so whoever is attacked is in the air when it hits.
- **Recruit.** Good players ask Toad or the Pianta in Castle Town (X to talk). Evil players use *Ask to join* in battle; hurt enemies say yes more often. Up to 2 follow you and fight on their own turn.
- **Grow.** XP and levels (cap 50), coins, Mushrooms. Losing sends you home with a few coins lost.
- **Switch sides** any time from the menu. **Saves** go to the browser automatically.

## Project layout
- `scenes/title.tscn` (main scene), `scenes/world.tscn` (any map), `scenes/battle.tscn`.
- `scripts/game.gd` (autoload `Game`): all data tables (characters, specials, partners, enemies, maps with exits, spawns, enemies and NPCs), the save, and scene changes. Most tuning happens here.
- `scripts/world.gd`: map loading, walking on the walk mask, followers, enemies, talking, pause menu.
- `scripts/battle.gd`: battle flow, timed presses, specials, recruiting, XP.
- `scripts/character_sprite.gd`, `scripts/choice_menu.gd`: shared sprite and menu box.
- `ui/theme.tres`: the project's default theme (Superstar Saga font, speech-balloon panels and the
  `NavyPanel`, `StripPanel`, `NotebookPanel`, `RedCard`/`GreenCard`, `FlatPanel` and
  `LightLabel`, `InfoLabel`, `TitleLabel`, `OutlineLabel`, `GoldLabel` variations).
  `ui/` also holds the reusable pieces: `dialogue_box` (typed-in speech balloon), `hud`,
  `area_banner`, `pause_screen` (notebook), `party_screen` (stat cards) and `gold_number`.
- `assets/ui/`: menu art and the bitmap fonts (`mlss_font.fnt`, `mlss_font_outline.fnt`).
- `assets/characters/`: walk sheets, 3 rows (down, right, up). `assets/maps/`: map art plus `<map>_mask.png` (white = walkable).

## Adding art
The tools read the original sheets from the `Mario&LuigiMMO` art folder (not in this repo):
- `python3 tools/slice_sprites.py "<Mario&LuigiMMO folder>" [ids]` cuts walk cycles. Add a character with the pixel boxes of its down, side and up rows (options for white backgrounds and drawn-on shadows are described at the top of the script), then add it to `CHARACTERS`, `PARTNERS` or `ENEMIES` in `game.gd`.
- `python3 tools/slice_ui.py "<Mario&LuigiMMO folder>"` cuts the menu art (speech balloons, notebook, stat cards, gold digits, icons, title art) into `assets/ui/` and builds the two bitmap fonts from the MLSS alphabet. Re-run `godot --headless --import` afterwards.
- `python3 tools/make_maps.py "<Mario&LuigiMMO folder>" [ids]` crops a map and guesses its walk mask from colours. You can touch up any `_mask.png` by hand in a paint program (white = walk, black = blocked); re-running the tool overwrites hand edits.

## Publishing
`export_presets.cfg` has a **Web** preset with thread support off, so the build runs on plain static hosting like GitHub Pages. `.github/workflows/deploy-pages.yml` (repo root) exports and publishes it on every push to `main`.

## Screenshot
![prototype](screenshot.png)
