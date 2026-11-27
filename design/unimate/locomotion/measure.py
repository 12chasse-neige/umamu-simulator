"""Compare raw bakes before selecting gameplay windows. All positions are metres."""
import argparse
import json
from pathlib import Path

import bpy
import numpy as np

trial = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, default=trial / "gameplay-measurements.json")
parser.add_argument("sources", type=Path, nargs="+")
args = parser.parse_args()
report = {}
names = ["Hip", "Neck", "Thigh_L", "Knee_L", "Ankle_L", "Toe_L",
         "Thigh_R", "Knee_R", "Ankle_R", "Toe_R", "Wrist_L", "Wrist_R"]
for source in args.sources:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    rig, = (obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    scene = bpy.context.scene
    action = rig.animation_data.action
    fps = scene.render.fps / scene.render.fps_base
    first = action.frame_range[0]
    frames = []
    for i in range(60):
        time = first + i * fps / 30
        scene.frame_set(int(time), subframe=time % 1)
        frames.append([tuple(rig.matrix_world @ rig.pose.bones[name].head) for name in names])
    joints = np.array(frames)
    hip, neck = joints[:, 0], joints[:, 1]
    root_local = joints - hip[:, None]
    difference = hip[-1] - hip[0]
    lean = np.degrees(np.arctan2(-(neck - hip)[:, 1], (neck - hip)[:, 2]))
    toe = joints[:, [5, 9]]
    lowest_toe = toe[..., 2].min(axis=1)
    toe_speed = np.linalg.norm(np.diff(toe[..., :2], axis=0), axis=-1) * 30
    low = toe[..., 2] < np.percentile(toe[..., 2], 8) + .055
    low_speeds = toe_speed[low[:-1] & low[1:]]
    # Find same-foot cycle endpoints with matching pose and velocity near
    # heel-strike. Penalize linear and side drift to prefer forward steps.
    matches = []
    for start in range(30):
        for end in range(start + 12, min(59, start + 43)):
            travel = -(hip[end, 1] - hip[start, 1])
            if travel < .20:
                continue
            leading = (root_local[start, 8, 1] - root_local[start, 4, 1])
            if leading < .12 or toe[start, 0, 2] > np.min(toe[start:end, 0, 2]) + .08:
                continue
            pose_error = np.mean(np.linalg.norm(root_local[end] - root_local[start], axis=1))
            velocity_error = np.mean(np.linalg.norm((root_local[end+1] - root_local[end]) -
                                                   (root_local[start+1] - root_local[start]), axis=1))
            lateral = abs(hip[end, 0] - hip[start, 0])
            matches.append((pose_error + 3 * velocity_error + lateral * .15, start, end, travel))
    match = min(matches) if matches else None
    item = {
        "ground_speed_mps": float(-difference[1] * 30 / 59),
        "drift_m": float(difference[0]),
        "height_change_m": float(difference[2]),
        "hip_low_m": float(hip[:, 2].min()),
        "hip_high_m": float(hip[:, 2].max()),
        "lean_median_deg": float(np.median(lean)),
        "lean_start_end": [float(lean[0]), float(lean[-1])],
        "toe_slide_mps": float(np.median(low_speeds)) if low_speeds.size else None,
        "low_foot_height_m": float(np.min(lowest_toe)),
        "ankle_swing_m": float(np.ptp(root_local[:, 4, 1])),
        "wrist_range_m": np.ptp(root_local[:, 10], axis=0).tolist(),
        "lowest_frame": int(np.argmin(hip[:, 2])),
        "highest_frame": int(np.argmax(hip[:, 2])),
    }
    if match:
        error, start, end, travel = match
        item.update({"cycle_s": (end - start) / 30, "cycle_speed": travel * 30 / (end - start),
                     "start_s": start / 30, "seam_error_m": float(error)})
    report[f"{source.parent.name}/{source.stem}"] = item
args.output.write_text(json.dumps(report, indent=2) + "\n")
