"""Restore Special Week's skirt and fingers on a gameplay copy of the trial skin."""
import json
from pathlib import Path
import re
import struct

import numpy as np
from scipy.spatial import cKDTree

ART = Path(__file__).resolve().parents[3] / "art/special-week"
DETAIL = re.compile(r"Sp_Hi_MSkirt0_[A-Z]+_0[012]|(?:Thumb|Index|Middle|Ring|Pinky)_0[123]_[LR]")


class Glb:
    """The two local Blender exports have packed accessors and one embedded buffer."""
    def __init__(self, path):
        data = path.read_bytes()
        length = struct.unpack_from("<I", data, 12)[0]
        self.doc = json.loads(data[20:20 + length])
        self.binary = bytearray(data[28 + length:])
        self.skin, = self.doc["skins"]
        self.nodes = self.doc["nodes"]
        self.joints = self.skin["joints"]
        self.names = [self.nodes[i]["name"] for i in self.joints]
        self.body, = (p for p in self.doc["meshes"][0]["primitives"]
                      if self.doc["materials"][p["material"]]["name"] == "mtl_bdy1001_00")

    def read(self, index):
        a = self.doc["accessors"][index]
        v = self.doc["bufferViews"][a["bufferView"]]
        width = {"SCALAR": 1, "VEC3": 3, "VEC4": 4, "MAT4": 16}[a["type"]]
        dtype = {5121: "u1", 5123: "<u2", 5125: "<u4", 5126: "<f4"}[a["componentType"]]
        if "byteStride" in v or "sparse" in a:
            raise ValueError("Expected a packed Blender accessor")
        return np.frombuffer(self.binary, dtype, a["count"] * width,
                             v.get("byteOffset", 0) + a.get("byteOffset", 0)).reshape(-1, width).copy()

    def append(self, values, component, shape):
        blob = values.tobytes()
        self.binary.extend(bytes(-len(self.binary) % 4))
        views = self.doc["bufferViews"]
        views.append(dict(buffer=0, byteOffset=len(self.binary), byteLength=len(blob)))
        self.binary.extend(blob)
        accessors = self.doc["accessors"]
        accessors.append(dict(bufferView=len(views)-1, componentType=component, count=len(values), type=shape))
        return len(accessors)-1

    def write(self, path):
        self.doc["buffers"][0]["byteLength"] = len(self.binary)
        self.binary.extend(bytes(-len(self.binary) % 4))
        meta = json.dumps(self.doc, separators=(",", ":")).encode()
        meta += b" " * (-len(meta) % 4)
        chunks = struct.pack("<I4s", len(meta), b"JSON") + meta
        chunks += struct.pack("<I4s", len(self.binary), b"BIN\0") + self.binary
        tmp = path.with_suffix(".tmp")
        tmp.write_bytes(struct.pack("<4sII", b"glTF", 2, len(chunks)+12) + chunks)
        tmp.replace(path)


def build():
    source = Glb(ART / "special-week.glb")
    trial = Glb(ART / "special-week-trial.glb")
    attrs = trial.body["attributes"]
    original = source.body["attributes"]
    src = source.read(original["POSITION"])
    dst = trial.read(attrs["POSITION"])
    scale = np.mean(np.ptp(dst, axis=0) / np.ptp(src, axis=0))
    offset = dst.min(axis=0) - scale * src.min(axis=0)
    error, match = cKDTree(src).query((dst - offset) / scale)
    if error.max() > 1e-5 or len(trial.joints) != 24:
        raise ValueError("The two exports must share the original Special Week body geometry")

    # Inverse binds describe both exports in mesh coordinates, including the trial's
    # changed root frame. Compose new children relative to their actual trial parent.
    def rest_frames(glb):
        binds = glb.read(glb.skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
        return dict(zip(glb.names, np.linalg.inv(binds)))

    frames = rest_frames(trial)
    source_frames = rest_frames(source)
    parents = {source.nodes[child]["name"]: node["name"] for node in source.nodes
               for child in node.get("children", [])}
    slots = {name: i for i, name in enumerate(trial.names)}
    for name in sorted(filter(DETAIL.fullmatch, source.names)):
        parent = parents[name]
        frame = source_frames[name].copy()
        frame[:3, 3] = frame[:3, 3] * scale + offset
        local = np.linalg.solve(frames[parent], frame)
        trial.nodes[trial.joints[slots[parent]]].setdefault("children", []).append(len(trial.nodes))
        trial.joints.append(len(trial.nodes))
        trial.nodes.append(dict(name=name, matrix=local.T.flatten().tolist()))
        slots[name] = len(slots)
        frames[name] = frame

    # Copy only vertices with a detail influence. All other weights, mesh attributes,
    # body bone transforms and animation inputs stay exactly as in the trial export.
    src_j = source.read(original["JOINTS_0"])[match]
    src_w = source.read(original["WEIGHTS_0"])[match]
    dst_j = trial.read(attrs["JOINTS_0"])
    dst_w = trial.read(attrs["WEIGHTS_0"])
    detail = np.array([bool(DETAIL.fullmatch(name)) for name in source.names])
    rows = np.any(detail[src_j] & (src_w > 0), axis=1)
    remap = []
    for name in source.names:
        while name not in slots and name in parents:
            name = parents[name]
        remap.append(slots.get(name, slots["Hip"]))
    dst_j[rows] = np.array(remap)[src_j[rows]]
    dst_w[rows] = src_w[rows]
    attrs["JOINTS_0"] = trial.append(dst_j.astype("<u2"), 5123, "VEC4")
    attrs["WEIGHTS_0"] = trial.append(dst_w.astype("<f4"), 5126, "VEC4")
    binds = np.linalg.inv(np.array(list(frames.values()))).transpose(0, 2, 1)
    original_binds = trial.read(trial.skin["inverseBindMatrices"])
    binds = binds.reshape(-1, 16).astype("<f4")
    binds[:len(original_binds)] = original_binds
    trial.skin["inverseBindMatrices"] = trial.append(binds, 5126, "MAT4")
    trial.write(ART / "special-week-detail.glb")
    print(f"Restored {len(slots)-24} detail joints on {rows.sum()} of {len(rows)} body-surface vertices")


if __name__ == "__main__":
    build()
