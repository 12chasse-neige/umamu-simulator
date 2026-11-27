"""Inputs and checks shared by the UniMate locomotion tools."""
from hashlib import sha256

# Exact text and channel order from the approved Special Week conditioning.
REFERENCE_JOINT_LABELS = {
    "Hip": "Hips",
    "Waist": "Spine",
    "Thigh_R": "Right Thigh",
    "Thigh_L": "Left Thigh",
    "Spine": "Spine",
    "Knee_R": "Right Shin",
    "Knee_L": "Left Shin",
    "Chest": "Spine",
    "Ankle_R": "Right Foot",
    "Ankle_L": "Left Foot",
    "Shoulder_R": "Right Shoulder",
    "Shoulder_L": "Left Shoulder",
    "Neck": "Neck",
    "Toe_R": "Right Toe",
    "Toe_L": "Left Toe",
    "Arm_R": "Right Upper Arm",
    "Arm_L": "Left Upper Arm",
    "Head": "Head",
    "Elbow_R": "Right Forearm",
    "Elbow_L": "Left Forearm",
    "Wrist_R": "Right Hand",
    "Wrist_L": "Left Hand",
    "Hand_Attach_R": "Right Hand End",
    "Hand_Attach_L": "Left Hand End",
}
BODY_JOINTS = set(REFERENCE_JOINT_LABELS)


def use_float32_solver():
    import torch
    from unimate.models.flow import integrators

    odeint = integrators.odeint

    def integrate(*args, **kwargs):
        kwargs["options"] = {**kwargs.get("options", {}), "dtype": torch.float32}
        return odeint(*args, **kwargs)

    integrators.odeint = integrate


def verify_motion(path):
    import numpy as np

    frames = np.load(path, allow_pickle=False)
    if frames.shape != (60, len(BODY_JOINTS), 12) or not np.isfinite(frames).all():
        raise ValueError(f"Invalid body-only sample {path}: {frames.shape}")
    return sha256(path.read_bytes()).hexdigest()
