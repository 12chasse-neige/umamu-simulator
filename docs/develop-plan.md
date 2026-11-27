# Tracen Academy 3D exploration and training game

The playable Godot prototype opens on the running meet menu. Players choose a character and explore the Academy alongside other trainees on a 24-minute day cycle. At the training oval they can choose eight rivals and race on Grassland or Mudland or time a solo practice lap. The local roster includes 39 rigged models. Special Week uses her approved motion library. The other roster entries use their own generated runs on level ground. [Run the prototype](../README.md) · [Review the code and checks](project-structure.md)

The packaged **macOS and Windows** demo adds login and persistence. On return, a player should recover their selected character, last campus landmark and personal best.

## Development milestones

| Milestone | Status | Next acceptance check |
| --- | --- | --- |
| [1. Make the campus playable](milestone-1-campus.md) | Playable campus and third-person runner are in Godot. | New players find the track from the gate and reach it without getting caught on the route. |
| 2. Build the running meet | The Academy oval hosts both surfaces, with in-world race entry, four running styles chosen before the start, character-based rival pacing, two-lap timing and an animated results reveal. | Tune rival difficulty and each surface using repeat races with the release roster. |
| 3. Connect accounts and progress | Local Scala registration and sign-in are available. Persistent race and campus progress are planned. | Two accounts can use the same installation. After restarting the game and service, each player resumes at the correct landmark with their own best time. |
| [4. Finish Tracen](campus-art-production.md) and the roster | Campus art, furnished rooms and local character switching are in the prototype. | Validate the selected release models on the same route and lap, including grounded starts, stops and turns. |
| 5. Package the desktop demo | Planned. | A tester on each desktop platform can start with a fresh database, register, complete a lap and recover the result after relaunch. |

## How the three tools fit together

- **Blender owns the artwork.** Keep editable `.blend` sources under `art/` and export `.glb` assets into the Godot project. The current exterior ships as one full-campus GLB. Keep the gate, frontage and track in separate Blender collections so each remains editable. For sourced characters, record the creator and permitted use, normalize scale and forward direction, and map idle, walk, and run clips to the same animation names. Distinct skeletons can then use the same player controller. [Godot’s Blender and glTF import guide](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html)
- **Godot owns gameplay.** Use the installed Godot 4.7.2 with GDScript. The player uses one `CharacterBody3D` with a capsule collider, a swappable visual model, and a `SpringArm3D` camera. Actual ground travel advances the UniMate gait clips. Traverse and contact code sets the hand and foot targets on stairs, walls, trunks and ladders. Practice laps use the same running gait and pace as exploration. The two-lap meet uses that gait with style, stage, energy and surface limits for each runner. Measure laps in Godot so the finish time is independent of the server response. [Movement and source data](character-movement.md) · [Godot’s third-person camera guide](https://docs.godotengine.org/en/stable/tutorials/3d/spring_arm.html)
- **Scala owns account persistence.** The local prototype uses Scala 3, Cats Effect and SQLite in `services/`. Registration and sign-in verify salted password hashes. For the saved-progress milestone, add server-validated identity, authenticated progress APIs and idempotent result submission. Store durations as integer milliseconds and derive each personal best from completed races. [Account implementation](running-meet.md#local-accounts)

## Demo assumptions and final checks

- **Campus scope:** one connected outdoor route. Make the academy entrance recognizable from the front gate and the track easy to find from the courtyard. The main building can serve as an exterior landmark for this release.
- **Asset dependency:** the tracked project ships with a proxy. Special Week is the local reference rig, and the selector also lists compatible GLBs installed under `art/characters/`. The packaged demo needs redistribution rights for its chosen models. [Local roster setup](../design/characters/README.md)
- **Deployment:** each demo machine currently runs its own local Scala service and SQLite account database. For future result saving, keep the result visible on a failed request and confirm the save after the service acknowledges it.
- **Acceptance:** test both characters on both platforms, including a slower second lap, a faster retry, a skipped checkpoint, a lost save response, and a server restart. The decisive test is whether a new player can find the track unaided, set a time, and come back later to beat it.

The Blender-to-Godot workflow and account example draw on slides 5, 8, and 10 of `lec6.pptx`. The campus, roster, and timed training loop follow your game choices.
