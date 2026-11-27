# Review the Godot project

The playable entry point is the [running meet menu](../game/ui/meet-menu.tscn). It opens [campus exploration](../game/campus/campus-walk.tscn). The campus includes the [two-lap race controller](../game/race/running-race.tscn) at the training oval and shares its art scene with the [standalone daylight preview](../art/campus/campus-preview.tscn).

| Area | Where to start |
| --- | --- |
| Running meet | [running-race.gd](../game/race/running-race.gd) opens entry at the Academy starting stripe and runs the meet with the existing player body. It builds the grid and steers rivals through traffic. [race-profile.gd](../game/race/race-profile.gd) supplies character stats and aptitudes. [race-pace.gd](../game/race/race-pace.gd) calculates both player and rival limits, energy use and rival effort. [race-results.gd](../game/race/race-results.gd) animates the final order after all nine finish. [race-field.gd](../game/race/race-field.gd) builds the shared tread, guard rails and finish marker for exploration and races. [race-progress.gd](../game/race/race-progress.gd) tracks signed course distance, completed laps and crossing times. |
| Accounts | [services/accounts](../services/accounts/) owns registration, login, password hashing and the account table. [services/system](../services/system/) owns routing and SQLite connections. |
| Campus and practice laps | The [campus scene](../game/campus/campus-walk.tscn) assembles the level, collision and doors. [academy-residents.gd](../game/campus/academy-residents.gd) places installed characters around campus and lets each choose a new destination as they walk. Actors load nearby and the active player’s character is excluded. [academy-walkways.gd](../game/campus/academy-walkways.gd) combines authored doors and stairs with collision-checked connections between nearby rooms and outdoor paths. The player and residents have capsule contact. Residents can pass each other through tight corridors. [campus-time.gd](../game/campus/campus-time.gd) runs the 24-minute clock and lighting presets. [track-race.gd](../game/campus/track-race.gd) owns the countdown, checkpoints and lap result. |
| Player movement | [runner.gd](../game/runner/runner.gd) owns the capsule, camera and active character. [runner-control.gd](../game/runner/runner-control.gd) owns the gait, exploration and solo-practice speed ramp, horizontal motion and flight state. |
| Traversal | [game/runner/traversal/](../game/runner/traversal/) holds the wall and ledge probes, climbing contacts and vault planner. The runner applies their results to the capsule. |
| Posing and playback | [game/runner/pose/](../game/runner/pose/) fits the skeleton to the terrain and samples Special Week’s approved clips. It also handles tail motion and skirt clearance. |
| Character and account UI | [game/ui/](../game/ui/) contains the shared theme, account form, controls popup, portrait galleries and portrait viewport. [game-language.gd](../game/app/game-language.gd) applies the saved language at startup and defaults to Simplified Chinese. [game-preferences.gd](../game/app/game-preferences.gd) saves language and name-label visibility. [zh_CN.po](../game/i18n/zh_CN.po) supplies the Chinese interface text. |
| Background music | [background-music.gd](../game/app/background-music.gd) shuffles local Ogg Vorbis, MP3 and WAV tracks for exploration. It skips the race and stinger folders and switches to dedicated cues at the meet controller’s race transitions. |
| Art and offline tools | [art/campus/](../art/campus/) contains the editable campus, export and preview. [game/tools/](../game/tools/) packs Special Week’s clips, retargets roster movement and samples poses for garment fitting. [design/unimate/locomotion/](../design/unimate/locomotion/) prepares rigs, runs inference and bakes clips. |

The capsule determines the player’s world position. The display rig follows it, with the pose solver handling visible foot and hand contact. Special Week’s local trial rig plays the approved motion library. The other roster rigs load per-character movement libraries from `art/characters/motions/`. The proxy works with the tracked project on its own. [Movement and clip workflow](character-movement.md) · [Roster setup](new-character-movement.md)

## Regression checks

Import the project before running the checks. Commands are listed in the [project README](../README.md#run-the-gameplay-checks).

| Check | Coverage |
| --- | --- |
| [Race balance](../game/tests/race/check-race-balance.gd) | Sixteen nine-runner proxy heats compare pushing throughout with a mid-race cruise across four styles and both surfaces. |
| [Race pace](../game/tests/race/check-race-pace.gd) | Four stage boundaries, style and character limits, surface effects and exhaustion. |
| [Running race](../game/tests/race/check-running-race.gd) | Pre-race style selection and in-race lock, eight selectable rivals, all nine start gates, rails, mouse steering, early inside lines, rival contact and recovery, both two-lap modes, nine ordered finish times, retry and exploration. |
| [Academy residents](../game/tests/campus/check-academy-residents.gd) | Encounter the installed roster and verify model-only spawning, name visibility, player contact, varied route choices, door and stair traversal, race handoff, character switching and clock behavior. |
| [Campus landmarks](../game/tests/campus/check-campus-landmarks.gd) | Load-bearing surfaces, fountain contacts and the stump. |
| [Residence doors](../game/tests/campus/check-residence-doors.gd) | Interact with the residence doors and cross their thresholds. |
| [Campus links](../game/tests/campus/walk-campus-links.gd) | Walk the authored route segments and room connections. |
| [Tree collision](../game/tests/campus/check-tree-collision.gd) | Walk into the approach trees and verify the trunks block the runner. |
| [Character switching](../game/tests/runner/check-character-switching.gd) | Open the picker with Tab, select by keyboard or button, bind installed rigs and preserve player position. Pass `-- 39` to require the complete local roster. |
| [Runner movement](../game/tests/runner/check-runner-movement.gd) | Exercise gaits, hold-to-accelerate running, timed laps, stairs, jumps, climbing, vaulting and ball contact on Special Week with campus foot traffic disabled. Pass `-- --proxy` for the capsule alone or pass a local character GLB without an authored movement library after `--` to check its procedural baseline. |
| [Roster movements](../game/tests/runner/check-roster-runs.gd) | Verify the 24-action libraries, source periods, expected gaits, run rotations and shared top speed. Includes a timed lap. Pass `-- 38 --full` to require the complete local roster. |

## Source and generated data

- `art/campus/campus.blend` and `kit.blend` are editable sources. The runtime `campus.glb` is tracked with Git LFS. Keep Godot’s tracked `.uid` and `.import` files with their resources. [Campus asset handoff](../art/campus/README.md)
- `design/characters/` holds the local FBX files and textures. The exporter installs display GLBs under `art/characters/`. Special Week’s generated gameplay skin and approved motion library live under `art/special-week/`. [Character sources and credits](../design/characters/README.md)
- `design/unimate/` holds the local checkpoint, Python environments, prepared rigs, bakes and measurements. A full roster run keeps its bakes under `movements/<slug>/` and its completed model list in `roster-status.json`. The versioned inputs in `locomotion/` supply the gameplay picks, prompts and original UniMate sampling recipes.
- Godot rebuilds `.godot/` after import. Store one-off logs, benchmarks and capture fixtures in a separate work directory so the source tree stays readable.
