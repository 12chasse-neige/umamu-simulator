"""Prepare a 24-joint UniMate rig from a local roster FBX."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

import bpy

from motion_inputs import BODY_JOINTS

UNIMATE = Path(__file__).resolve().parents[1]


def reduce_body(source, destination):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(source))
    rigs = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    if len(rigs) != 1:
        raise ValueError(f"{source.name} has {len(rigs)} armatures. A single skinned rig is required.")
    rig, = rigs
    rig.animation_data_clear()
    rig.data.pose_position = "REST"
    missing = BODY_JOINTS - set(rig.data.bones.keys())
    if missing:
        raise ValueError(f"{source.name} is missing required joints: {', '.join(sorted(missing))}")
    rest = {name: rig.data.bones[name].matrix_local.copy() for name in BODY_JOINTS}
    retained_parent = {}
    for bone in rig.data.bones:
        name = bone.name
        while bone is not None and bone.name not in BODY_JOINTS:
            bone = bone.parent
        retained_parent[name] = bone.name if bone else "Hip"

    meshes = [obj for obj in bpy.context.scene.objects
              if obj.type == "MESH" and obj.find_armature() == rig]
    if not meshes:
        raise ValueError(f"{source.name} has no meshes skinned to its armature.")
    for mesh in meshes:
        for vertex in mesh.data.vertices:
            weights = {}
            for group in vertex.groups:
                name = mesh.vertex_groups[group.group].name
                if name in retained_parent:
                    parent = retained_parent[name]
                    weights[parent] = weights.get(parent, 0.0) + group.weight
            total = sum(weights.values())
            if total > 0:
                for name, weight in weights.items():
                    group = mesh.vertex_groups.get(name) or mesh.vertex_groups.new(name=name)
                    group.add([vertex.index], weight / total, "REPLACE")
        for group in list(mesh.vertex_groups):
            if group.name not in BODY_JOINTS:
                mesh.vertex_groups.remove(group)

    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    bones = rig.data.edit_bones
    for name in BODY_JOINTS:
        bone = bones[name]
        parent = bone.parent
        while parent is not None and parent.name not in BODY_JOINTS:
            parent = parent.parent
        if bone.parent != parent:
            bone.use_connect = False
            bone.parent = parent
    for bone in list(bones):
        if bone.name not in BODY_JOINTS:
            bones.remove(bone)
    bpy.ops.object.mode_set(mode="OBJECT")
    for name, before in rest.items():
        after = rig.data.bones[name].matrix_local
        if max(abs(a - b) for left, right in zip(before, after) for a, b in zip(left, right)) > 1e-4:
            raise ValueError(f"Rest transform changed while reducing {source.name}: {name}")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [rig, *meshes]:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(destination), export_format="GLB", use_selection=True,
                             export_animations=False, export_morph=False, export_apply=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path, help="New work directory for this rig.")
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    output = args.output.resolve()
    output.mkdir(parents=True)
    reduced = output / "body.glb"
    rig = output / "rig"
    reduce_body(source, reduced)

    command = [
        sys.executable, "-m", "data_process.rig_preprocess", "run",
        "--input", str(reduced), "--output_dir", str(rig), "--exp_dir", str(UNIMATE / "model"),
    ]
    subprocess.run([*command, "--annotate", "rule", "--review",
                    "--face_r", "Thigh_R", "--face_l", "Thigh_L"],
                   cwd=UNIMATE / "upstream", check=True)
    annotation_path = rig / "annotation.json"
    annotation = json.loads(annotation_path.read_text())
    reference = json.loads((UNIMATE / "rig" / "annotation.json").read_text())
    topology = {joint["raw"]: joint["parent"] for joint in annotation["joints"]}
    expected = {joint["raw"]: joint["parent"] for joint in reference["joints"]}
    if (topology != expected or annotation["face_pair"] != reference["face_pair"]
            or any(joint["check"] for joint in annotation["joints"])):
        raise ValueError(f"Review the joint labels and facing pair in {annotation_path}")
    subprocess.run([*command, "--annotation", str(annotation_path)],
                   cwd=UNIMATE / "upstream", check=True)
    if not (rig / "cond.npy").is_file() or not (rig / reduced.name).is_file():
        raise ValueError(f"Preprocessing did not produce a canonical rig in {rig}")


if __name__ == "__main__":
    main()
