"""Generate candidate clips on the reviewed Special Week topology."""
import argparse
import json
import os
from pathlib import Path
import sys

import numpy as np
import torch

from motion_inputs import BODY_JOINTS, REFERENCE_JOINT_LABELS, use_float32_solver, verify_motion
from motion_recipes import BATCHES, batch_size_for

output = Path(__file__).resolve().parent
trial = output.parent
launch_dir = Path.cwd()
sys.path.insert(0, str(trial / "upstream"))
os.chdir(trial / "upstream")
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["HF_HUB_CACHE"] = str(trial / "hf-cache")

from data_process.utils.asset_files import cond_frame_digest
from unimate.inference import sample
from unimate.inference.sample import InferenceArgs

# MPS requires a single precision adaptive time grid.
use_float32_solver()
torch.set_num_threads(6)
run = output / "config"
run.mkdir(exist_ok=True)
for name in ("checkpoints", "dataset_stats.npy"):
    link = run / name
    if not link.exists():
        link.symlink_to(trial / "model" / name)
config = json.loads((trial / "model" / "config.json").read_text())
config["sampling"]["device"] = "mps"
rig = trial / "rig"
conditioning, = np.load(rig / "cond.npy", allow_pickle=True).item().values()
joint_names = list(conditioning["joint_names"])
if (joint_names != list(REFERENCE_JOINT_LABELS)
        or list(conditioning["clean_joint_names"]) != list(REFERENCE_JOINT_LABELS.values())):
    raise ValueError("The conditioning data must match the approved trial's body joint order and labels.")
config["dataset"]["max_joints"] = len(BODY_JOINTS)
# Check the complete canonical frame for every batch, including gameplay takes.
if cond_frame_digest(conditioning) != "9312a658625511a5bcf0253cf3be0d61140ce5bc":
    raise ValueError("Generation requires the reduced skeleton from the original trial.")
(run / "config.json").write_text(json.dumps(config))
prompts = json.loads((output / "prompts.json").read_text())
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("batch", choices=BATCHES, nargs="?", default="baseline")
mode = parser.add_mutually_exclusive_group()
mode.add_argument("--replay-selected", type=Path,
                  help="Output directory for fresh inference of the gameplay selections.")
mode.add_argument("--candidates-in", type=Path, help="New directory for verified candidate samples.")
arguments = parser.parse_args()
seed, directory, labels = BATCHES[arguments.batch]
is_review = arguments.batch == "review"
batch_size = batch_size_for(arguments.batch)
takes = output / directory
if is_review:
    prompts = json.loads((output / "review-prompts.json").read_text())
selected = set()
if arguments.replay_selected is not None:
    batch = "trial" if is_review else arguments.batch
    picks = json.loads((output / "picks.json").read_text())
    selected = {f'{pick["source"]}.npy' for pick in picks.values() if pick["batch"] == batch}
    if not selected:
        parser.error(f"No gameplay takes are selected from {batch}")
    takes = (launch_dir / arguments.replay_selected).resolve() / batch
    takes.mkdir(parents=True, exist_ok=False)

    chunks = []
    for repetition in range(2):
        for start in range(0, len(labels), batch_size):
            names = {
                f"special_week_body-{label}-rep_{repetition}-{slot}.npy"
                for slot, label in enumerate(labels[start:start + batch_size])
            }
            chunks.append(bool(names & selected))
    keep_chunk = iter(chunks)
    generate = sample.generate_samples
    save_motions = sample.visualize_and_save_motions

    def generate_selected(**kwargs):
        if next(keep_chunk):
            return generate(**kwargs)
        if kwargs["diff_model"] != "flow" or kwargs["x1_known"] is not None:
            raise ValueError("Selection replay requires plain flow inference")
        # Unused chunks still consume their noise draw, preserving the seed
        # and the original batch shape for every take that enters the ODE.
        torch.randn(kwargs["motion_shape"], device=kwargs["device"])
        return None

    def save_selected(**kwargs):
        if kwargs["samples"] is not None:
            save_motions(**kwargs)

    sample.generate_samples = generate_selected
    sample.visualize_and_save_motions = save_selected
elif arguments.candidates_in is not None:
    takes = (launch_dir / arguments.candidates_in).resolve()
    takes.mkdir(parents=True, exist_ok=False)
else:
    takes.mkdir(parents=True, exist_ok=True)
cases = takes / "cases.json"
cases.write_text(json.dumps([
    {"asset": str(rig), "prompt": prompts[label], "id": label}
    for label in labels
], indent=2))
sample.main(InferenceArgs(
    exp_dir=str(run),
    output_dir=str(takes),
    test_cases_json=str(cases),
    num_repetitions=2,
    batch_size=batch_size,
    seed=seed,
    cfg_scale=3.0,
    model_path=str(trial / "model/checkpoints/checkpoint_step_150000.pt"),
    only_save_motion=True,
))

if selected or arguments.candidates_in is not None:
    manifest_path = takes / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    generated = {}
    for name in sorted(selected or manifest["samples"]):
        path = takes / "motions" / name
        entry = manifest["samples"][name]
        if entry["frame_digest"] != cond_frame_digest(conditioning):
            raise ValueError(f"Unexpected skeleton in the sampler output: {path}")
        generated[name] = {**entry, "sha256": verify_motion(path)}
    manifest["samples"] = generated
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    (takes / "captions.json").write_text(json.dumps(
        {name: entry["prompt"] for name, entry in generated.items()}, indent=2) + "\n")
    print(f"Verified {len(generated)} fresh 24-joint samples in {takes}", flush=True)
