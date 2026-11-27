"""Download the Uma Musume character set from Sketchfab into design/characters/.

Sketchfab serves downloadable models only behind an authenticated API token:
create one at https://sketchfab.com/settings/password ("API Token") and pass it
through the SKETCHFAB_API_TOKEN environment variable.

    SKETCHFAB_API_TOKEN=xxxx python3 design/characters/tools/fetch_sketchfab.py

Every character is fetched in the two shapes Sketchfab offers, because they serve
different purposes:

    source/ + textures/   the author's own upload, unpacked as delivered. This is
                         byte-for-byte the same layout as special-week/: an FBX
                         plus tex_<part><id>_00_<map>.png atlases that
                         art/special-week/export_glb.py already binds by name.
    gltf/                 Sketchfab's own glTF conversion of the same model, kept
                         self-contained so it opens in any viewer without Blender.

Both carry the in-game Cygames skeleton, so the 400+ bone rig matches Special
Week; the glTF conversion appends a unique _NNNN suffix to every node name
(`Hip` becomes `Hip_05`), which a name-strip adapter has to undo.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]
API = "https://api.sketchfab.com/v3"

# Same asset lineage as the current Special Week FBX: in-game model rips of
# 21k-30k faces with the game's 400+ bone rig and tex_* atlases. Ordered so the
# most recognisable cast lands first if a run is interrupted.
CHARACTERS = [
    ("silence-suzuka", "90cded9ec1e641a0a8ce6d9cc3ca7bca", "Silence Suzuka"),
    ("tokai-teio", "c691aadbd14d4735810a01ac406fd940", "Tokai Teio"),
    ("mejiro-mcqueen", "b963bea059a847b48d2e7c329fbce274", "Mejiro Mc Queen"),
    ("symboli-rudolf", "ed52308f5b4f4d3cb4735be0be1d79f1", "Symboli Rudolf"),
    ("oguri-cap", "633921f72d9c42eab0dfdb9bcb876977", "Oguri Cap"),
    ("gold-ship", "d59da1d3d7f8455bba5204bbf173e8cb", "Gold Ship"),
    ("vodka", "dcdc7346b26748f4a470b1f48eff86c7", "Vodka"),
    ("daiwa-scarlet", "6fdd3062fa924b15a4dd0f7493c44617", "Daiwa Scarlet"),
    ("grass-wonder", "04cfb42b98b84bef9b3d4466876d60f1", "Grass Wonder"),
    ("seiun-sky", "f3fa06d1746c4f4ba44d73fc4f55a9b0", "Seiun Sky"),
    ("tm-opera-o", "1f82ad98b84943b6b2076d742ca87dc1", "T.M. Opera O"),
    ("meisho-doto", "902e7dbadc7246c69a54950b29f79aa6", "Meisho Doto"),
    ("admire-vega", "be3325dd0bf040c5944f37d7497eab68", "Admire Vega"),
    ("narita-top-road", "a4a6901d7121444b9b011f32dda4a084", "Narita Top Road"),
    ("tamamo-cross", "6911de2fdce5479c875f2d58dc571df2", "Tamamo Cross"),
    ("air-groove", "abee5dac4d9546a4a85844a97ac89d65", "Air Groove"),
    ("agnes-digital", "51911125c6b441298a44027c2da3d349", "Agnes Digital"),
    ("super-creek", "c604d8cb871a4716987aa2ee07898a6b", "Super Creek"),
    ("super-creek-mummy", "6792ae5e7b8c489f885efa5a24d6651c", "Super Creek (mummy)"),
    ("twin-turbo", "a2faf60d46514e499145f24c406babb8", "Twin Turbo"),
    ("narita-brian", "865d1e9a10c445168f05acde5ccf19c2", "Narita Brian"),
    ("mayano-top-gun-halloween", "0e12d9ebdf8e4c4a8e4ac5740b8da0ca", "Mayano Top Gun (Halloween)"),
    ("meisho-doto-halloween", "758b6b63ebe24920b868e27199a64952", "Meisho Doto (Halloween)"),
    ("fenomeno", "449ce90162844b73b430b3ab7d79dd4f", "Fenomeno"),
    ("hishi-akebono", "5b1cf582694c429e8c64623977537e1f", "Hishi Akebono"),
    ("calstone-light-o", "6fff7c68eabb4041af79f37d50c7da51", "Calstone Light O"),
    ("still-in-love", "6b161151dbf846f99068ef92a16bf8cd", "Still in Love"),
    ("hishi-amazon", "db20f6d19d684937b02e04a4aaff6d9f", "Hishi Amazon"),
    ("el-condor-pasa", "7a58f12c7fec4bb099d209eddf260bc2", "El Condor Pasa"),
    ("maruzensky", "ef47019249e64ee3a754b823ae3da947", "Maruzensky"),
    ("fuji-kiseki", "b1896ff655344901b9a87bd8dd548daa", "Fuji Kiseki"),
    ("taiki-shuttle", "3d346328382948f1b974c690ffcd985c", "Taiki Shuttle"),
    ("happy-meek", "ce07ec53e8c948999fccd7fa3ce71784", "Happy Meek"),
    ("speed-symboli", "2991b549878946ac8467807b7eee9b93", "Speed Symboli"),
    ("rigantona", "717c15b013cc41b28768c5c4dcd0729d", "Rigantona"),
    ("darley-arabian", "c6ad8afab6f74aeaae871aaaa9ba9892", "Darley Arabian"),
    ("matikane-tanhauser", "eff0cf74567f415984c1373f7a6c2707", "Matikane Tanhauser"),
    ("satono-diamond", "8e36f13a48b241a582648fae18f8feec", "Satono Diamond"),
]

MODEL_RANK = {".gltf": 0, ".glb": 0, ".fbx": 1, ".obj": 2, ".usdz": 3, ".blend": 4}
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".tga", ".bmp"}
RETRY_STATUS = {429, 500, 502, 503, 504}


def api_get(path: str, token: str, attempts: int = 5) -> dict:
    request = urllib.request.Request(
        f"{API}{path}",
        headers={"Authorization": f"Token {token}", "User-Agent": "umamu-simulator"},
    )
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code not in RETRY_STATUS or attempt == attempts - 1:
                raise
            wait = 5 * 2**attempt
            print(f"    Sketchfab said {error.code}, retrying in {wait}s", file=sys.stderr)
            time.sleep(wait)
    raise RuntimeError("unreachable")


def download(url: str, destination: Path, attempts: int = 4) -> None:
    for attempt in range(attempts):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "umamu-simulator"})
            with urllib.request.urlopen(request, timeout=300) as response:
                with destination.open("wb") as handle:
                    shutil.copyfileobj(response, handle)
            return
        except urllib.error.HTTPError as error:
            if error.code not in RETRY_STATUS or attempt == attempts - 1:
                raise
            time.sleep(5 * 2**attempt)


def safe_extract(archive: Path, destination: Path) -> None:
    """Extract a zip without letting an entry escape the destination directory."""
    destination = destination.resolve()
    with zipfile.ZipFile(archive) as zipped:
        for member in zipped.infolist():
            resolved = (destination / member.filename).resolve()
            if destination not in resolved.parents and resolved != destination:
                raise RuntimeError(f"unsafe archive entry: {member.filename}")
        zipped.extractall(destination)


ARCHIVE_MAGIC = {"source": b"PK", "gltf": b"PK", "usdz": b"PK", "glb": b"glTF"}


def download_archive(
    uid: str,
    token: str,
    kind: str,
    destination: Path,
    manifest: dict | None = None,
    attempts: int = 3,
) -> bool:
    """Fetch one archive, taking a fresh signed URL on every attempt.

    Sketchfab throttles repeated file downloads: past a burst it answers 403, or
    returns an HTML error page with a 200 status. Both look like a corrupt
    archive downstream, so every attempt re-signs the URL and checks the magic
    bytes instead of trusting the status code.

    """
    magic = ARCHIVE_MAGIC.get(kind, b"PK")
    problem = ""
    for attempt in range(attempts):
        try:
            if manifest is None:
                manifest = api_get(f"/models/{uid}/download", token)
            entry = manifest.get(kind)
            if not entry:
                return False
            download(entry["url"], destination)
            with destination.open("rb") as handle:
                if handle.read(len(magic)) != magic:
                    head = destination.read_bytes()[:80]
                    raise RuntimeError(f"payload is not {kind} (starts {head!r})")
            return True
        except Exception as error:  # noqa: BLE001 - any failure means retry the URL
            problem = str(error)
            # Drop the manifest too: its URLs are what just failed.
            manifest = None
            if attempt < attempts - 1:
                wait = 20 * (attempt + 1)
                print(f"    {kind} archive: {problem}; retrying in {wait}s", file=sys.stderr)
                time.sleep(wait)
    raise RuntimeError(f"{kind} archive unavailable after {attempts} attempts: {problem}")


def extract_nested(target: Path) -> None:
    """Unwrap a zip that an author shipped inside their own source archive.

    El Condor Pasa uploads `source/El cóndor pase.zip` containing the FBX, so a
    single extract leaves a zip where the model should be.
    """
    for archive in sorted((target / "source").glob("*.zip")):
        safe_extract(archive, archive.parent)
        archive.unlink()


def unpack_original(
    target: Path, scratch: Path, uid: str, token: str, manifest: dict | None = None
) -> str:
    """Unpack the author's upload straight into source/ + textures/ like special-week."""
    for kind in ("source", "glb", "gltf"):
        bundle = scratch / f"original-{kind}.zip"
        if not download_archive(uid, token, kind, bundle, manifest):
            continue
        if kind == "glb":
            (target / "source").mkdir(parents=True, exist_ok=True)
            shutil.copy2(bundle, target / "source" / f"{target.name}.glb")
        else:
            safe_extract(bundle, target)
            extract_nested(target)
        models = [p for p in target.rglob("*") if p.suffix.lower() in MODEL_RANK]
        if models:
            names = ", ".join(str(p.relative_to(target)) for p in sorted(models))
            return f"{kind} ({names})"
    raise RuntimeError("no original archive could be unpacked")


def unpack_gltf(
    target: Path, scratch: Path, slug: str, uid: str, token: str, manifest: dict | None = None
) -> str:
    """Unpack Sketchfab's glTF conversion as a self-contained gltf/ folder."""
    bundle = scratch / "gltf.zip"
    if not download_archive(uid, token, "gltf", bundle, manifest):
        return ""
    extracted = scratch / "gltf-unpacked"
    safe_extract(bundle, extracted)

    files = [path for path in sorted(extracted.rglob("*")) if path.is_file()]
    models = [path for path in files if path.suffix.lower() in MODEL_RANK]
    if not models:
        raise RuntimeError("glTF archive contained no model file")
    model = min(models, key=lambda path: (MODEL_RANK[path.suffix.lower()], path.name))

    gltf_dir = target / "gltf"
    textures_dir = gltf_dir / "textures"
    textures_dir.mkdir(parents=True, exist_ok=True)

    images: dict[str, Path] = {}
    for path in files:
        if path.suffix.lower() in IMAGE_SUFFIXES:
            shutil.copy2(path, textures_dir / path.name)
            images[path.name] = textures_dir / path.name

    scene = gltf_dir / f"{slug}{model.suffix.lower()}"
    shutil.copy2(model, scene)
    if scene.suffix != ".gltf":
        return f"glb ({scene.name})"

    document = json.loads(scene.read_text())
    for index, buffer in enumerate(document.get("buffers", [])):
        uri = buffer.get("uri")
        if not uri or uri.startswith("data:"):
            continue
        companion = next((path for path in files if path.name == Path(uri).name), None)
        if companion is None:
            raise RuntimeError(f"glTF buffer {uri!r} missing from the archive")
        name = f"{slug}.bin" if index == 0 else Path(uri).name
        shutil.copy2(companion, gltf_dir / name)
        buffer["uri"] = name
    for image in document.get("images", []):
        uri = image.get("uri")
        if not uri or uri.startswith("data:"):
            continue
        name = Path(uri).name
        if name not in images:
            raise RuntimeError(f"glTF image {uri!r} missing from the archive")
        image["uri"] = f"textures/{name}"
    scene.write_text(json.dumps(document, indent=2))

    unresolved = [
        image["uri"]
        for image in document.get("images", [])
        if "uri" in image and not (gltf_dir / image["uri"]).is_file()
    ]
    if unresolved:
        raise RuntimeError(f"glTF image references do not resolve: {unresolved}")

    joints = len(document["skins"][0]["joints"]) if document.get("skins") else 0
    return f"gltf ({scene.name}, {joints} joints)"


def fetch(slug: str, uid: str, title: str, token: str) -> dict:
    target = ROOT / slug
    if (target / "meta.json").is_file():
        print(f"  {slug}: already present, skipped")
        return json.loads((target / "meta.json").read_text())

    model = api_get(f"/models/{uid}", token)
    # One manifest serves both archives: re-signing per archive trips Sketchfab's
    # burst throttle, and the second signature comes back 403.
    manifest = api_get(f"/models/{uid}/download", token)

    target.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory() as scratch_name:
        scratch = Path(scratch_name)
        original = unpack_original(target, scratch, uid, token, manifest)
        try:
            converted = unpack_gltf(target, scratch, slug, uid, token, manifest)
        except Exception as error:  # noqa: BLE001 - the glTF is a convenience copy
            converted = f"unavailable ({error})"

    author = model.get("user") or {}
    licence = model.get("license") or {}
    textures = sorted(p.name for p in (target / "textures").glob("*") if p.is_file())
    meta = {
        "slug": slug,
        "title": title,
        "sketchfabName": model.get("name"),
        "uid": uid,
        "viewer": f"https://sketchfab.com/3d-models/{uid}",
        "original": original,
        "gltf": converted,
        "textures": textures,
        "faceCount": model.get("faceCount"),
        "vertexCount": model.get("vertexCount"),
        "animationCount": model.get("animationCount"),
        "author": author.get("displayName") or author.get("username"),
        "authorProfile": f"https://sketchfab.com/{author.get('username')}",
        "license": licence.get("label"),
        "licenseUrl": licence.get("url"),
    }
    (target / "meta.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False) + "\n")
    print(f"  {slug}: {meta['faceCount']} faces | {original} | {converted}")
    return meta


def write_credits() -> None:
    """Rebuild CREDITS.md from every meta.json on disk, not just this run's batch."""
    order = {slug: index for index, (slug, _, _) in enumerate(CHARACTERS)}
    metas = sorted(
        (json.loads(path.read_text()) for path in ROOT.glob("*/meta.json")),
        key=lambda meta: (order.get(meta["slug"], len(order)), meta["slug"]),
    )
    header = [
        "# Character model credits",
        "",
        "CC-BY requires attribution to travel with the asset, so keep this file",
        "next to the models. Regenerate the whole set with",
        "`SKETCHFAB_API_TOKEN=... python3 design/characters/tools/fetch_sketchfab.py`.",
        "",
        "| Character | Folder | Author | License | Source |",
        "| --- | --- | --- | --- | --- |",
        "| Special Week | `special-week/` | local FBX export | game rip, reference only | "
        "`Special Week Race Special Dreamer.fbx` |",
    ]
    rows = [
        f"| {meta['title']} | `{meta['slug']}/` | "
        f"[{meta['author']}]({meta['authorProfile']}) | "
        f"[{meta['license']}]({meta['licenseUrl']}) | "
        f"[Sketchfab]({meta['viewer']}) |"
        for meta in metas
    ]
    (ROOT / "CREDITS.md").write_text("\n".join(header + rows) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--token", default=os.environ.get("SKETCHFAB_API_TOKEN"))
    parser.add_argument("--only", nargs="*", help="restrict to these slugs")
    parser.add_argument("--delay", type=float, default=8.0,
                        help="seconds between characters, Sketchfab rate-limits bursts")
    args = parser.parse_args()

    token = (args.token or "").strip()
    if not token:
        print("error: no Sketchfab API token. Set SKETCHFAB_API_TOKEN or pass --token.\n"
              "Create one at https://sketchfab.com/settings/password", file=sys.stderr)
        return 2

    wanted = set(args.only or ())
    results, failures = [], []
    attempted = 0
    for slug, uid, title in CHARACTERS:
        if wanted and slug not in wanted:
            continue
        # Skip finished folders before the delay, so a re-run does not sleep
        # through the whole catalogue just to rediscover what is already there.
        if (ROOT / slug / "meta.json").is_file():
            print(f"  {slug}: already present, skipped")
            continue
        # Space the requests out even for a --only subset: the API rate-limits bursts.
        if attempted:
            time.sleep(args.delay)
        attempted += 1
        try:
            results.append(fetch(slug, uid, title, token))
        except Exception as error:  # noqa: BLE001 - report and keep the batch going
            print(f"  {slug}: failed - {error}", file=sys.stderr)
            failures.append((slug, str(error)))

    if results:
        write_credits()
    print(f"\n{len(results)}/{len(CHARACTERS)} characters ready under {ROOT}")
    if failures:
        print("failed: " + ", ".join(slug for slug, _ in failures), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
