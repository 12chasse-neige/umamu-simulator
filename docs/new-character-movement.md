# Make a new character playable

Use the existing campus runner for a new rigged character from `design/characters/`. First get the original, fully dressed character walking, jumping and climbing under player input. This gives you a working model against which to judge any later retargeting, generated motion or garment correction.

| What you want | Where to start | What you get |
| --- | --- | --- |
| Play another roster member with the current controls | Steps 1–2 | An entry in the Tab menu, procedural posing, physics and terrain contacts. This path works today for compatible rigs. |
| Give the character the timing and style of an approved UniMate take | Steps 1–3, then 5–7 | A per-character movement library played through the shared controller. |
| Generate the full movement set for the character | Steps 1–4 | Candidate motion arrays, baked clips and measurements on the character's reduced rig. Continue through steps 5–7 to select and integrate the clips. |

## 1. Inspect the source and export the full character

Run the shell commands from the repository root. **Silence Suzuka** is the worked example. Her folder contains `source/1002_Silence Suzuka.fbx`, a body atlas for character 1002, and matching face, eye, hair and tail maps. Use the original FBX for animation work. The separate Sketchfab `gltf/` conversion can add numerical suffixes to joint names that the controller looks up literally. Keep the source, textures, metadata and credits together. Local character binaries belong in the ignored directories. [Roster inventory and source layout](../design/characters/README.md) · [Character credits](../design/characters/CREDITS.md)

```sh
slug=silence-suzuka
blender=/Applications/Blender.app/Contents/MacOS/Blender
godot=/Applications/Godot.app/Contents/MacOS/Godot

"$blender" --background --python-exit-code 1 \
  --python art/special-week/export_glb.py -- "$slug"
"$godot" --headless --path . --import
```

On other installations, set the two executable variables to the installed Blender and Godot commands. Pass the slug explicitly. The exporter defaults to Special Week when called without arguments. A roster export reads one FBX, binds its textures, and writes `art/characters/<slug>.glb`. Godot imports that file as a scene. The Tab menu discovers GLBs directly in `art/characters/`, so put intermediate rigs, baked clips and review meshes elsewhere. [Blender exporter](../art/special-week/export_glb.py) · [Character picker](../game/ui/character-menu.gd)

Use `--roster` in place of the slug to export every local rigged FBX other than the separate Special Week export. The exporter uses the costume variant and tail family named in each material slot, so Calstone Light O can use her `90` body with `00` face maps and a `tail0002` material. When an atlas is unavailable, it can use the matching base-color image from the same model's Sketchfab conversion. Fenomeno's hair and Super Creek's tail use that route. Kitasan Black needs an armature and skin weights before it can appear in the picker. [Exporter material lookup](../art/special-week/export_glb.py) · [Known source gaps](../design/characters/README.md#known-gaps)

## 2. Bind the skeleton and prove the procedural baseline

Open the campus with F5, press **Tab**, choose the character, and press **Enter**. Scroll the list or use the arrow keys to reach the rest of the roster. The check mark identifies the character currently in play. Check the body from the front and side while standing and while jogging away from the camera. The runner attaches the scene under `Facing`, disables embedded animation players, and binds the first `Skeleton3D` it finds. Keep the deforming body armature first if the export contains several skeletons. [Character selection and binding](../game/runner/runner.gd) · [Pose solver](../game/runner/pose/runner-pose.gd)

Use the [character-switching check](../game/tests/runner/check-character-switching.gd) to verify keyboard activation, the Switch button and the pose solver for the local roster. Append `-- 39` to require all 39 local rigged models including Special Week. The check also exercises the runner proxy.

| Inspect in the imported rig | What the controller expects |
| --- | --- |
| Torso names | Procedural binding requires `Hip`, `Waist`, `Chest`, `Neck`, `Head`. The UniMate contract below also includes `Spine`. |
| Limb names | Both `_L` and `_R` versions of `Thigh`, `Knee`, `Ankle`, `Toe`, `Arm`, `Elbow`, `Wrist`, `Hand_Attach`. The solver uses the two limb segments and their endpoint. Check that the left knee and elbow bend on the character’s own left. |
| Rest frame | In the runner’s local frame, up is +Y and the character faces +Z. Check rest pose, uniform scale, armature parent transform, bone roll and inverse binds together. Turn the whole model in a preview and verify the skin follows the skeleton. |
| Size and soles | Measure the vertical head-joint-to-ankle span in the runner frame. The binder rejects a span below 0.001 m and rescales spans outside 0.75–1.75 m toward 1.22 m. It takes boot height from each resting ankle. Check the actual boot soles against the floor. A thick heel or an offset model origin can still produce floating feet. |
| Collision and reach | The campus standing capsule is 1.64 m tall with a 0.28 m radius. Use it for the first pass. Inspect head clearance, knee reach and handholds on a markedly taller or shorter character before deciding whether their collision dimensions need to differ. |

For a procedural baseline, run the movement suite with the **new GLB as its argument** before installing its movement library. Omitting the argument exercises the default character. This check previously measured 2.92 m/s uphill and 3.02 m/s downhill on the academy stairs with Silence Suzuka’s procedural pose. Use the roster motion check in step 5 once the generated library is installed.

```sh
"$godot" --headless --path . --fixed-fps 60 \
  --script res://game/tests/runner/check-runner-movement.gd -- "res://art/characters/$slug.glb"
```

If procedural movement meets the character’s needs, continue with the in-game checks in step 7. The remaining steps explain how to add authored motion and costume-specific detail.

## 3. Choose the body rig that will own the clips

Keep two assets for the character. The **display rig** retains the original mesh, materials, skin weights, fingers, skirt, hair, ears and tail. The **motion rig** contains the body joints needed to describe a stride, reach or recovery. For the Special Week scheme, “23-rig” means **23 parent–child links connecting 24 joints**. The library has 24 rotation tracks plus one hip-position track.

```text
Hip → Waist → Spine → Chest → Neck → Head
Chest → Shoulder_L → Arm_L → Elbow_L → Wrist_L → Hand_Attach_L
Chest → Shoulder_R → Arm_R → Elbow_R → Wrist_R → Hand_Attach_R
Hip → Thigh_L → Knee_L → Ankle_L → Toe_L
Hip → Thigh_R → Knee_R → Ankle_R → Toe_R
```

**To reuse an approved take**, first compare the reduced rigs’ joint names and order, parents, rest orientations, lengths, forward axis and unit scale. On the exact canonical body frame, the existing rotations can drive a compatible skin. For a full FBX or a different rest frame, bring source and target into the same facing and scale, map the 24 body joints, transfer rotation **relative to each joint’s rest pose**, then bake on the target. Preserve the target’s segment lengths. Convert hip displacement into target units and keep intermediate roll/helper joints in their original hierarchy. A useful first bake is one walk cycle. Overlay the source and target at left strike, passing pose, right strike and the loop boundary. Check elbow and knee bend, wrist roll, toe direction and planted-foot drift before baking more actions.

**To generate on the new proportions**, prepare a motion-only copy in Blender. Blender-Uma-Addon can help inspect and separate the skeleton on supported assets. The deliverable from this step is a verified rig, independent of how it was separated.

1. Duplicate the armature **and its mesh data** in a working file. Put it in rest pose, clear animation from the copy, and retain the full display file as the reference.
2. On the copy, keep the 24 joints above. When removing a helper between two retained bones, reparent the child to its nearest retained ancestor and preserve its armature-space rest transform. Preserve the original left/right labels and inspect bone roll in the exported rig.
3. For the simplified preview mesh, transfer influences from removed bones to the appropriate retained parent and normalize each vertex’s weights. For example, finger weights can follow the wrist and a simplified skirt can follow the hip. On the display mesh keep the detailed weights. Restrict generated rotation channels to the body.
4. Export a rest-pose GLB and reimport it into an empty scene. Count the skin joints, inspect the hierarchy, bend one knee, raise one arm, and rotate the hip. The mesh should remain attached and the far arm should stay at rest. Save this GLB separately from the display export. [Sampler joint contract](../design/unimate/locomotion/sample.py) · [Godot track contract](../game/runner/pose/runner-clip.gd)

## 4. Generate the movement candidates with UniMate

The local UniMate workflow runs **inference with a pretrained checkpoint**. A new character needs its own skeleton conditioning if its canonical rest frame changes. The project has separate Python environments for inference (`.venv`) and Blender/preprocessing (`.rig-env`) under `design/unimate/`. The upstream checkout, checkpoint, encoder and environments are local dependencies. A clean checkout can run the procedural route without them. [Existing motion setup](character-movement.md#unimate-animation) · [Sampler implementation](../design/unimate/locomotion/sample.py)

For a roster FBX with the standard hierarchy, the preparation script reduces the mesh, checks the retained rest transforms and joint hierarchy, and creates the canonical rig. It writes to a new work directory. Here is the Silence Suzuka example, run from the repository root:

```sh
unimate_dir="$PWD/design/unimate"
work_dir="$unimate_dir/characters/$slug"
"$unimate_dir/.rig-env/bin/python" "$unimate_dir/locomotion/prepare_body.py" \
  "design/characters/$slug/source/1002_Silence Suzuka.fbx" "$work_dir"
```

Inspect the canonical preview before generating. The preparation tool uses the FBX for the skinned preview mesh. The fully dressed gameplay export still follows step 1. [Roster rig preparation](../design/unimate/locomotion/prepare_body.py)

For a rig that needs manual reduction or annotation, place the reduced export from step 3 at `"$work_dir/body.glb"` and run the review pass:

```sh
unimate_dir="$PWD/design/unimate"
work_dir="$unimate_dir/characters/$slug"
(
  cd "$unimate_dir/upstream" || exit 1
  "$unimate_dir/.rig-env/bin/python" -m data_process.rig_preprocess run \
    --input "$work_dir/body.glb" --output_dir "$work_dir/rig" \
    --exp_dir "$unimate_dir/model" --annotate rule --review \
    --face_r Thigh_R --face_l Thigh_L
)
```

Review the generated annotation. Check the right/left facing pair, hip root, both hands, toes and all labels. After reviewing or correcting `annotation.json`, run the second pass below. The annotation file supplies both the names and the facing pair.

```sh
(
  cd "$unimate_dir/upstream" || exit 1
  "$unimate_dir/.rig-env/bin/python" -m data_process.rig_preprocess run \
    --input "$work_dir/body.glb" --output_dir "$work_dir/rig" \
    --exp_dir "$unimate_dir/model" --annotation "$work_dir/rig/annotation.json"
)
```

Inspect `preview.png`, `summary.json`, `cond.npy` and the canonical GLB in the output directory. The result should face forward, stand on the ground and export 24 joints. Use this canonical GLB and its matching conditioning together throughout generation and baking.

Run the batch from the repository root once the canonical rig passes that check. Choose a new output directory for each run.

```sh
"$unimate_dir/.venv/bin/python" "$unimate_dir/locomotion/generate.py" \
  "$work_dir/rig" "$work_dir/movement-takes" --reference-motions --batch-size 4
```

The batch takes its prompt list from the gameplay selections. There are 22 source prompts for 24 actions. Jump and landing share a take, and down-climbing uses the up-climb in reverse. The set covers standing, walking, jogging, running, the archived sprint, stance changes, jumps, turns, stairs, climbing, vaulting and kicking. Timed laps use the ordinary run. [Reference selections](../design/unimate/locomotion/picks.json)

Use `--reference-motions` for a roster character with the same 24 body joint names. UniMate encodes descriptive joint labels as text as well as encoding the movement prompt. The 38 other roster rigs each had 12 labels that differed from Special Week’s, including `Right Elbow` versus `Right Forearm` and `Right Wrist` versus `Right Hand`. Eighteen listed their joints in a different order. A test on one unchanged Silence Suzuka rig held the prompt, seed and noise fixed. Changing the labels shortened the detected run cycle from 0.97 s to 0.53 s and shifted the jump’s median torso lean from 48° to 32°. The generator applies the recorded labels by bone name and preserves the target skeleton. Reference mode also assigns each selected take’s original noise channels by bone name. [Reference joint names and labels](../design/unimate/locomotion/motion_inputs.py)

Reference mode produces one take per prompt, uses the recorded seeds and noise batch shapes, and requires Apple Metal to draw the original noise. It can solve on Metal or on CPU. Changing the selected actions or solver batch size preserves each take's initial noise. The solver device and batch can affect numerical results. For the exact single-sample Metal run recipe, use `--reference-run` instead. On Special Week’s canonical rig it reproduces the approved raw run array byte for byte. Use the [approved Special Week replay](character-movement.md#unimate-animation) to rebuild her whole gameplay library.

For alternative candidates, omit `--reference-motions`. The sampler defaults to one take per prompt, seed 10, guidance scale 3.0, a solver batch of one and Metal when available. Use `--takes 2` for 44 candidates. In either mode, use `--motion jog` for a quick check, or repeat `--motion` to choose several actions. Use `--device cpu` to run the solver on CPU.

Each array in `motions/` is checked for 60 frames × 24 joints × 12 features and finite values. `manifest.json` records the prompt, checkpoint, target conditioning fingerprint and raw SHA-256. Reference takes record their original seed, repetition and slot. The script checks the fingerprint against the canonical GLB and bakes the candidates with Blender 5. Review the animated files and their hashes in `baked/`. `measurements.json` records the first-pass motion metrics, and `generation.json` maps actions to takes and records elapsed time by stage. [Batch script](../design/unimate/locomotion/generate.py) · [Blender baker](../design/unimate/locomotion/bake.py)

On an Apple M4 Pro using Metal, the earlier full Silence Suzuka batch took **6 min 46 s** from the prepared rig. Inference and validation took 398 s, baking took 6 s, and measurement took 2 s. Budget about **7 minutes** for one take per prompt on a similar setup, or **14 minutes** for two. Rig preparation, clip review and gameplay integration are separate steps.

For the saved roster batch, run its local `resume-roster.py` with the UniMate `.venv/bin/python`. It reads `roster-status.json`, skips finished characters, and archives and restarts any interrupted character set. Use `--verify-only` to check the finished sets without starting inference. Press Ctrl+C to stop the resumed batch and save its progress.

Open the bakes in Blender and review at normal speed and frame by frame. For transitions, compare the start with the outgoing pose and the end with the incoming pose. Choose target-specific playback windows and contact phases in step 5 before retargeting to the display rig. The capsule and gravity continue to determine travel, takeoff and landing in gameplay.

## 5. Install the generated movement library

The complete reference-label batch is indexed by `design/unimate/roster-reference-movements-voil0_mm/roster-status.json`. Export each display GLB first and then run the Godot packer from the project root. The packer checks each raw and baked SHA-256 against the target’s generation manifest and retargets the 24 body rotations and pelvis track into the display rig’s rest axes.

```sh
roster_status="$PWD/design/unimate/roster-reference-movements-voil0_mm/roster-status.json"
godot --headless --path . --script res://game/tools/build-roster-motions.gd -- "$roster_status"
godot --headless --path . --fixed-fps 60 --script res://game/tests/runner/check-roster-runs.gd -- 38 --full
```

The packer writes one `.res` library and a source report for each character under `art/characters/motions/`. To inspect or test a new build before installing it, pass a second argument with a staging directory. Tab loads the matching library by character slug. Special Week uses her approved trial library. The run-only builder remains available for a batch generated with `--reference-run`. [Full library packer](../game/tools/build-roster-motions.gd) · [Isolated run packer](../game/tools/build-roster-runs.gd)

The full pack uses the approved reference windows and contact phases for the matching source picks. The run selects a same-foot cycle on the target bake. For walk, jog and run, the pack measures travel in the display rig’s scale over the selected source interval. At 30 fps, source frames `a` and `b` make a period of `(b − a) / 30` seconds. The ground speed is the travel during that interval divided by the period. The loop blend closes the seam without adding frames. The capsule supplies world travel, and stair and climbing poses still use the actual surfaces and handholds. [Reference picks](../design/unimate/locomotion/picks.json) · [Clip playback](../game/runner/pose/runner-clip.gd)

Review the target’s loops at both contacts and across the seam. Check jump, landing and stance transitions at full speed and frame by frame. Before changing a window, compare hand and toe positions relative to the pelvis at its endpoints and confirm they are moving in the same direction.

## 6. Fit contacts, hands and clothing on the display rig

Tune against the final display mesh, including shoes and costume. Check one source of motion at a time.

| Symptom | Where to look and what to do |
| --- | --- |
| A planted shoe slides or a knee twists in a reversal | Check scale, cycle period, forward speed and the actual supporting toe first. Measure the toe in **world space** while it is low. On a sharp turn, let the supporting foot push off and release its anchor as the pelvis rotates. Test both turn directions. |
| Feet flash at a curb, or a running character slows to a walk on stairs | Check the repeated-riser grade probe, grounded support over the nosing, ankle travel limit and stride distance. A single curb keeps the current gait. On stairs the controller carries approach speed and lengthens the stride at a run. Watch the first descending tread and the last landing, as well as the middle of the flight. |
| She stays folded after prone, or the wrists look bent | Follow the hip, chest and neck through the squat-to-stand recovery. Check the real wrist-to-middle-knuckle direction and palm orientation at idle. During a running jump, the opposite arm follows the driving knee, the elbows open on descent, and the thumbs turn with the forearms. Review a stationary jump and a second jump as well. |
| Hands or boots miss walls, sills, trunks or rungs | Check the actor’s capsule and surface probes, then compare hand and foot reach with **this rig’s** limb lengths. Climb across a shallow window projection and back to the wall, climb a trunk and pull up onto a clear ledge. |
| A skirt crosses a thigh or swinging hand | Freeze the accepted body motion. Inspect the garment’s weighted panel chains and pose the garment after the body and foot contacts. Compare the *same body frames* at the same stride phases before and after fitting. Use the costume’s own vertex groups, body material, panel order and skirt offsets. Review outer pleats and ruffles from several views, including the wrap frame. |
| Hair, ears or tail distort the generated motion | Keep them on the display rig. Use native accessory joints where available. Inspect their bind pose and weights while the hip turns. Give the tail its own follow-through once the body gait passes. |

Special Week’s detail builder relies on matching vertices in two exports of **her own mesh**. Her fitter and sampling tool assume her material, ten skirt panels, three joints per panel, and paths to her installed skin and curves. For a new outfit, identify its garment and body surfaces first, adapt the sampler to load the target, and fit against all three playable gaits. Save the curves under the target’s identity. At a hand–thigh overlap, compare the hem shape as well as the triangle intersection count. A large upward fold can lower the count and visibly deform the costume. [Detail skin builder](../design/unimate/locomotion/build_detail_skin.py) · [Pose sampling](../game/tools/sample-skirt.gd) · [Garment fitting and verification](../design/unimate/locomotion/fit_skirt.py)

## 7. Verify the character through gameplay

1. **Select and reset.** Switch to the target with Tab, move, press R, switch away and back. Confirm the selected mesh animates, the boots meet the floor, and the camera still follows the capsule.
2. **Cross the gait boundaries.** Start from rest, walk with Alt, jog, then run with Shift. On a straight, level path, hold the right mouse button until the character reaches 5.1 m/s. Release it to return to the base run. Start a timed lap with G and repeat after the countdown. Movement should use the run gait without Shift during the lap. Watch several cycles from the front, side and rear. Check both seams and both feet during a 180° reversal.
3. **Use the campus geometry.** Cross a low curb at a walk and jog. Run into the academy or amphitheatre stairs, descend at pace, and step off a real ledge. A stair descent should remain supported, while a genuine drop should enter flight.
4. **Exercise the one-shots and contacts.** Squat, lie prone, release to stand, jump from idle, jump out of a run and jump twice. Grab a wall, a projecting sill, a tree and a ledge. Vault the low barrier. The movement suite supplies a ladder and ball to check rung and kick contact. Inspect the hands and shoes at actual contact.
5. **Keep target-specific evidence.** Save the GLB path, rig fingerprint if applicable, gait windows and speed measurements, the target movement test output, and a short normal-speed capture. If the shared controller changed, rerun the default and proxy movement tests and the campus route checks. The route suite loads the default runner. The explicit GLB argument in step 2 exercises the new character. [Test commands](../README.md#run-the-gameplay-checks) · [Current movement behavior and reference measurements](character-movement.md)
