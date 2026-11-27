# Character movement

Press **Tab** to switch between the 39 rigged models in the local installation. Special Week uses her approved library. Each of the other 38 characters loads a full movement library retargeted from its own generated body rig. [New-character movement guide](new-character-movement.md)

| Input | Movement |
| --- | --- |
| WASD | Jog relative to the camera. |
| Alt + WASD | Walk. |
| Shift + WASD | Hold Shift to run while exploring. |
| Hold right mouse while running | In exploration and solo practice, accelerate toward 5.1 m/s. In the two-lap meet, push toward the current strategy cap. |
| C / Z | Hold C to squat, or Z to get down on the ground. Release to rise when there is room. |
| Space | Jump and, with a second press in the air, jump again. |
| F | Face a wall, low ledge or trunk and grab it. Press again to release. |
| WASD on a wall | Climb in four directions. Hold W at a clear top to pull up. Face out from a ledge and press F to climb down. |
| W / S on a tree | Climb up or down. Release the directional key to pause. |
| G near the track start stripe | Start or cancel a timed lap. Movement starts after the three-second countdown. |
| R | Return to the gate. |

Approach a narrow barrier at a jog or run to vault it automatically. The controller limits a vault to barriers between 0.28 and 0.83 m high with a walkable landing and clearance across the capsule's path. Use the amphitheatre stairs for both stair gaits, the low barrier to their east for a vault, and the trunks lining the entrance avenue for tree climbing.

## UniMate animation

### Regenerated roster libraries

The reference-label batch produced 858 takes across 39 rigged characters. The roster packer verifies each take’s provenance and retargets 24 actions from 22 takes for each display rig. Jump and landing share a take, and wall descent reverses the ascent. The library supplies the pose for ground gaits, stance changes, jumps, stairs, wall and ladder traversal, vaulting and kicking. The capsule, terrain contacts and traversal targets still determine where the character moves. Sprint is archived in the library. Shift selects run in exploration. Race movement uses run automatically.

The selected character uses her UniMate run on level ground when running during exploration or racing. The packer retargets the 24 body rotations onto the full display rig and measures forward travel over the selected source frames. At normal running pace, the pose advances in elapsed seconds at the original 30 fps timing. The capsule uses the measured pace in the display rig’s scale, while the clip retains the pelvis movement within the stride.

In exploration and solo practice on level ground, holding the right mouse button ramps the target speed from the character’s base pace to the shared cap of 5.1 m/s over two seconds. Releasing the button eases back to the base pace in up to 0.75 seconds. The character keeps their authored stride and the controller scales the loop’s playback rate by the ratio of target speed to source pace. Characters with shorter strides take more steps per second to reach the same speed. At the cap, Special Week’s 0.533-second source cycle plays in about 0.411 seconds, or 4.87 steps per second. Stair, turn, collision and traversal rules still determine the achieved pace. In the two-lap meet, the same run gait follows the strategy, phase and character-specific pace. [Race controls and mechanics](running-meet.md#racing-controls)

All 38 local roster runs have a same-foot loop of 16 frame intervals, or 0.533 s at 30 fps. Their level-ground paces range from 3.38 to 4.25 m/s. The batch used Special Week’s run prompt, seed and initial noise, with the joint labels and noise channels matched to each target rig by bone name. Over the selected cycle, Silence Suzuka’s regenerated wrists travel 36 and 28 cm forward and back relative to the hip. Special Week’s approved take measures 35 and 27 cm over its cycle. [Build and verify roster motions](new-character-movement.md#5-install-the-generated-movement-library)

### Special Week’s approved library

Special Week uses the approved trial’s 24 animated body joints. The local gameplay skin adds the original finger and skirt chains. The library contains 24 action clips or windows. Each has one rotation track for each body joint, including the head, toes, and hand attachments, plus the hip translation track. The gameplay controller poses the garment after the body animation and foot contacts. The checkpoint and FLAN-T5 encoder run locally on Apple Metal. [UniMate preprocessing guide](https://github.com/Friedrich-M/UniMate/tree/main/data_process/rig_preprocess) · [Released weights](https://huggingface.co/Linzhan/UniMate)

The gameplay library is rebuilt from fresh inference on the trial skeleton for every selected take. Walk, run, and vertical wall climbing replay the approved trial prompts and seeds. Standing uses the relaxed arms take. The ordinary jump and landing use two windows from the same regenerated two-footed jump. Game gravity and collision govern the capsule in flight. Handholds, ladder rungs, and stair treads determine contact targets.

Each looping selection records two corresponding source frames in `locomotion/picks.json`. Their time difference is one cycle. Ground paces come from the travel measured over that interval.

| Gait | Source frames at 30 fps | Cycle | Steady pace |
| --- | --- | --- | --- |
| Walk | 3–44 | 41 frames · 1.367 s | 0.85 m/s |
| Jog | 1–31 | 30 frames · 1.000 s | 1.57 m/s |
| Run | 23–39 | 16 frames · 0.533 s | 3.93 m/s |
| Sprint (archived take) | 20–39 | 19 frames · 0.633 s | 4.58 m/s |

Special Week’s ordinary run clip has a measured 3.93 m/s base pace in exploration and timed laps. The archived sprint comes from the `sprint-long-strides` prompt in `sprint-straightaway`. The prompt reads “An object sprints at top speed on a flat track with long, rapid alternating strides.” The selected cycle covers 2.90 m of forward travel at its generated cadence. On the campus straight, the median torso lean is about 19° for sprint and 13° for run.

The trial video and local weights live under `design/unimate/`. The sampler checks the original rig’s joint order, hierarchy, and rest pose before running. The replay keeps the original prompt order, seeds, and batch sizes, so the selected takes use the same inputs and frame windows. Unused batches of prompts consume their original noise draws without running the solver. The gameplay baker reads the specified replay directory and checks the raw sample hashes. The Godot packer requires fresh replay provenance, checks the baked clip hashes, and records the generation metadata in `art/special-week/motions.json`. Godot loads that library from `art/special-week/`. For fresh candidates on a prepared character rig, use the [movement batch in the new-character guide](new-character-movement.md#4-generate-the-movement-candidates-with-unimate).

```sh
replay_dir="$(mktemp -d "$PWD/design/unimate/locomotion/regenerated.XXXXXX")"
(
  set -e
  cd design/unimate
  for batch in review baseline refined contact gameplay sprint-straightaway relaxed jump-balance; do
    PYTORCH_ENABLE_MPS_FALLBACK=1 MPLBACKEND=Agg .venv/bin/python locomotion/sample.py \
      "$batch" --replay-selected "$replay_dir"
  done
  MPLBACKEND=Agg .rig-env/bin/python locomotion/bake.py --replay "$replay_dir"
  .rig-env/bin/python locomotion/measure.py --output "$replay_dir/measurements.json" "$replay_dir"/baked/*/*.glb
)
```

```sh
godot --headless --path . --script res://game/tools/build-motions.gd -- \
  "$replay_dir/baked" art/special-week/motions.tres \
  "$replay_dir/measurements.json" design/unimate/locomotion/picks.json
godot --headless --path . --import
```

On first import, Godot may report that it detected the five trial textures as 3D textures. The message records the import settings Godot applied. The generated texture sidecars keep VRAM compression and mipmaps for later imports.

### Building the local finger and skirt rig

The detail builder matches the vertices in the full local Special Week export to the trial export. It restores the original skin weights for 30 finger joints and 30 skirt joints on a separate gameplay copy. Standing uses a relaxed finger curl and turns the palms toward the thighs. At steady ground pace the fingers follow their wrists. The garment cycles use the same phase as their corresponding body clips, including the wrap between the final and first sample. The garment fitter writes offsets only for skirt joints.

Run these commands from the repository root after installing both local GLBs and the motion library. The sampler records actual gameplay poses, at a walk, jog and run. The fitter uses Blender’s triangle intersection queries on the outer panels, pleats and ruffle. The verifier compares the original and fitted skins under the same body poses and reports mean counts of intersecting triangle pairs. The closed underside fan is excluded from that metric. A count is a geometric contact measure and gives no penetration depth.

```sh
pose_dir="$(mktemp -d)"
design/unimate/.rig-env/bin/python design/unimate/locomotion/build_detail_skin.py
godot --headless --path . --import
godot --headless --path . --fixed-fps 60 --script res://game/tools/sample-skirt.gd -- "$pose_dir/base.jsonl"
design/unimate/.rig-env/bin/python design/unimate/locomotion/fit_skirt.py "$pose_dir/base.jsonl"
godot --headless --path . --fixed-fps 60 --script res://game/tools/sample-skirt.gd -- "$pose_dir/rendered.jsonl" --rendered
design/unimate/.rig-env/bin/python design/unimate/locomotion/fit_skirt.py --verify "$pose_dir/rendered.jsonl"
```

The runner automatically selects the detail skin when installed. Some generated poses bring the fingers into the upper leg or shorts, leaving no space for cloth between those surfaces. Residual garment contacts are most frequent during walk and jog. A cloth-only fold tested on the same poses lifted part of the hem by 23 cm at 4% of the walk cycle and 14.5 cm at 22% of the jog cycle.

### Reproducing the original UniMate trial

The review batch uses the original `rig/cond.npy` and `rig/special_week_body.glb`. The sampler checks the canonical skeleton fingerprint, which covers joint order, hierarchy, and rest geometry as well as the 24 body joints. The skirt follows its inherited skin weights. Skirt, hair, and accessory bones have no generated channels.

The batch reproduces two takes each of walk, run, jump, and climb in the original prompt order. It pins checkpoint step 150000, seed 10, guidance scale 3.0, and one case per batch. The regenerated motion arrays and baked review clips matched the originals byte for byte.

```sh
cd design/unimate
PYTORCH_ENABLE_MPS_FALLBACK=1 MPLBACKEND=Agg .venv/bin/python locomotion/sample.py review
MPLBACKEND=Agg .rig-env/bin/python locomotion/bake.py --review
```

Review outputs are under `design/unimate/locomotion/review/`. The regenerated motion arrays go in `reproduced/motions/` and the review GLBs in `reproduced-glb/`. The original preview is `design/unimate/UniMate Special Week trial.mp4`. The six retired source batches and their gameplay bakes were moved to the Trash after the new library was verified.

## Controller and contacts

The runner owns the capsule and input. The `pose/` scripts fit the display rig and sample its clips. The `traversal/` scripts probe walls, ledges and barriers and compute climbing and vault targets. The campus scene connects the runner to the timed lap. The movement suite supplies its own ladder and ball for contact checks. [Code map](project-structure.md) · [Playable scene](../game/campus/campus-walk.tscn)

- `runner-control.gd` selects the requested gait, tracks progress toward the shared running speed cap, brakes into sharp turns, and updates the visual gait from actual speed with hysteresis. The runner interpolates the target ground speed between the base pace and the cap. The authored run advances by scaled elapsed time. Procedural posing advances by ground displacement over the ordinary stride length.
- `runner-clip.gd` samples the selected source frame interval. Most loops blend over two source frames at each end. Idle blends its body rotations and pelvis over up to six frames on either side of the join, using the nearby captured poses. It still repeats frames 8–37 over 29 frame intervals at 30 fps, or 0.967 s. Steady ground travel at the generated pace takes one source period. On stairs, walking advances one full left–right cycle per two measured tread depths. At higher speeds the base stride lengthens, with at least 0.56 seconds per cycle at ordinary running pace. Holding right mouse increases the rate of those strides while the tread spacing still sets their minimum length. Walls and ladders keep their generated pose periods during sustained travel. Jump, double jump, and pull-up use action progress.
- `runner.gd` distinguishes repeated risers from isolated curbs by sampling floor heights along the requested heading. Input still selects the pace on stairs. Grade reduces the requested horizontal speed by up to 22% uphill and 17% downhill. On a measured descent, the downward sweep checks for a tread under the capsule center and under its rear half within the configured floor snap range. A deeper drop enters flight. The model and camera ease across individual treads, and the pose solver limits ankle and toe travel as feet change treads. `track-race.gd` tracks countdown and lap progress on the primary dirt oval.
- `runner-pose.gd` fits world-space hand and foot targets to the floor, trunk, wall plane, ledge edge, stairs, or ladder rungs. During a kick, the generated swing reaches for the ball. The game applies the impulse when the foot is within range during the strike.
- Releasing prone reverses the lowering motion through a squat. The torso straightens with the capsule as overhead clearance permits. During a sharp turn, the lower shoe supplies the initial push-off, its anchor releases as the pelvis rotates, and the other shoe follows the new heading.
- On walls and trunks, contact probes look ahead of both ends of the capsule. A wall-backed projection up to 24 cm deep can move the climber outward and then back toward the supporting face. Capsule sweeps still enforce solid overhangs and unsupported edges. At a ledge, the roster pose can bring the shoulders toward the handhold when the authored pose would put it beyond the rig’s arm reach.
- A jump advances from the source frame marked as takeoff, then blends into its landing window. Brief drops use the landing-ready posture. During flight the driving knee and opposite arm lead a running jump. Both elbows open and the hands spread as vertical speed turns downward. The thumbs rotate with the forearms, and the arms blend back to the landing pose over 0.15 seconds.
- On level ground, Special Week’s steady walk plays the approved body rotations and pelvis motion. The capsule supplies the stride’s net travel while the pelvis keeps its movement within each stride. A bounded horizontal pelvis correction follows the lowest supported shoe during walk and jog. Terrain changes also limit the world-space travel of each ankle to keep a change in ray height from snapping the foot.
- `runner-tail.gd` attaches Special Week’s tail to the posed hip and bends it on a separate three-joint chain. Each joint follows the stride with a little more delay toward the tip. Side-to-side swing grows from walk to jog to run, and eases in or out with the achieved pace. Compatible full rigs use their existing tail joints.
- The Tab picker loads a character’s own movement library with the display rig. It also supports older run-only libraries and procedural posing for rigs without authored motion.

## Verification

Run `godot --headless --path . --fixed-fps 60 --script res://game/tests/runner/check-runner-movement.gd`. It covers ordinary running during a timed lap, the right-mouse ramp and release, stairs, stance clearance, jump buffering, double jump, ladder, wall traversal, pull-up, tree climb, vaults, and ball contact. With the local trial model and motion library installed, it also checks the generation fingerprint, all 24 body tracks, the approved level walk, increasing tail swing across gaits, source periods, loop boundaries, steady gait cadence, and hand alignment at idle, hand height during a walking jump, 180° reversals, walk and jog crossings of an isolated curb, a separate raised window sill, and grounded foot continuity on a ten-riser west academy flight. Running regressions measure sustained speed and both toes on the same stairs, and track elbow motion, wrist alignment and palm rotation during ordinary and double jumps. Append `-- --proxy` to exercise traversal without a local skin. [Campus regression commands](../README.md#run-the-gameplay-checks)

The character-switching check covers the 39 local models and the proxy. The roster check verifies all 24 actions per library, each character’s base gait speeds, and the shared top speed and per-character cadence across several boosted run cycles. It repeats the run with the slowest base pace in a timed lap. The movement suite checks idle playback through three loop boundaries at the source cadence and measures the largest movement between ticks on the display rig. [Roster verification commands](project-structure.md#regression-checks)

## Earlier reference measurements

The local reference files and provenance live under `design/umamu-motion-reference/`. The captures inform cadence, pose and contact. The table records the earlier procedural pass and its motion-capture references.

| Reference | Observation | Earlier setting |
| --- | --- | --- |
| 100STYLE `Neutral_FW` | Selected steady cycles gave a median 1.37 s per stride. The toe was low and nearly stationary for about 52% of a cycle. | Walk at 1.35 m/s, with a 1.04 s stride, 60% stance and a 1.5° forward torso angle. |
| 100STYLE `Neutral_FR` | Selected steady cycles were about 0.80 s per stride, with a 40% low-speed toe interval. | Jog at 3.0 m/s, with a 0.64 s stride, 36% stance and a 9° forward torso angle. |
| LaFAN1 `sprint1_subject2` and `sprint1_subject4` (noncommercial reference), plus the World Athletics women's 100 m report | Faster capture segments gave about 0.53–0.60 s per stride. The report distinguishes ground-contact and flight time at race speed. | Sprint at 6.2 m/s, with a 0.48 s stride, 25% stance and a 30° forward torso angle. |
| ACCAD `Female1_A07_Crouch` and `Female1_C26_RunToCrouch` | Pelvis height dropped by about 30% in the crouch trial. The running transition lowers the body through the knees and hips. | Lower the pelvis by 0.285 m, move it back over the planted feet, and shorten the collision capsule to 1.22 m. |
| ACCAD `Female1_B09_WalkTurnLeft90` and `Female1_B12_WalkTurnRight90` | In the left-turn example the head crossed 35° about 0.10 s before the hips. In the right-turn example the head followed the hips. | Let the head and chest show a modest steering cue. The pelvis follows actual travel, and the foot contacts stay in world space. |
| CMU `13_33`, `14_33`, and `16_01` | The ladder trials show alternating reaches and weight transfers. The jump shows loading, extension, flight and absorption at landing. | Place limbs on the actual rungs. Start the jump with a 75 ms load and use vertical velocity and floor contact for the airborne and landing poses. |

Stride means one full left–right cycle. Gait estimates use native BVH frame times and forward kinematics. Contact was estimated from low height and low world speed of the toe, so it can miss the beginning of heel contact and the end of toe-off. Controller speeds and stance windows are gameplay settings chosen with those observations. [100STYLE](https://www.ianxmason.com/100style/) · [ACCAD](https://accad.ohio-state.edu/research/motion-lab/mocap-system-and-data) · [CMU](https://mocap.cs.cmu.edu/) · [LaFAN1](https://github.com/ubisoft/ubisoft-laforge-animation-dataset) · [World Athletics](https://worldathletics.org/about-iaaf/documents/research-centre)
