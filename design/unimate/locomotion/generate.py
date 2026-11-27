"""Generate, bake and measure UniMate candidates for a prepared character rig."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
from time import perf_counter

from motion_inputs import BODY_JOINTS, REFERENCE_JOINT_LABELS, use_float32_solver, verify_motion
from motion_recipes import recipe_for, reference_noises

LOCOMOTION = Path(__file__).resolve().parent
UNIMATE = LOCOMOTION.parent
UPSTREAM = UNIMATE / "upstream"


def gameplay_prompts():
    """Group the gameplay actions by source take, keeping their reference prompts."""
    picks = json.loads((LOCOMOTION / "picks.json").read_text())
    prompts = json.loads((LOCOMOTION / "prompts.json").read_text())
    review = json.loads((LOCOMOTION / "review-prompts.json").read_text())
    cases = {}
    for action, pick in picks.items():
        source = pick["source"]
        key = (pick["batch"], source)
        if key not in cases:
            label = source.removeprefix("special_week_body-").rsplit("-rep_", 1)[0]
            cases[key] = {
                "id": action,
                "prompt": (review if pick["batch"] == "trial" else prompts)[label],
                "reference_source": source,
                "reference_noise": recipe_for(pick["batch"], source),
                "actions": {},
            }
        cases[key]["actions"][action] = {"reverse": pick.get("reverse", False)}
    return list(cases.values())


def main():
    cases = gameplay_prompts()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rig", type=Path, help="Reviewed rig_preprocess output directory.")
    parser.add_argument("output", type=Path, help="New directory for this batch.")
    parser.add_argument("--device", choices=("auto", "mps", "cpu"), default="auto")
    parser.add_argument("--takes", type=int, default=1, help="Candidates per source prompt.")
    parser.add_argument("--batch-size", type=int, default=1, help="Prompts per solver batch.")
    parser.add_argument("--seed", type=int, default=10)
    reference_mode = parser.add_mutually_exclusive_group()
    reference_mode.add_argument("--reference-motions", action="store_true",
                                help="Match the approved Special Week joint labels and each take's initial noise.")
    reference_mode.add_argument("--reference-run", action="store_true",
                                help="Use the approved Special Week run's single-sample Metal recipe on this rig.")
    parser.add_argument("--motion", action="append",
                        choices=[action for case in cases for action in case["actions"]],
                        help="Limit the run to this action. Repeat to select several.")
    args = parser.parse_args()
    if args.takes < 1:
        parser.error("--takes must be positive")
    if args.batch_size < 1:
        parser.error("--batch-size must be positive")
    reference = args.reference_run or args.reference_motions
    if reference and (args.takes != 1 or args.seed != 10):
        parser.error("Reference generation uses one take per prompt and the recorded seeds")
    if args.reference_run:
        if args.batch_size != 1 or args.device == "cpu":
            parser.error("--reference-run uses solver batch size 1 and Apple Metal")
        if args.motion and args.motion != ["run"]:
            parser.error("--reference-run generates only the run")
        args.device = "mps"
        args.motion = ["run"]
    if args.motion:
        cases = [case for case in cases if set(args.motion) & case["actions"].keys()]
    if not reference:
        for case in cases:
            del case["reference_noise"]
    rig = args.rig.resolve()
    output = args.output.resolve()
    if output.exists():
        parser.error(f"Output must be a new directory: {output}")

    checkpoint = UNIMATE / "model/checkpoints/checkpoint_step_150000.pt"
    model_config = UNIMATE / "model/config.json"
    stats = UNIMATE / "model/dataset_stats.npy"
    blender_python = UNIMATE / ".rig-env/bin/python"
    for path in (checkpoint, model_config, stats, blender_python, rig / "cond.npy"):
        if not path.is_file():
            parser.error(f"Missing required file: {path}")
    if not UPSTREAM.is_dir():
        parser.error(f"Missing local UniMate checkout: {UPSTREAM}")

    started = perf_counter()
    sys.path.insert(0, str(UPSTREAM))
    os.chdir(UPSTREAM)
    os.environ.update(HF_HUB_OFFLINE="1", HF_HUB_CACHE=str(UNIMATE / "hf-cache"),
                      MPLBACKEND="Agg", OMP_NUM_THREADS="6")
    os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")

    import numpy as np
    import torch
    from data_process.utils.asset_files import FRAME_DIGEST_KEY, cond_frame_digest, glb_node_extra
    from unimate.inference import sample as sampler
    from unimate.inference.sample import InferenceArgs

    torch.set_num_threads(6)
    device = args.device if args.device != "auto" else ("mps" if torch.backends.mps.is_available() else "cpu")
    if device == "mps" or reference:
        if not torch.backends.mps.is_available():
            parser.error("Apple Metal is required to draw the original reference noise or run on MPS")
        use_float32_solver()

    cond_path = rig / "cond.npy"
    (asset, condition), = np.load(cond_path, allow_pickle=True).item().items()
    joint_names = condition["joint_names"]
    if len(joint_names) != len(BODY_JOINTS) or set(joint_names) != BODY_JOINTS:
        parser.error("The motion rig must have the 24 body joints in the movement guide")
    canonical_glb = rig / f"{asset}.glb"
    digest = cond_frame_digest(condition)
    if not digest or glb_node_extra(canonical_glb, FRAME_DIGEST_KEY) != digest:
        parser.error(f"Missing or mismatched canonical GLB for {cond_path}: {canonical_glb}")

    config = json.loads(model_config.read_text())
    config["sampling"]["device"] = device
    config["dataset"]["max_joints"] = len(BODY_JOINTS)
    output.mkdir(parents=True)
    config_dir = output / "config"
    config_dir.mkdir()
    (config_dir / "config.json").write_text(json.dumps(config, indent=2) + "\n")
    (config_dir / "dataset_stats.npy").symlink_to(stats)
    reference_joints = list(REFERENCE_JOINT_LABELS)
    matched_labels = [REFERENCE_JOINT_LABELS[name] for name in joint_names]
    sampling_rig = rig
    # Keep the target geometry and bone order. Match text by canonical bone name.
    if list(condition["clean_joint_names"]) != matched_labels:
        sampling_rig = output / "reference-rig"
        sampling_rig.mkdir()
        np.save(sampling_rig / "cond.npy", {asset: {**condition, "clean_joint_names": matched_labels}})
        (sampling_rig / canonical_glb.name).symlink_to(canonical_glb)
        summary = rig / "summary.json"
        if summary.is_file():
            (sampling_rig / summary.name).write_bytes(summary.read_bytes())
    case_file = output / "cases.json"
    case_file.write_text(json.dumps([
        {"asset": str(sampling_rig), "prompt": case["prompt"], "id": case["id"]}
        for case in cases
    ], indent=2) + "\n")

    count = len(cases) * args.takes
    print(f"Generating {count} takes from {len(cases)} prompts on {device}.", flush=True)
    generate_samples = sampler.generate_samples
    if reference:
        from unimate.inference.generate import ClassifierFreeSampleModel

        dataset = config["dataset"]
        sample_shape = (len(BODY_JOINTS), dataset["feature_len"], dataset["max_motion_length"])
        noise_order = [reference_joints.index(name) for name in joint_names]
        noises = reference_noises(cases, sample_shape)
        noises = iter(noises[:, noise_order].split(args.batch_size))

        def generate_with_reference_noise(**kwargs):
            if kwargs["diff_model"] != "flow" or kwargs["x1_known"] is not None:
                raise ValueError("Reference motion requires plain flow inference")
            noise = next(noises).to(kwargs["device"])
            if noise.shape != tuple(kwargs["motion_shape"]):
                raise ValueError(f"Unexpected reference noise shape {noise.shape}")
            guided = ClassifierFreeSampleModel(kwargs["model"], cfg_scale=kwargs["cfg_scale"])
            return kwargs["gen_diffusion"].sample_ode()(noise, guided, cond=kwargs["cond"])[-1]

        sampler.generate_samples = generate_with_reference_noise
    try:
        sampler.main(InferenceArgs(
            exp_dir=str(config_dir), model_path=str(checkpoint), output_dir=str(output),
            test_cases_json=str(case_file), num_repetitions=args.takes, batch_size=args.batch_size,
            seed=args.seed, cfg_scale=3.0, only_save_motion=True,
        ))
    finally:
        sampler.generate_samples = generate_samples
    manifest_path = output / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    manifest["runs"][0]["joint_labels_reference"] = "special_week_body"
    if reference:
        manifest["runs"][0]["noise_joint_names"] = reference_joints
    samples = manifest["samples"]
    for index, case in enumerate(cases):
        slot = index % args.batch_size
        case["samples"] = [f"{asset}-{case['id']}-rep_{take}-{slot}.npy"
                           for take in range(args.takes)]
    expected = {name: case for case in cases for name in case["samples"]}
    if samples.keys() != expected.keys():
        raise ValueError(f"Incomplete inference batch in {output}. Expected {count} takes, found {len(samples)}.")
    for name, case in expected.items():
        sample = samples[name]
        if sample["frame_digest"] != digest or sample["prompt"] != case["prompt"]:
            raise ValueError(f"Unexpected skeleton or prompt in {name}")
        sample["sha256"] = verify_motion(output / "motions" / name)
        if reference:
            sample["reference_noise"] = case["reference_noise"]
            sample["reference_source"] = case["reference_source"]
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    sampled = perf_counter()

    subprocess.run([str(blender_python), str(LOCOMOTION / "bake.py"), "--candidates",
                    str(output), "--rig", str(sampling_rig)], check=True)
    baked = perf_counter()
    subprocess.run([str(blender_python), str(LOCOMOTION / "measure.py"),
                    "--output", str(output / "measurements.json"),
                    *(str(output / "baked" / Path(name).with_suffix(".glb")) for name in expected)],
                   check=True)
    finished = perf_counter()
    timings = {"inference": round(sampled - started, 2), "bake": round(baked - sampled, 2),
               "measurement": round(finished - baked, 2), "total": round(finished - started, 2)}
    report = {
        "device": device, "batch_size": args.batch_size, "frame_digest": digest,
        "takes_per_prompt": args.takes, "cases": cases,
        "timings_seconds": timings,
    }
    if args.reference_run:
        report["reference_run"] = True
    if args.reference_motions:
        report["reference_motions"] = True
    (output / "generation.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Finished {count} takes in {timings['total']:.1f}s. Outputs: {output}", flush=True)


if __name__ == "__main__":
    main()
