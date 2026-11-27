"""Fit periodic garment-only offsets to the gameplay skin. Run with the local rig environment."""
import argparse
import json
from pathlib import Path

import bpy  # Registers mathutils in the standalone Blender Python runtime.
from mathutils.bvhtree import BVHTree
import numpy as np
from scipy.ndimage import gaussian_filter1d
from scipy.spatial import cKDTree

from build_detail_skin import ART, Glb

SECTIONS = ["F", "FL", "FLL", "L", "BL", "B", "BR", "R", "FRR", "FR"]
DIRECTIONS = np.array([
    [1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1],
    [1, .7, 0], [-1, .7, 0], [0, .7, 1], [0, .7, -1],
])


def geometry():
    source = Glb(ART / "special-week.glb")
    detail = Glb(ART / "special-week-detail.glb")
    attrs = detail.body["attributes"]
    src = source.body["attributes"]
    vertices = detail.read(attrs["POSITION"])
    triangles = detail.read(detail.body["indices"]).reshape(-1, 3)
    original = source.read(src["POSITION"])
    scale = np.mean(np.ptp(vertices, axis=0) / np.ptp(original, axis=0))
    offset = vertices.min(0) - original.min(0) * scale
    distance, nearest = cKDTree(original).query((vertices-offset)/scale)
    if distance.max() > 1e-5:
        raise ValueError("Garment fitting requires corresponding body geometry")
    skin = detail.read(attrs["JOINTS_0"])
    weights = detail.read(attrs["WEIGHTS_0"])
    src_j = source.read(src["JOINTS_0"])[nearest]
    src_w = source.read(src["WEIGHTS_0"])[nearest]

    def surface(prefixes):
        mask = np.array([name.startswith(prefixes) for name in source.names])
        influence = (mask[src_j] * src_w).sum(axis=1)
        return triangles[influence[triangles].mean(axis=1) > .48]

    cloth = surface(("Sp_Hi_MSkirt",))
    # The underside includes a closed fan spanning both leg openings. It cannot
    # constrain the hanging fabric; fit the pleats, side panels and visible hem.
    radius = np.linalg.norm(vertices[cloth][:, :, [0, 2]], axis=2)
    cloth = cloth[radius.min(axis=1) > .06]
    legs = surface(("Thigh", "Knee", "Ankle"))
    hands = surface(("Elbow", "ArmRoll", "Wrist", "Hand", "Thumb", "Index", "Middle", "Ring", "Pinky"))
    influence = []
    for section in SECTIONS:
        columns = []
        for level in range(3):
            joint = detail.names.index(f"Sp_Hi_MSkirt0_{section}_{level:02d}")
            columns.append(np.where(skin == joint, weights, 0).sum(axis=1))
        influence.append(columns)
    influence = np.array(influence).transpose(2, 0, 1)
    return vertices, skin, weights, detail.names, cloth, legs, hands, influence


def fit_cycle(task):
    gait, samples = task
    vertices, skin, weights, names, cloth, legs, hands, influence = geometry()
    rest = np.column_stack((vertices, np.ones(len(vertices))))
    # Keep both bones of each strip moving together, with extra freedom for the
    # ruffle. Each candidate needs triangle tests only in the strip it affects.
    parts = []
    for section in range(len(SECTIONS)):
        sub = cloth[np.any(influence[cloth, section, :].sum(axis=2) > .0001, axis=1)]
        indices, local = np.unique(sub, return_inverse=True)
        parts.append((indices, local.reshape(-1, 3).tolist()))

    samples.sort(key=lambda sample: sample[0])
    # A floating-point endpoint may land within a fraction of a source frame
    # of the first sample. Store one value at that phase of the cycle.
    samples = [sample for i, sample in enumerate(samples)
               if (sample[0]-samples[i-1][0]) % 1.0 > .001]
    keys = {}
    previous = np.zeros((10, 3, 3))
    # Start on the last few poses so the first fitted pose already has history.
    order = list(range(len(samples)))
    for index in order[-4:] + order + order[::-1]:
        phase, frame = samples[index]
        matrices = np.array([frame[name] for name in names]).reshape(-1, 3, 4)
        posed = np.einsum("vijk,vk,vi->vj", matrices[skin], rest, weights)
        targets = [BVHTree.FromPolygons(posed.tolist(), group.tolist(), all_triangles=True)
                   for group in (legs, hands)]
        refining = len(keys) == len(samples)
        if refining:
            previous = (keys[(index-1) % len(samples)] + keys[(index+1) % len(samples)]) / 2
            offsets = keys[index].copy()
        else:
            offsets = previous * .78
        points = posed + np.einsum("vij,ijk->vk", influence, offsets)
        for step, ratios in [
                (.045, [0., .65, 1.]), (.036, [1., .3, 0.]), (.028, [0., .65, 1.]),
                (.022, [1., 1., .25]), (.018, [0., .1, 1.]), (.013, [1., 0., 0.]),
                (.010, [0., 1., .2]), (.006, [.5, .65, 1.])]:
            ratios = np.array(ratios)
            for section, (indices, faces) in enumerate(parts):
                start = points[indices]
                strength = influence[indices, section] @ ratios
                current = offsets[section]

                def score(displacement):
                    change = ratios[:, None] * displacement
                    candidate = current + change
                    if np.linalg.norm(candidate[0]) > .062 or np.max(np.linalg.norm(candidate, axis=1)) > .155:
                        return np.inf
                    tree = BVHTree.FromPolygons((start + strength[:, None]*displacement).tolist(),
                                                faces, all_triangles=True)
                    leg_hits, hand_hits = (len(tree.overlap(body)) for body in targets)
                    hits = leg_hits + 1.3 * hand_hits
                    # Smooth neighboring panels and resist discontinuities across frames.
                    neighbor = (offsets[section-1] + offsets[(section+1) % len(parts)]) * .5
                    return (hits + 220*np.sum(candidate**2) + 450*np.sum((candidate-neighbor)**2)
                            + (2500 if refining else 900)*np.sum((candidate-previous[section])**2))

                best = np.zeros(3)
                cost = score(best)
                for direction in DIRECTIONS:
                    move = direction * step
                    value = score(move)
                    if value < cost:
                        best, cost = move, value
                offsets[section] += ratios[:, None] * best
                points[indices] += strength[:, None] * best
        previous = offsets
        keys[index] = offsets
    # A circular filter removes one-frame dents. Interpolation spans the exact
    # source interval including the last-to-first segment.
    curve = gaussian_filter1d(np.array([keys[i] for i in order]), .88, axis=0, mode="wrap")
    # Bound high-frequency dents, including around phase zero, symmetrically
    # in time. This preserves the duration of the body cycle.
    for _ in range(12):
        difference = np.roll(curve, -1, axis=0) - curve
        length = np.linalg.norm(difference, axis=-1, keepdims=True)
        excess = difference * np.maximum(0., 1.-.029/np.maximum(1.e-9, length))
        curve += .45*(excess - np.roll(excess, 1, axis=0))
    return gait, [[phase, offsets.round(5).reshape(-1, 3).tolist()]
                  for (phase, _), offsets in zip(samples, curve)]


def check_rendered(gaits):
    """Compare triangle-pair overlaps for the same measured body poses and geometry."""
    vertices, joints, weights, names, cloth, legs, hands, _ = geometry()
    rest = np.column_stack((vertices, np.ones(len(vertices))))
    trial = Glb(ART / "special-week-trial.glb")
    attrs = trial.body["attributes"]
    skins = [("trial", trial.names, trial.read(attrs["JOINTS_0"]), trial.read(attrs["WEIGHTS_0"])),
             ("fitted", names, joints, weights)]
    for gait, samples in gaits.items():
        for label, bones, binds, influence in skins:
            counts = []
            for _, frame in samples:
                matrices = np.array([frame[name] for name in bones]).reshape(-1, 3, 4)
                posed = np.einsum("vijk,vk,vi->vj", matrices[binds], rest, influence).tolist()
                garment = BVHTree.FromPolygons(posed, cloth.tolist(), all_triangles=True)
                counts.append([len(garment.overlap(BVHTree.FromPolygons(posed, limb.tolist(), all_triangles=True)))
                               for limb in (legs, hands)])
            leg_hits, hand_hits = np.mean(counts, axis=0)
            print(f"{gait:6} {label:6} {len(samples):3} frames, mean intersecting triangle pairs "
                  f"{leg_hits:6.1f} leg / {hand_hits:6.1f} arm and hand")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pose_samples", type=Path)
    parser.add_argument("--verify", action="store_true", help="Measure a --rendered capture instead of fitting")
    args = parser.parse_args()
    gaits = {name: [] for name in ("walk", "jog", "run")}
    for row in args.pose_samples.read_text().splitlines():
        gait, phase, frame = json.loads(row)
        if gait == "sprint" and gait not in gaits:
            gaits[gait] = []  # Older reference captures also contain the sprint take.
        gaits[gait].append((phase, frame))
    for gait, samples in gaits.items():
        phases = np.sort([phase for phase, _ in samples])
        if len(phases) < 24 or np.diff(np.r_[phases, phases[0]+1]).max() > .05:
            raise ValueError(f"Incomplete source cycle for {gait}")
    if args.verify:
        check_rendered(gaits)
        return
    curves = dict(map(fit_cycle, gaits.items()))
    target = ART / "skirt-cycles.json"
    temporary = target.with_suffix(".tmp")
    temporary.write_text(json.dumps(dict(sections=SECTIONS, curves=curves), separators=(",", ":")))
    temporary.replace(target)
    print("Fitted skirt samples:", {name: len(curve) for name, curve in curves.items()})


if __name__ == "__main__":
    main()
