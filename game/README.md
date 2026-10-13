# Mario & Luigi MMO (Godot 4 prototype)

A Superstar Saga style RPG starter that runs in the browser.

## Open it
1. Install Godot 4.4 or newer (standard version, not .NET).
2. In the Project Manager choose **Import**, pick this folder's `project.godot`, then press **F5** to play.

## Controls
| Action | Keyboard | Gamepad |
|---|---|---|
| Move | Arrows / WASD | D-pad |
| Mario (jump, timed hits, dodge) | Z or J | A |
| Luigi (jump, timed hits, dodge) | X or K | B |

## What's here
- `scenes/overworld.tscn` (main scene): a placeholder field. Mario leads and Luigi follows his path; each brother jumps with his own button. Goombas wander and start a battle on touch.
- `scenes/battle.tscn` + `scripts/battle.gd`: turn-based battle stub with timed hits. Press the brother's button to Jump, then again right as he lands for a second stomp (Good / Excellent). On the enemy's turn, jump as it reaches you to dodge.
- `scripts/game.gd` (autoload `Game`): input map, party stats, enemy table, scene switching.
- `scripts/bro_sprite.gd`: shared brother sprite (8 frames x 5 directions, left is mirrored) with jump physics.
- `assets/sprites/`: frames cut from the Superstar Saga sheets in the parent folder.

## Publish to the web for free (GitHub Pages)
- `export_presets.cfg` has a **Web** preset with thread support off, so the build runs on plain static hosting like GitHub Pages (no special server headers needed).
- Manual: Project > Export > Web > Export Project into `build/web/`, then upload that folder.
- Automatic: the deploy workflow lives in `/deploy-pages/.github/workflows/deploy-pages.yml` in the project files; it uses this "Web" preset.

## Screenshot
![prototype](screenshot.png)

## Next steps
- Real maps: build a TileMapLayer from the `Maps` sheets in place of `scripts/ground.gd`.
- Battle menu (Jump / Hammer / Bros. Attack / Items), more enemies from `Enemies/`.
- Multiplayer: GitHub Pages only serves files, so players need a free relay or peer-to-peer (WebRTC) signaling service alongside it.
