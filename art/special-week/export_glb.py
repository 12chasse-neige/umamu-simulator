"""Build the textured Godot character from the supplied FBX and atlases."""

from math import cos, pi, radians, sin, tau
from pathlib import Path
from tempfile import TemporaryDirectory

import bpy
from mathutils import Quaternion, Vector


SOURCE = Path(__file__).resolve().parents[2] / "design/characters/special-week"
TEXTURES = {
    "mtl_bdy1001_00": "tex_bdy1001_00_diff",
    "mtl_chr1001_00_eye": "tex_chr1001_00_eye0",
    "mtl_chr1001_00_face": "tex_chr1001_00_face_diff",
    "mtl_chr1001_00_hair": "tex_chr1001_00_hair_diff",
    "mtl_chr1001_00_mayu": "tex_chr1001_00_face_diff",
    "mtl_tail0001_00": "tex_tail0001_00_1001_diff",
}
X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)
SIDES = ("L", "R")


def bind_textures():
    for material in bpy.data.materials:
        atlas = TEXTURES[material.name.split(".")[0]]
        nodes = material.node_tree.nodes
        shader = nodes.get("Principled BSDF")
        shader.inputs["Base Color"].default_value = (1, 1, 1, 1)
        shader.inputs["Roughness"].default_value = 0.85
        shader.inputs["Metallic"].default_value = 0.0
        shader.inputs["Specular IOR Level"].default_value = 0.0
        texture = nodes.new("ShaderNodeTexImage")
        texture.image = bpy.data.images.load(str(SOURCE / "textures" / f"{atlas}.png"), check_existing=True)
        material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])


def key_rotation(rig, name, frame, *rotations):
    bone = rig.pose.bones[name]
    rest = bone.bone.matrix_local.to_quaternion()
    rotation = Quaternion()
    for axis, angle in rotations:
        rotation = rotation @ Quaternion(axis, radians(angle))
    bone.rotation_mode = "QUATERNION"
    bone.rotation_quaternion = rest.inverted() @ rotation @ rest
    bone.keyframe_insert("rotation_quaternion", frame=frame, group=name)


def key_body(rig, frame, height, lean=0, twist=0, tail_lift=0):
    hip = rig.pose.bones["Hip"]
    hip.location = hip.bone.matrix_local.to_3x3().inverted() @ Vector((0, 0, height))
    hip.keyframe_insert("location", frame=frame, group=hip.name)
    key_rotation(rig, "Chest", frame, (X, lean), (Z, twist))
    key_rotation(rig, "Tail_Ctrl", frame, (X, tail_lift))


def key_limbs(rig, frame, side, thigh, knee, arm, elbow, ankle_correction=0.75):
    sign = 1 if side == "L" else -1
    key_rotation(rig, f"Thigh_{side}", frame, (X, thigh))
    key_rotation(rig, f"Knee_{side}", frame, (X, knee))
    key_rotation(rig, f"Ankle_{side}", frame, (X, -ankle_correction * (thigh + knee)))
    key_rotation(rig, f"Arm_{side}", frame, (X, arm), (Y, sign * 81))
    key_rotation(rig, f"Elbow_{side}", frame, (Z, -sign * elbow))


def idle_pose(rig, frame, progress):
    key_body(rig, frame, 0.005 * (1 - cos(tau * progress)))
    for side in SIDES:
        key_limbs(rig, frame, side, 0, 0, 0, 12)


def leg_reach(thigh, knee):
    # These are the distances between this rig's hip, knee and ankle joints.
    return 0.347 * cos(radians(thigh)) + 0.394 * cos(radians(thigh + knee))


def run_pose(rig, frame, progress, sprint=False):
    phase = tau * progress
    lean, twist = (16, 9) if sprint else (6, 6)
    thigh_swing, knee_flex, arm_swing, elbow = (45, 72, 36, 66) if sprint else (30, 45, 23, 47)
    reach = []
    for index, side in enumerate(SIDES):
        stride = phase + index * pi
        swing = cos(stride)
        thigh = -thigh_swing * swing
        knee = knee_flex * max(0, -sin(stride))
        key_limbs(rig, frame, side, thigh, knee, arm_swing * swing, elbow)
        reach.append(leg_reach(thigh, knee))
    height = -0.015 + 0.022 * cos(2 * phase)
    if sprint:
        height = max(reach) - 0.741 + 0.05 + 0.055 * cos(2 * phase)
    key_body(rig, frame, height, lean, twist * cos(phase), tail_lift=24 if sprint else 6)


def crouch_pose(rig, frame, progress, walking=False):
    phase = tau * progress
    reach = []
    for index, side in enumerate(SIDES):
        swing = cos(phase + index * pi) if walking else 0
        thigh = -72 - 11 * swing
        knee = 123 + 4 * swing
        key_limbs(rig, frame, side, thigh, knee, -43 + 8 * swing, 28, ankle_correction=1)
        # Keep the more extended leg at floor height as the knees alternate.
        reach.append(leg_reach(thigh, knee))
    key_body(rig, frame, max(reach) - 0.741, 23, 3 * cos(phase) if walking else 0, tail_lift=52)


def jump_pose(rig, frame, progress):
    tuck = sin(pi * progress)
    key_body(rig, frame, -0.04 * tuck, 11 * tuck, tail_lift=18 * tuck)
    for index, side in enumerate(SIDES):
        thigh = -6 - (42 - index * 16) * tuck
        knee = 10 + (54 - index * 10) * tuck
        key_limbs(rig, frame, side, thigh, knee, -45 * tuck, 14 + 38 * tuck)


def add_action(rig, name, length, pose, **options):
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data.action = action
    for index in range(length + 1):
        pose(rig, index + 1, index / length, **options)

    rig.animation_data.action = None
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 1, action)
    track.mute = True


def export():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(SOURCE / "source/Special Week Race Special Dreamer.fbx"))
    bind_textures()
    rig = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    rig.animation_data_create()
    bpy.context.scene.render.fps = 30
    add_action(rig, "Idle", 72, idle_pose)
    add_action(rig, "Jog", 17, run_pose)
    add_action(rig, "Sprint", 13, run_pose, sprint=True)
    add_action(rig, "Crouch", 1, crouch_pose)
    add_action(rig, "CrouchWalk", 24, crouch_pose, walking=True)
    add_action(rig, "Jump", 30, jump_pose)

    destination = Path(__file__).resolve().with_name("special-week.glb")
    with TemporaryDirectory(dir=destination.parent) as directory:
        output = Path(directory, destination.name)
        result = bpy.ops.export_scene.gltf(
            filepath=str(output),
            export_format="GLB",
            export_animation_mode="ACTIONS",
            export_anim_slide_to_zero=True,
            export_force_sampling=False,
            export_morph=False,
        )
        if "FINISHED" not in result or not output.is_file():
            raise RuntimeError("Blender did not finish exporting Special Week.")
        output.replace(destination)


if __name__ == "__main__":
    export()
