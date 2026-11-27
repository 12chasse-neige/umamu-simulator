"""Bake local UniMate features to gameplay or body-only review GLBs."""
import argparse
from hashlib import sha256
import json
from pathlib import Path
from shutil import copyfile
import sys

import numpy as np

from motion_inputs import BODY_JOINTS, verify_motion

root = Path(__file__).resolve().parent
trial = root.parent
sys.path.insert(0, str(trial / "upstream"))

from data_process.mesh_animation.animate_motion import animate_character
from data_process.mesh_animation import common as animation
from data_process.utils import blender_rig
from data_process.utils.asset_files import FRAME_DIGEST_KEY, cond_frame_digest, glb_node_extra


def bind_layered_action(armature, action):
    slot = action.slots.new("OBJECT", armature.name)
    armature.animation_data_create()
    armature.animation_data.action = action
    armature.animation_data.action_slot = slot
    action.layers.new("Motion").strips.new(type="KEYFRAME").channelbag(slot, ensure=True)


def add_layered_curves(action, bone_name, attribute, components, keyframes):
    strip = action.layers[0].strips[0]
    channelbag = strip.channelbag(action.slots[0])
    path = f'pose.bones["{bone_name}"].{attribute}'
    for component in range(components):
        curve = channelbag.fcurves.new(data_path=path, index=component)
        curve.keyframe_points.add(len(keyframes))
        for point, (frame, value) in zip(curve.keyframe_points, keyframes):
            point.co = frame, value[component]
            point.interpolation = "LINEAR"
        curve.update()


blender_rig.bind_action = bind_layered_action
blender_rig._add_fcurves = add_layered_curves
export_original = blender_rig.export_animated_character
animation.export_animated_character = lambda path, formats: export_original(path, formats=("glb",))

parser = argparse.ArgumentParser(description=__doc__)
mode = parser.add_mutually_exclusive_group(required=True)
mode.add_argument("--review", action="store_true", help="Bake the new samples on the trial rig.")
mode.add_argument("--replay", type=Path, help="Use only freshly regenerated samples from this directory.")
mode.add_argument("--candidates", type=Path, help="Bake the verified manifest from generate.py.")
parser.add_argument("--rig", type=Path, help="Prepared rig for --candidates.")
parser.add_argument("--picks", type=Path, default=root / "picks.json",
                    help="Select verified takes to bake from the replay directory.")
args = parser.parse_args()
if (args.rig is None) != (args.candidates is None):
    parser.error("--rig and --candidates must be used together")
rig = args.rig if args.candidates else trial / "rig"
condition = rig / "cond.npy"
(asset, conditioning), = np.load(condition, allow_pickle=True).item().items()
model = rig / f"{asset}.glb"
frame_digest = cond_frame_digest(conditioning)
if args.candidates:
    if not frame_digest or glb_node_extra(model, FRAME_DIGEST_KEY) != frame_digest:
        raise ValueError(f"{model} does not match {condition}.")
    output = args.candidates / "baked"
    sources = {"candidates": args.candidates}
    filenames = json.loads((args.candidates / "manifest.json").read_text())["samples"]
    selections = {("candidates", name) for name in filenames}
elif args.review:
    review = root / "review"
    output = review / "reproduced-glb"
    sources = {"review": review / "reproduced"}
    filenames = json.loads((sources["review"] / "manifest.json").read_text())["samples"]
    selections = {("review", name) for name in filenames}
else:
    picks = json.loads(args.picks.read_text())
    selections = {(pick["batch"], f'{pick["source"]}.npy') for pick in picks.values()}
    sources = {batch: args.replay / batch for batch, _ in selections}
    output = args.replay / "baked"

manifests = {}
provenance = {}
for batch, name in sorted(selections):
    source = sources[batch]
    if batch not in manifests:
        manifests[batch] = json.loads((source / "manifest.json").read_text())
    manifest = manifests[batch]
    sample = manifest["samples"][name]
    if sample["frame_digest"] != frame_digest:
        raise ValueError(f"{batch}/{name} was generated on a different skeleton.")
    clip = source / "motions" / name
    digest = verify_motion(clip)
    if not args.review and digest != sample.get("sha256"):
        raise ValueError(f"{clip} does not match its fresh inference manifest.")
    reference_noise = sample.get("reference_noise")
    provenance[f"{batch}/{clip.stem}"] = {
        "frame_digest": frame_digest,
        "joint_count": len(BODY_JOINTS),
        "motion_sha256": digest,
        "seed": reference_noise["seed"] if reference_noise else manifest["runs"][sample["run"]]["seed"],
        "regenerated": not args.review,
    }

for batch, name in sorted(selections):
    destination = output / batch if args.replay else output
    clip = sources[batch] / "motions" / name
    animate_character(str(model), str(clip), str(condition), str(destination),
                      "general", extra_bones_strategy="keep")
    if not args.review:
        baked = destination / f"{clip.stem}.glb"
        provenance[f"{batch}/{clip.stem}"]["baked_sha256"] = sha256(baked.read_bytes()).hexdigest()

if not args.review:
    (output / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
if args.replay:
    game_mesh = trial.parents[1] / "art" / "special-week" / "special-week-trial.glb"
    if not game_mesh.exists() or game_mesh.read_bytes() != model.read_bytes():
        copyfile(model, game_mesh)
