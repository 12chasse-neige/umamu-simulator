# Tracen Academy running meet

A single-player 3D racing and campus exploration game built in Godot and Blender. Enter the Academy and walk to its training oval. Choose eight rivals and run two laps on Grassland or Mudland.

![The academy courtyard and fountain rendered in Godot](design/tracen-academy/previews/courtyard-godot.jpg)

## Run the prototype

Use **Godot 4.7.2** with the Forward+ renderer and install **Git LFS** to fetch the campus model.

```sh
git lfs install
git clone https://github.com/12chasse-neige/umamu-simulator.git
cd umamu-simulator
git lfs pull
```

Import `project.godot` in the Godot Project Manager, let the first asset import finish, and press **F5**. Choose a runner from the portrait roster and select **Enter Academy**. Follow the track signs east around the school wing. At the start/finish sign, press **G** to pick eight rivals, a running style and either Grassland or Mudland. **Solo practice** times one lap. A fresh clone uses runner proxies. Install local character exports to race against other models and add choices to the main menu and the campus **Tab** menu. The game loads the selected character’s UniMate library for ground gaits, jumps, stances and traversal when available. [Add movement to a new character](docs/new-character-movement.md) · [Local roster setup](design/characters/README.md) · [Movement and source data](docs/character-movement.md)

On the race oval, use the **mouse** to aim the camera and **WASD** to steer relative to it. Movement uses the run gait during both the meet and solo practice. Hold the **right mouse button** while running to push toward the current speed cap. Cruise to save energy for a stronger final spurt. Below 18% energy, fatigue progressively lowers your speed cap and acceleration. Choose **Front Runner**, **Pace Chaser**, **Late Surger** or **End Closer** at race entry. Your style is fixed for both laps. Each start draws your gate at random from 1 on the inside to 9 on the outside. Rivals choose a style suited to their stats, contest position and look for space to pass. Guard rails bound the continuous track surface. Mudland applies a 0.86 pace multiplier, and Dirt aptitude affects acceleration. The second lap finishes at the stripe beside the Amazon sign. Once all nine runners finish, the results reveal the winner, every place and each total time. Press **Esc** to leave the race and continue exploring.

### Campus controls

The game starts in Simplified Chinese. Use **中文 / EN** on the login panel to change languages. The game remembers your choice. The **操作说明 / Controls** button on the same panel opens the key list. Turn on **显示 NPC 名字 / Show NPC names** to see name labels during campus exploration and meets.

| Input | Action |
| --- | --- |
| WASD | Jog relative to the camera |
| Mouse | Orbit the third-person camera |
| Alt | Hold to walk |
| Shift | Hold to run while exploring. |
| Hold right mouse while running | Push toward your style and stage cap in the two-lap meet. In exploration and solo practice, accelerate toward 5.1 m/s on level ground. |
| C | Hold to squat. |
| Z | Hold to lie face down, then release to stand. |
| Space | Jump. Press again in the air for a second jump. |
| F, then WASD | Grab a wall, ledge, or tree. WASD traverses a wall. W and S climb a tree. F releases the grip. Hold W at a clear wall top to pull up. |
| G | Open the race entry menu at the oval's starting stripe. During a solo practice lap, press G to cancel. |
| E | Open or close a bedroom door when prompted |
| T | Advance to the next time-of-day preset |
| Tab | Pause and choose a character. Select a name and press Enter or click Switch. |
| R | Return to the gate |
| Esc / left click | Release or recapture the mouse |
| F2 | Return to the running meet menu |

Run directly toward a low barrier to vault it. One Academy day lasts **24 real minutes**. Press **T** to skip to the next lighting preset. Installed roster characters wander outdoors and inside the Academy, including the library, residences, gym, dining arcade, faculty pavilions and grandstand. They choose their next destination as they walk and use doors, stairs and connecting passages. You can bump into residents as they walk. Their name labels are hidden by default. Campus residents require installed character models. Character switching keeps your position and camera angle. Follow the signs around the academy wing to the outer rail opening. The training oval has its own timed practice lap. [Development roadmap](docs/develop-plan.md)

## Background music

Put local tracks in `design/music/` or in any folder beneath it; the playlist walks the whole tree. The ambient playlist shuffles tracks across the main menu and campus. It skips `01-race/`, `06-stingers/` and the race-entry cue. Dedicated tracks take over for race entry, the countdown, running and results. The ambient track resumes when you return to campus. It scans for Ogg Vorbis, MP3 and WAV files and loads them directly, so no conversion step or extra tool is needed at play time. FLAC is not scanned; convert lossless sources once before dropping them in:

```sh
ffmpeg -nostdin -i track.flac -map 0:a:0 -vn -c:a libmp3lame -q:a 4 -map_metadata 0 track.mp3
```

The current library keeps the album rip in the game's own id families:

| Folder | Tracks | Contents |
| --- | --- | --- |
| `01-race/` | 27 | Dedicated race cues and the Arc race BGM |
| `02-bgm-am/` | 59 | `am###` short event and story cues |
| `03-bgm-gm/` | 186 | `gm###` in-game BGM: campus, career, races and results |
| `04-bgm-dm/` | 36 | `dm###` home screen and menu BGM |
| `05-songs/` | 93 | `sm`, `cs` and `live` songs, instrumentals, karaoke and live takes |
| `06-stingers/` | 10 | `jingle` and `fx` cues |

## Player accounts

Races and campus exploration work as a guest. To create an account or sign in, start the Scala service from the repository root with **JDK 21** and **sbt**.

```sh
sbt run
```

Keep the service running while you use the account panel. It listens on `127.0.0.1:8765` and creates `data/accounts.sqlite3` on first start. Account credentials persist across restarts. The signed-in profile lasts for the current Godot session, and race times are local to each race. [Race and account implementation](docs/running-meet.md)

## Desktop packages

Extract the macOS ZIP and open `Tracen Academy.app` on Apple Silicon or Intel. The app uses an ad-hoc signature and has no Apple notarization. On 64-bit Windows, extract the ZIP and run `Tracen-Academy.exe`. Both packages contain the guest game and proxy racers. Campus residents and character artwork use optional local assets in the source project. To use accounts with either desktop package, run the service separately as described above. [Godot’s macOS launch guide](https://docs.godotengine.org/en/stable/tutorials/export/running_on_macos.html)

To add your own soundtrack to an exported game, put your tracks in `~/Library/Application Support/Godot/app_userdata/Tracen Academy/music/` on macOS or `%APPDATA%\Godot\app_userdata\Tracen Academy\music\` on Windows. Keep the folder names and filenames described under [Background music](#background-music) and [Race music](docs/running-meet.md#race-music) for the four dedicated cues. Restart the game after adding music.

To build the same packages, start from a clean clone with `git lfs pull` complete and install the matching Godot 4.7.2 release export templates under **Editor → Manage Export Templates**. Run these commands from the repository root on macOS.

```sh
mkdir -p exports
godot --headless --path . --import
godot --headless --path . --export-release macOS exports/Tracen-Academy-macOS.zip
godot --headless --path . --export-release 'Windows Desktop' exports/Tracen-Academy.exe
zip -j exports/Tracen-Academy-Windows-x86_64.zip exports/Tracen-Academy.exe
```

The Windows preset embeds the project data in the executable. The macOS preset places the project data inside the app bundle. Keep ETC2/ASTC texture importing enabled for the universal macOS build. Both packages include the shared campus scene and its imported art. [Desktop export presets](export_presets.cfg)

For a desktop package with bundled music, use a separate staging copy of the project. Replace its `design/` directory with one containing only the `music/` tree. Keep the audio files in their original folders, set their import mode to **Keep File**, and remove `design/*` from both presets' resource exclusion filters in the staging copy. Run the same export commands. These builds play the bundled library on launch and use the same campus exclusions and race cues as the source project.

## Project files

| Path | Contents |
| --- | --- |
| `game/race/` | Academy oval geometry, race entry and HUD, NPC steering, surfaces and trackside sign |
| `game/campus/` | Campus scene, collision, doors, day/night lighting and timed practice lap |
| `game/runner/` | Player controller, camera and gait state, with traversal and posing in their own folders |
| `game/ui/` | Main menu, account form, shared theme and character portrait picker |
| `services/` | Scala account API, SQLite persistence and local HTTP server |
| `game/tests/` | Headless campus and runner regression checks |
| `game/tools/` | Offline Godot tool for packing the local animation library |
| `art/campus/` | Editable Blender campus and kit, Godot-ready GLB, environment preview, and Blender exporter |
| `design/` | Campus references and previews, texture studies, character tooling, and UniMate motion inputs |
| `docs/` | Code map, development roadmap, campus art and movement workflows |

Start a code review with the [project structure and test coverage guide](docs/project-structure.md).

The campus handoff covers opening and exporting the Blender scene, running the Godot art preview, and the sources of the campus assets. [Campus art and credits](art/campus/README.md) · [Campus guide](design/tracen-academy/campus-guide.png) · [Texture prompts](docs/campus-texture-prompts.md)

Godot recreates `.godot/` on import. Character downloads, exported local rigs, UniMate weights, Python environments, and generated animation libraries live outside Git. The proxy and tracked campus assets are enough to review the base game. [Local roster setup](design/characters/README.md) · [Animation workflow](docs/character-movement.md)

## Run the gameplay checks

With the project imported, run these commands from the repository root. Use the path to your Godot executable in place of `godot` if it is outside your shell's PATH.

```sh
godot --headless --path . --fixed-fps 60 --script res://game/tests/campus/check-academy-residents.gd
godot --headless --path . --script res://game/tests/race/check-race-pace.gd
godot --headless --path . --fixed-fps 60 --script res://game/tests/race/check-running-race.gd
godot --headless --path . --fixed-fps 60 --script res://game/tests/race/check-race-balance.gd
godot --headless --path . --fixed-fps 60 --script res://game/tests/campus/walk-campus-links.gd
godot --headless --path . --fixed-fps 60 --script res://game/tests/campus/check-residence-doors.gd
godot --headless --path . --fixed-fps 60 --script res://game/tests/campus/check-tree-collision.gd
godot --headless --path . --fixed-fps 60 --script res://game/tests/campus/check-campus-landmarks.gd
godot --headless --path . --fixed-fps 60 --script res://game/tests/runner/check-runner-movement.gd
godot --headless --path . --fixed-fps 60 --script res://game/tests/runner/check-character-switching.gd
godot --headless --path . --fixed-fps 60 --script res://game/tests/runner/check-roster-runs.gd
```

For a command-line-only first run, initialize the import cache with `godot --headless --path . --import`. The runner check exercises the installed character. Append `-- --proxy` for a proxy-only pass. The local Special Week setup includes a separate garment and finger skin and four skirt cycles. [Build and verify the local skin](docs/character-movement.md#building-the-local-finger-and-skirt-rig)
