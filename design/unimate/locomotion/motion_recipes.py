"""The prompt order, seed and batch shape of the Special Week reference takes."""

BATCHES = {
    "baseline": (1223, "samples", [
        "idle", "walk", "jog", "run", "sprint", "sprint-race", "squat", "prone", "rise",
        "jump", "double-jump", "wall-up", "wall-down", "wall-left", "wall-right", "mantle",
        "stairs-up", "stairs-down", "tree", "vault", "ladder", "turn-left", "turn-right",
    ]),
    "refined": (1288, "samples-refined", [
        "race-dash", "race-fast", "lower-face-down", "prone-crawl",
        "step-up", "step-down", "climb-onto-platform", "climb-pole",
    ]),
    "contact": (3007, "samples-contact", [
        "vault-upright", "vault-step", "air-tuck", "wall-descend",
    ]),
    "review": (10, "review/reproduced", ["walk", "run", "jump", "climb"]),
    "gameplay": (10, "samples-gameplay", [
        "kick-right", "kick-instep", "wall-grip", "jog-steady", "sprint-track",
    ]),
    "sprint": (10, "samples-sprint", ["sprint-fast", "sprint-strides", "sprint-race-pace"]),
    "sprint-straightaway": (10, "samples-sprint-straightaway", [
        "sprint-long-strides", "sprint-straight", "sprint-fast-strides", "sprint-race-straight",
    ]),
    "relaxed": (91, "samples-relaxed", [
        "idle-arms-low", "idle-at-ease", "jump-small-step", "jump-small-hop",
    ]),
    "jump-balance": (10, "samples-jump-balance", [
        "jump-waist", "jump-over-line", "jump-hands-forward",
    ]),
}


def batch_size_for(batch):
    return 2 if batch in ("baseline", "refined", "contact") else 1


def recipe_for(batch, source):
    """Locate a picked take within the original, potentially partial, chunk."""
    batch = "review" if batch == "trial" else batch
    seed, _, labels = BATCHES[batch]
    name, iteration = source.removeprefix("special_week_body-").rsplit("-rep_", 1)
    repetition, slot = map(int, iteration.split("-"))
    size = batch_size_for(batch)
    index = labels.index(name)
    if repetition not in (0, 1) or slot != index % size:
        raise ValueError(f"Invalid reference repetition or slot for {source}")
    return {
        "batch": batch, "seed": seed, "repetition": repetition,
        "chunk_start": index - slot, "batch_size": size, "slot": slot,
    }


def reference_noises(cases, sample_shape):
    """Draw the original Metal chunks and collect the selected slots on CPU."""
    import torch

    selected = {}
    for case in cases:
        recipe = case["reference_noise"]
        key = (recipe["repetition"], recipe["chunk_start"])
        selected.setdefault(recipe["batch"], {}).setdefault(key, []).append(case)

    noises = {}
    for batch, chunks in selected.items():
        seed, _, labels = BATCHES[batch]
        size = batch_size_for(batch)
        generator = torch.Generator(device="mps").manual_seed(seed)
        last_chunk = max(chunks)
        for repetition in range(last_chunk[0] + 1):
            for start in range(0, len(labels), size):
                if (repetition, start) > last_chunk:
                    break
                width = min(size, len(labels) - start)
                noise = torch.randn((width, *sample_shape), device="mps", generator=generator)
                for case in chunks.get((repetition, start), ()):
                    noises[case["id"]] = noise[case["reference_noise"]["slot"]].cpu()
    return torch.stack([noises[case["id"]] for case in cases])
