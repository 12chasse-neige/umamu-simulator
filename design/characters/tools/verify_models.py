"""Check every character folder in design/characters/.

Two layers, so the checks run in the environment that can actually answer them:

    python3 design/characters/tools/verify_models.py
        files only - FBX header, atlas convention, glTF buffers and image refs.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python design/characters/tools/verify_models.py
        the same checks, plus a real FBX import: one armature, and every bone
        art/special-week/export_glb.py drives present under its exact name.

Exits non-zero if anything fails, so it can gate a re-run after adding models.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Bones export_glb.py drives by name. A model missing any of these cannot reuse
# the existing animation code.
REQUIRED_BONES = [
    "Hip", "Chest", "Neck", "Head",
    "Thigh_L", "Knee_L", "Ankle_L", "Arm_L", "Elbow_L", "Tail_Ctrl",
]
FBX_MAGIC = b"Kaydara FBX Binary"
# `tex_bdy<id>_<variant>_diff.png`. The variant is not always the "00" default:
# Agnes Digital ships 01, the Halloween costumes 40, Calstone Light O 90. The
# tail atlas is numbered separately (tail0001 or tail0002).
ATLAS_ID = re.compile(r"^tex_bdy(\d{4})_(\d{2})_diff\.png$")


def atlas_report(folder: Path) -> tuple[bool, str]:
    """Derive the atlas id and confirm the set the export map needs."""
    textures = {path.name for path in (folder / "textures").glob("*") if path.is_file()}
    if not textures:
        return False, "no textures/ at all"
    ids = {
        (match.group(1), match.group(2))
        for name in textures
        if (match := ATLAS_ID.match(name))
    }
    if len(ids) != 1:
        return False, f"cannot derive one atlas id from {sorted(textures)[:3]}..."
    atlas, variant = ids.pop()
    # The body costume and the character maps do not have to share a variant:
    # Calstone Light O pairs a 90 costume body with the 00 face and hair.
    def find(pattern: str) -> list[str]:
        return sorted(name for name in textures if re.match(pattern, name))

    required = {
        f"tex_bdy{atlas}_{variant}_diff.png": find(rf"^tex_bdy{atlas}_{variant}_diff\.png$"),
    }
    required[f"tex_chr{atlas}_*_face_diff.png"] = find(rf"^tex_chr{atlas}_\d{{2}}_face_diff\.png$")
    required[f"tex_chr{atlas}_*_hair_diff.png"] = find(rf"^tex_chr{atlas}_\d{{2}}_hair_diff\.png$")
    required[f"tex_chr{atlas}_*_eye*.png"] = find(rf"^tex_chr{atlas}_\d{{2}}_eye")
    missing = [label for label, found in required.items() if not found]
    if missing:
        return False, f"id {atlas}/{variant} missing {missing}"

    # The tail atlas is a soft dependency: a model without it still loads, it
    # just loses the tail material binding, so warn instead of failing.
    tail = [
        name
        for name in textures
        if re.match(rf"tex_tail\d{{4}}_00_{atlas}_diff\.png$", name)
    ]
    note = f"id {atlas}/{variant}, {len(textures)} maps"
    if not tail:
        note += " (WARNING: no tail atlas)"
    return True, note


def filesystem_report(folder: Path) -> tuple[bool, str]:
    parts = []
    ok = True

    source = folder / "source"
    models = sorted(source.glob("*.fbx")) if source.is_dir() else []
    if not models:
        ok = False
        parts.append("no source/*.fbx")
    else:
        head = models[0].read_bytes()[:18]
        if head != FBX_MAGIC:
            ok = False
            parts.append(f"{models[0].name} is not a binary FBX")
        else:
            parts.append(f"{models[0].name} {models[0].stat().st_size // 1024} KB")

    atlas_ok, atlas_note = atlas_report(folder)
    ok &= atlas_ok
    parts.append(atlas_note)

    scene = folder / "gltf" / f"{folder.name}.gltf"
    if scene.is_file():
        try:
            document = json.loads(scene.read_text())
            buffers = document.get("buffers", [])
            failed = [
                buffer["uri"]
                for buffer in buffers
                if buffer.get("uri") and not (scene.parent / buffer["uri"]).is_file()
            ]
            if buffers:
                declared = buffers[0].get("byteLength")
                actual = (scene.parent / buffers[0]["uri"]).stat().st_size
                if declared != actual:
                    failed.append(f"{buffers[0]['uri']} is {actual} bytes, declared {declared}")
            images = [
                image["uri"]
                for image in document.get("images", [])
                if image.get("uri") and not (scene.parent / image["uri"]).is_file()
            ]
            joints = len(document["skins"][0]["joints"]) if document.get("skins") else 0
            if failed or images:
                ok = False
                parts.append(f"gltf broken: {(failed + images)[:2]}")
            else:
                parts.append(f"gltf ok, {joints} joints")
        except json.JSONDecodeError as error:
            ok = False
            parts.append(f"gltf is not JSON: {error}")
    else:
        parts.append("no gltf/")

    return ok, " | ".join(parts)


def rig_report() -> dict[str, tuple[bool, str]]:
    """Import each FBX. Only callable inside Blender, where bpy exists."""
    import bpy  # noqa: PLC0415 - only importable under Blender

    reports = {}
    for folder in sorted(path for path in ROOT.iterdir() if (path / "meta.json").is_file()):
        models = sorted((folder / "source").glob("*.fbx"))
        if not models:
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        try:
            bpy.ops.import_scene.fbx(filepath=str(models[0]))
        except Exception as error:  # noqa: BLE001 - report, do not abort the sweep
            reports[folder.name] = (False, f"import failed: {error}")
            continue
        rigs = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
        if len(rigs) != 1:
            reports[folder.name] = (False, f"{len(rigs)} armatures")
            continue
        bones = {bone.name for bone in rigs[0].data.bones}
        missing = [name for name in REQUIRED_BONES if name not in bones]
        if missing:
            reports[folder.name] = (False, f"missing bones {missing}")
        else:
            reports[folder.name] = (True, f"{len(bones)} bones")
    return reports


def main() -> int:
    folders = sorted(path for path in ROOT.iterdir() if (path / "meta.json").is_file())
    if not folders:
        print("no character folders found", file=sys.stderr)
        return 2

    try:
        import bpy  # noqa: F401, PLC0415 - probe for the Blender runtime
        in_blender = True
    except ImportError:
        in_blender = False

    rigs = rig_report() if in_blender else {}
    failures = []
    print(f"{'character':24} {'files':6} {'rig':6} detail")
    for folder in folders:
        files_ok, files_note = filesystem_report(folder)
        if in_blender:
            rig_ok, rig_note = rigs.get(folder.name, (False, "no FBX"))
        else:
            rig_ok, rig_note = True, "not checked (needs Blender)"
        if not files_ok or not rig_ok:
            failures.append(folder.name)
        print(f"{folder.name:24} {'ok' if files_ok else 'FAIL':6} "
              f"{'ok' if rig_ok else 'FAIL':6} {files_note} | {rig_note}")

    print(f"\n{len(folders) - len(failures)}/{len(folders)} clean")
    if not in_blender:
        print("rig/bone checks skipped - rerun this script under Blender to run them")
    if failures:
        print("failing: " + ", ".join(failures), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
