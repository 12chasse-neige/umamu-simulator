# Running meet

Choose a runner from the portrait roster, select **Enter Academy**, and follow the track signs to the training oval. At the white starting stripe, press **G** to open race entry. Pick **eight rivals**, choose **Grassland** or **Mudland**, select your running style, and press **Start race**. Click a portrait to toggle it. **Auto-fill** fills any open spots, and the field remembers your last picks while you stay on campus. **Solo practice** times one lap.

## Racing controls

Open **操作说明 / Controls** on the login panel for the key list. The game defaults to Simplified Chinese and saves the language selected with **中文 / EN**. **显示 NPC 名字 / Show NPC names** turns on the overhead name labels for residents and rivals.

Use the mouse to aim and **WASD** to steer. Movement defaults to running. In a meet, move to cruise at 94% of your current race cap. Hold **RMB** while running to push toward the full cap and spend energy faster. Power limits how quickly you can reach that speed. When contact knocks you off pace, steer clear to regain your approach speed quickly, up to the current speed cap. The HUD shows your running style, stage, energy, speed cap and acceleration. **Esc** leaves the meet at your current location. Retry restores your selected strategy, lineup, surface and full energy.

| Strategy | How to race it |
| --- | --- |
| Front Runner | Establish a lead in the opening leg. Defending it takes energy you may need on the final straight. |
| Pace Chaser | Stay close to the leaders and look for a clear passing lane. This style starts with the smallest reserve for a given Stamina stat. |
| Late Surger | Settle in midpack and advance as the final leg opens. Leave room to pass. |
| End Closer | Concede ground early for the highest late speed coefficient. Enter the final leg with energy and a clear line. |

The entry menu shows the selected runner’s five stats and her aptitude for each style. Choose a style before pressing **Start race**. It applies from the countdown through the finish on both surfaces. To choose another style, return to the track and open race entry again.

## Race mechanics

Cygames describes choosing a strategy in the paddock. In the Academy meet you choose at entry, then steer and manage effort during the race. The four phase boundaries, strategy speed and acceleration coefficients, and style-specific Stamina conversion follow the community mechanics reference. Campus speed scaling, energy costs, aptitude penalties and rival decisions are local tuning choices. [Cygames game system](https://umamusume.jp/contents/game/system/) · [Umamusume Wiki racing mechanics](https://umamusu.wiki/Game:Mechanics)

Each runner enters the opening, middle, final and last-sixth stages at 0, 4, 16 and 20 of 24 equal course sections. During the first ten sections, the gap to the leader affects the runner’s target pace. Wit and style aptitude affect the precision of that pace. Power and surface aptitude govern acceleration. Speed and Sprint aptitude contribute to the finishing cap. A runner with energy in reserve can spurt from the two-thirds mark. Guts strengthens the spurt and reduces late energy use. Pushing costs 40% more energy per metre at the same speed. In the final leg, the energy left per metre boosts the spurt speed and acceleration. Below 18% of starting energy, fatigue progressively reduces both limits. A depleted runner can still finish. The HUD shows when you are pushing, producing a strong spurt or running fatigued.

The roster uses five-star initial stats and style, surface and Sprint grades from 35 trainee cards, including the three installed alternate outfits. Runners without a mapped card and named proxies use consistent Academy profiles. All nine entrants use the same limits. Rivals pick their highest-rated style, favoring the less common style in a tie. They watch the gap, their remaining energy and nearby traffic to decide when to press and which line to take through a bend. [Silence Suzuka’s card](https://umamusu.wiki/Game:Silence_Suzuka_%28Innocent_Silence%29) · [Gold Ship’s card](https://umamusu.wiki/Game:Gold_Ship_%28Red_Strife%29)

## Race timing and assets

The primary oval has a 376.5 m centreline. One continuous tread covers the course from the outside rail to the inside rail, including the former strips between the nested circuits. The rails, entrance gap and full-width start/finish stripe are part of the Academy scene. Selecting Grassland or Mudland changes the tread material in place, and that surface stays visible when you leave the race. Mudland applies a 0.86 surface multiplier to running speed and acceleration. Each runner’s Dirt aptitude also affects her acceleration there.

Each start and retry draws the player’s gate at random, from **1** on the inside to **9** on the outside. Rivals fill the other eight gates. Your gate number appears during the countdown. The race clock starts at **Go**. Each racer starts behind the stripe, and forward travel adds to their signed progress along the oval. Stepping off the course returns the runner to their last valid track position. The second full lap ends on a forward finish crossing. Position comes from finish time for completed racers and progress for racers still running. The player sees their own time while waiting for the field. After all nine runners cross the line, the results fade in, the winner portrait appears and the rows reveal each runner’s place and total time.

The start/finish sign stands behind the inside rail, facing across the track. The desktop packages display the start/finish label on the board. The local project can also display the first-season anime illustration from `art/race/hishi-amazon-anime.png` or the supplied image from `art/race/finish-amazon.png`. [Official Hishi Amazon character page](https://anime-umamusume.jp/archive/1st/character/12.html) · [Local roster setup](../design/characters/README.md)

## Race music

Race entry plays **1-05 · Cleats, Powerfully and Lightly**. The three-second countdown uses the closing phrase of **8-01 · Tokyo & Nakayama G1 Race**. At **Go**, `arc-race-bgm.mp3` takes over and loops until results. The results screen plays **8-10 · Tokyo & Nakayama Open Race** once. Cancel or leave a meet to return to the ambient playlist. A retry plays the countdown cue again. Race cues play 8 dB louder than the ambient playlist.

Use these paths relative to the music folder when setting up the dedicated cues.

| Cue | File |
| --- | --- |
| Entry | `02-bgm-am/1-05. am003 -Cleats, Powerfully and Lightly.mp3` |
| Countdown | `01-race/8-01. 1001 cl#2 -Tokyo & Nakayama G1 Race.mp3` |
| Running | `01-race/arc-race-bgm.mp3` |
| Results | `01-race/8-10. 1010 cl#2 -Tokyo & Nakayama Open Race.mp3` |

## Character portraits

The gallery and race entry render portraits from the installed Godot models, including alternate outfits. Portraits are generated in a separate viewport and cached under `user://portraits-v4`. A new model or changed model file queues a new portrait. If fewer than eight rival models are installed, named Academy proxies fill the remaining spots.

## Local accounts

Run `sbt run` from the project root with JDK 21. The game connects to `127.0.0.1:8765`. Use the **Register** and **Sign in** tabs in the account form, or leave the service off to play as a guest. The form accepts usernames of 3–24 letters, digits or underscores and passwords of 8–128 characters. Usernames are case-insensitive.

- `POST /api/registeraccount` creates an account. `POST /api/loginaccount` verifies it. Both take a JSON object with `username` and `password` and return the normalized username on success.
- Scala message plans own validation and credential checks. The account table owns prepared SQL and the uniqueness constraint. Passwords are stored as 256-bit PBKDF2-HMAC-SHA256 digests with distinct 128-bit random salts and 600,000 iterations. [OWASP password storage guidance](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
- The service creates `data/accounts.sqlite3` by default. Set `UMAMU_ACCOUNT_DB` to use another path. For a different local port, set `UMAMU_ACCOUNT_PORT` in the environment of both the service and Godot. The API binds to loopback for this desktop prototype.
- The native UI keeps the signed-in name in memory and clears it when you sign out or exit the game. The database stores accounts. Race results and campus state stay in gameplay.

## Checks

```sh
sbt compile
godot --headless --path . --script res://game/tests/race/check-race-pace.gd
godot --headless --path . --fixed-fps 60 --script res://game/tests/race/check-running-race.gd
godot --headless --path . --fixed-fps 60 --script res://game/tests/race/check-race-balance.gd
```

With the service running, create a test account from the menu, sign out, restart the service, and sign in with that account. Verify that a duplicate username and an incorrect password each show an error. The race check approaches the Academy stripe, opens the entry menu, verifies the chosen eight models, checks the entry selection and verifies that number keys preserve it during the race, checks steering and contact, and completes both two-lap modes. It confirms that the results stay closed while rivals are running, verifies all nine finish times in order, and checks retry with the same lineup.

The balance check drives a proxy along the same inside line against eight named Academy runners. It fixes the player at gate 8 for a repeatable comparison and runs each style and surface twice, once pushing throughout and once cruising in the middle. It checks that saving energy wins more often and that the field wins most full-effort heats.
