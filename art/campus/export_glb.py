"""Export the campus, review cameras and fountain loop from background Blender."""

import base64
import json
import os
import struct
import zlib
from collections import defaultdict
from math import floor
from pathlib import Path
from tempfile import TemporaryDirectory

import bpy


def prepare_grass(scene):
    """Export planting surfaces in 12 m tiles and reuse the same blade meshes in Godot."""
    tiles = defaultdict(bytearray)
    masks = []
    for obj in scene.objects:
        scale = obj.get("Grass export scale")
        if scale is None:
            continue
        masks.append(obj)
        mesh = obj.data
        points = [obj.matrix_world @ v.co for v in mesh.vertices]
        density = mesh.attributes["Clump density"].data
        blade_height = mesh.attributes["Blade height"].data
        for polygon in mesh.polygons:
            rate = density[polygon.index].value * scale
            if rate <= 0.0:
                continue
            a, b, c, d = [points[i] for i in polygon.vertices]
            x = floor((a.x + c.x) / 24.0)
            y = floor(-(a.y + c.y) / 24.0)
            tiles[f"{x},{y}"].extend(struct.pack(
                "<10f", a.x, a.y, b.x - a.x, d.y - a.y,
                a.z, b.z, c.z, d.z, rate, blade_height[polygon.index].value,
            ))
    for mask in masks:
        bpy.data.objects.remove(mask, do_unlink=True)

    # Use the garden clumps for the entire site, with fewer blades in the
    # distance. Placing the prototypes below the base keeps the GLB view clean.
    originals = bpy.data.collections["Turf · compact game clumps"]
    for index, original in enumerate(sorted(originals.objects, key=lambda obj: obj.name)):
        original_mesh = original.data
        uv = original_mesh.uv_layers.active
        vertex_uvs = {loop.vertex_index: uv.data[loop.index].uv[:] for loop in original_mesh.loops}
        for lod, blade_count in (("near", 6), ("far", 3)):
            vertices, faces, uvs = [], [], []
            for blade in range(blade_count):
                start = len(vertices)
                for i in range(blade * 7, (blade + 1) * 7):
                    vertices.append(original_mesh.vertices[i].co[:])
                    uvs.append(vertex_uvs[i])
                faces.extend((start + a, start + b, start + c) for a, b, c in (
                    (0, 1, 3), (0, 3, 2), (2, 3, 5), (2, 5, 4), (4, 5, 6),
                ))
            name = f"Grass clump {lod} {index + 1}"
            mesh = bpy.data.meshes.new(name)
            mesh.from_pydata(vertices, [], faces)
            mesh.materials.append(original_mesh.materials[0])
            atlas = mesh.uv_layers.new(name="Foliage atlas")
            for face in mesh.polygons:
                face.use_smooth = True
            for loop in mesh.loops:
                atlas.data[loop.index].uv = uvs[loop.vertex_index]
            proxy = bpy.data.objects.new(name, mesh)
            scene.collection.objects.link(proxy)
            proxy.location.z = -15.0

    return {
        "tile_size": 12.0,
        "tiles": {
            key: [len(data), base64.b64encode(zlib.compress(data)).decode("ascii")]
            for key, data in tiles.items()
        },
    }


def prepare_shrubs(scene):
    """Evaluate foliage once per shared garden collection."""
    instances = {}
    for obj in scene.objects:
        source = obj.instance_collection
        if source is not None and source.get("campus_shrub_master"):
            instances.setdefault(source, []).append(obj)

    for source, placements in instances.items():
        baked = bpy.data.collections.new(source.name + " · export")
        baked.instance_offset = source.instance_offset
        for original in source.objects:
            copy = original.copy()
            baked.objects.link(copy)
            if not original.modifiers:
                continue
            scene.collection.objects.link(copy)
            for modifier in copy.modifiers:
                group = modifier.node_group if modifier.type == "NODES" else None
                if group is not None and (socket := group.get("campus_compact_shoots")):
                    getattr(modifier.properties.inputs, socket).value = True
            copy.update_tag()
            depsgraph = bpy.context.evaluated_depsgraph_get()
            evaluated = copy.evaluated_get(depsgraph)
            mesh = bpy.data.meshes.new_from_object(
                evaluated, preserve_all_data_layers=True, depsgraph=depsgraph
            )
            if len(mesh.polygons) == 0:
                raise RuntimeError(f"Foliage evaluated to an empty mesh for {source.name}")
            mesh.name = source.name + " · shoots"
            copy.modifiers.clear()
            copy.data = mesh
            scene.collection.objects.unlink(copy)
        for placement in placements:
            placement.instance_collection = baked


def export_campus():
    source = Path(__file__).resolve().with_name("campus.blend")
    if not bpy.app.background or Path(bpy.data.filepath).resolve() != source:
        raise RuntimeError("Open campus.blend in background Blender to run this exporter.")

    # Bake the editable inscriptions and painted sports lines in this session.
    # The source .blend retains the original fonts and splines.
    scene = bpy.context.scene
    for obj in list(scene.objects):
        if obj.type not in {"FONT", "CURVE"}:
            continue
        evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
        mesh = bpy.data.meshes.new_from_object(evaluated)
        replacement = bpy.data.objects.new(f"{obj.name} · mesh", mesh)
        for collection in obj.users_collection:
            collection.objects.link(replacement)
        replacement.matrix_world = obj.matrix_world.copy()
        bpy.data.objects.remove(obj, do_unlink=True)

    destination = source.with_suffix(".glb")
    # The pour and spray repeat together after 72 frames.
    scene.name = "FountainFlow"
    scene.frame_start = 1
    scene.frame_end = 73
    scene.frame_set(1)
    grass = prepare_grass(scene)
    prepare_shrubs(scene)
    with TemporaryDirectory(dir=destination.parent) as directory:
        output = Path(directory, destination.name)
        result = bpy.ops.export_scene.gltf(
            filepath=str(output),
            export_format="GLB",
            export_cameras=True,
            export_lights=True,
            export_animations=True,
            export_animation_mode="SCENE",
            export_anim_scene_split_object=False,
            export_anim_slide_to_zero=True,
            export_optimize_animation_keep_anim_object=False,
            export_apply=True,
            export_yup=True,
        )
        if "FINISHED" not in result or not output.is_file():
            raise RuntimeError("Blender did not finish exporting the campus.")
        scatter = Path(directory, "grass-scatter.json")
        scatter.write_text(json.dumps(grass, separators=(",", ":")) + "\n")
        os.replace(output, destination)
        os.replace(scatter, destination.with_name(scatter.name))


if __name__ == "__main__":
    export_campus()
