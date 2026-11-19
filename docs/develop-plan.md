# Tracen Academy 3D exploration and training game

Build a single-player demo for **macOS and Windows**. The player logs in, chooses an Umamusume, and enters Tracen Academy at the front gate. They can explore the campus, follow the path to the training track, and run a timed lap. On their next visit, the game restores their character, last campus landmark, and personal best.

The **first playable milestone** is one placeholder runner completing a lap on a rough campus. That gives you a way to judge the scale of Tracen, the feel of running, and the camera before investing in scenery or waiting for character models. You’ll choose the final two models later.

## Development milestones

| Milestone | Work | Ready when |
|---|---|---|
| [1. Make the campus playable](milestone-1-campus.md) | In Blender, block out the front gate, academy building, courtyard, connecting path, and training oval at a consistent scale. In Godot, add a placeholder runner with camera-relative WASD movement, Shift to run, and a mouse-controlled third-person camera. | A player can find the track from the gate, run around its bends, and turn the camera near walls and fences without losing sight of the runner. |
| 2.Build the timed lap | Place a start line and ordered checkpoints around the oval. Let the player start a countdown, see elapsed time and the next checkpoint, finish a lap, and immediately retry. Allow them to abandon a run and return to exploration. | A full lap produces a time. Crossing the finish line early, running backward across it, or skipping a checkpoint cannot finish the lap. |
| 3.Connect accounts and progress | Add registration and login in Godot. Have Scala save the selected character and last reached landmark, record completed laps, and return the personal best for each character on the track. | Two accounts can use the same installation and see their own progress. After restarting the game and server, each player resumes at the correct landmark with the correct best time. |
| 4.Finish Tracen and the roster | Replace the blockout with a recognizable academy frontage, gate, courtyard landscaping, track markings, and rails. Import the first chosen character and tune its running animation in motion. Then add the second character and a selection screen. | Both characters can complete the same route and lap. Switching preserves the player’s location, and each runner’s feet meet the ground through starts, stops, and turns. |
| 5. Package the desktop demo | Export native macOS and Windows builds. Package the Scala service with database migrations and provide startup instructions for each platform. Run the complete demo on each OS. | From a fresh database, a tester can start the service, register, select either runner, complete a lap, quit, and recover the result after relaunch. |

## How the three tools fit together

- **Blender owns the artwork.** Keep editable `.blend` sources under `art/` and export `.glb` assets into the Godot project. Export the gate, academy frontage, and track separately so you can revise one without rebuilding the campus. For sourced characters, record the creator and permitted use, normalize scale and forward direction, and map idle, walk, and run clips to the same animation names. Distinct skeletons can then use the same player controller. [Godot’s Blender and glTF import guide](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html)
- **Godot owns gameplay.** Use the installed Godot 4.7.2 with GDScript. Give the player one `CharacterBody3D` with a capsule collider, a swappable visual model, and a `SpringArm3D` camera. Let the controller drive movement and use actual ground speed to blend the animations. Measure laps in Godot so the finish time is independent of the server response. [Godot’s third-person camera guide](https://docs.godotengine.org/en/stable/tutorials/3d/spring_arm.html)
- **Scala owns accounts and durable progress.** Use Scala 3, Cats Effect, http4s, and PostgreSQL in `server/`. Provide registration and login endpoints, authenticated `GET` and `PUT /me/progress`, and `POST /me/laps`. Hash passwords, issue expiring bearer tokens, and derive account ownership from the token. Give each completed lap a unique ID so a retry after a dropped response records it once. Store durations as integer milliseconds and derive each personal best from the fastest completed lap. [http4s documentation](https://http4s.org/)

## Demo assumptions and final checks

- **Campus scope:** one connected outdoor route. Make the academy entrance recognizable from the front gate and the track easy to find from the courtyard. The main building can serve as an exterior landmark for this release.
- **Asset dependency:** no character models are currently in the project. The placeholder supports movement, training, and backend development. The finished roster milestone requires two models you select with terms suitable for the intended demo.
- **Deployment:** each demo machine runs its own local Scala service and PostgreSQL database. Accounts and records belong to that installation. If saving fails after a lap, keep the result visible with a retry action and confirm success only after the server acknowledges it.
- **Acceptance:** test both characters on both platforms, including a slower second lap, a faster retry, a skipped checkpoint, a lost save response, and a server restart. The decisive test is whether a new player can find the track unaided, set a time, and come back later to beat it.

The Blender-to-Godot workflow and account example draw on slides 5, 8, and 10 of `lec6.pptx`. The campus, roster, and timed training loop follow your game choices.
