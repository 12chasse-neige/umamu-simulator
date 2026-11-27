# Character models

Local, non-committed character assets for the simulator. Everything in this
folder except `tools/`, `CREDITS.md` and this file is gitignored, because the
models are game rips of Cygames' Uma Musume assets and must not be redistributed.

## What is here

`special-week/` is the original hand-placed export the runner uses. The other 39
came from the public Sketchfab collection of the same asset lineage, so they carry
the in-game skeleton, the `mtl_<part><id>_00` material names and the
`tex_<part><id>_<variant>_<map>.png` atlas names:

| Folder | Character | Faces | Bones | Atlas |
| --- | --- | --- | --- | --- |
| `admire-vega/` | Admire Vega | 28,338 | 707 | 1033 |
| `agnes-digital/` | Agnes Digital | 28,364 | 439 | 1019/01 |
| `air-groove/` | Air Groove | 21,983 | 428 | 1018 |
| `calstone-light-o/` | Calstone Light O | 26,617 | 646 | 1120/90 |
| `daiwa-scarlet/` | Daiwa Scarlet | 29,598 | 437 | 1009 |
| `darley-arabian/` | Darley Arabian | 29,672 | 702 | 9040 |
| `el-condor-pasa/` | El Condor Pasa | 22,480 | 436 | 1014 |
| `fenomeno/` | Fenomeno | 30,524 | 702 | 1127 ⚠ |
| `fuji-kiseki/` | Fuji Kiseki | 22,482 | 431 | 1005 |
| `gold-ship/` | Gold Ship | 23,386 | 398 | 1007 |
| `grass-wonder/` | Grass Wonder | 21,630 | 429 | 1011 |
| `happy-meek/` | Happy Meek | 29,349 | 704 | 2001 |
| `hishi-akebono/` | Hishi Akebono | 28,422 | 704 | 1028/01 |
| `hishi-amazon/` | Hishi Amazon | 26,157 | 427 | 1012/01 |
| `kitasan-black/` | Kitasan Black | 91,969 | — ⚠ | — ⚠ |
| `maruzensky/` | Maruzensky | 25,528 | 439 | 1004 |
| `matikane-tanhauser/` | Matikane Tanhauser | 30,826 | 706 | 1062 |
| `mayano-top-gun-halloween/` | Mayano Top Gun (Halloween) | 30,002 | 705 | 1024/40 |
| `meisho-doto/` | Meisho Doto | 29,268 | 708 | 1058 |
| `meisho-doto-halloween/` | Meisho Doto (Halloween) | 30,222 | 708 | 1058/40 |
| `mejiro-mcqueen/` | Mejiro Mc Queen | 24,338 | 419 | 1013 |
| `narita-brian/` | Narita Brian | 28,501 | 438 | 1016 |
| `narita-top-road/` | Narita Top Road | 30,642 | 702 | 1077 |
| `oguri-cap/` | Oguri Cap | 24,794 | 420 | 1006 |
| `rigantona/` | Rigantona | 29,449 | 704 | 2006 |
| `satono-diamond/` | Satono Diamond | 30,823 | 708 | 1067 |
| `seiun-sky/` | Seiun Sky | 23,287 | 439 | 1020 |
| `silence-suzuka/` | Silence Suzuka | 23,477 | 423 | 1002 |
| `speed-symboli/` | Speed Symboli | 30,372 | 706 | 9047 |
| `still-in-love/` | Still in Love | 29,895 | 685 | 1097 |
| `super-creek/` | Super Creek | 30,884 | 691 | 1045 |
| `super-creek-mummy/` | Super Creek (mummy) | 29,985 | 701 | 1045/40 |
| `symboli-rudolf/` | Symboli Rudolf | 23,867 | 437 | 1017 |
| `taiki-shuttle/` | Taiki Shuttle | 29,256 | 394 | 1010 |
| `tamamo-cross/` | Tamamo Cross | 27,405 | 431 | 1021 |
| `tm-opera-o/` | T.M. Opera O | 28,740 | 423 | 1015 |
| `tokai-teio/` | Tokai Teio | 28,281 | 413 | 1003 |
| `twin-turbo/` | Twin Turbo | 28,949 | 702 | 1066 |
| `vodka/` | Vodka | 22,536 | 410 | 1008 |

Attribution lives in `CREDITS.md`, covering 5 uploaders: Alexandra
([ansaldotoys2](https://sketchfab.com/ansaldotoys2), 20 models), photon
([Professor_E12](https://sketchfab.com/Professor_E12), 12), symbol aughhhh
([yabadiba](https://sketchfab.com/yabadiba), 6) and Flying Cat
([FlyingCat25](https://sketchfab.com/FlyingCat25), the unrigged Kitasan Black).
The models are CC-BY, so that file has to travel with anything you publish.

## Layout of each character

```
<slug>/
  meta.json        faces, author, licence, upstream Sketchfab page
  source/*.fbx     the author's original upload, what the Blender pipeline uses
  textures/*.png   the tex_* atlases for that FBX, exactly as special-week/ has them
  gltf/            Sketchfab's glTF conversion, self-contained, for viewers and the web
    <slug>.gltf
    <slug>.bin
    textures/*.png
```

`source/` and `textures/` follow the layout of `special-week/`. The Blender exporter accepts a character slug and writes roster models to `art/characters/<slug>.glb`. Pass `--roster` to export every rigged roster FBX. Once Godot has imported the exports, press **Tab** in the campus to switch characters. [New-character movement guide](../../docs/new-character-movement.md)

## What the export pipeline has to adapt

1. `export_glb.py` reads the four-digit character ID from the body diffuse atlas and uses the variant from each material slot. For a standard `00` outfit, Silence Suzuka resolves to
   `mtl_bdy1002_00` → `tex_bdy1002_00_diff`, `mtl_tail0001_00` →
   `tex_tail0001_00_1002_diff`.
2. The atlas variant is not always `00`: Agnes Digital and Hishi Amazon ship
   `01`, the Halloween costumes and the mummy ship `40`, Calstone Light O `90`.
   The body costume and the character maps can even disagree — Calstone pairs a
   `90` body with `00` face, hair and eye.
3. The tail prefix is `tex_tail0001_00` for most, but `tex_tail0002_00` for Happy
   Meek, Calstone Light O and Narita Brian.
4. Only the glTF conversion has mangled node names — Sketchfab appends a unique
   `_NNNN` suffix, so `Hip` becomes `Hip_05`. The FBX in `source/` keeps the clean
   names, which is why the pipeline should read the FBX and not the glTF.
5. Bone counts run 394–709. Above ~690 the extra bones are costume and accessory
   bones; the core skeleton and every bone the pipeline drives are identical, so
   they are unused weight rather than a different rig.

## Known gaps

- `fenomeno/` is missing the original hair diffuse atlas. The exporter uses
  her converted glTF's `mtl_chr1127_00_hair_baseColor.png`.
- `super-creek/` is missing the original tail diffuse atlas. The exporter uses
  her converted glTF's `mtl_tail0001_00_baseColor.png`.
- `kitasan-black/` is **not** a game rip and not usable by the pipeline: a single
  unrigged mesh named `Stocking` with generic `Material.001`–`Material.015` and no
  texture set. Kept because it is a Kitasan Black model, but it will not animate.
- Haru Urara was in the collection but the uploader delisted it mid-run
  (`{"detail": "Unavailable asset"}`), so it is not here.

## Verified

`tools/verify_models.py` runs every check below; run it under Blender for the
rig half.

- 37 of 39 pass cleanly; the two failures are Fenomeno's missing hair atlas and
  Kitasan Black above, both reported rather than hidden.
- All 38 rigged FBX import into Blender 5.3 headless as a single armature, and
  every bone `export_glb.py` drives is present under its exact name: `Hip`,
  `Chest`, `Neck`, `Head`, `Thigh_L`, `Knee_L`, `Ankle_L`, `Arm_L`, `Elbow_L`,
  `Tail_Ctrl`.
- Every glTF loads with its buffers and image references resolving, and every
  FBX is a real binary FBX.

## Regenerating

The Sketchfab download API requires an account token; anonymous requests get 401.
Create one at <https://sketchfab.com/settings/password> (bottom of the page), then:

```bash
SKETCHFAB_API_TOKEN=... python3 design/characters/tools/fetch_sketchfab.py
```

Pass `--only <slug> ...` to fetch a subset and `--delay <seconds>` to space the
requests out. Existing folders are skipped before the delay, so a re-run only
fills gaps. The script rewrites `CREDITS.md` from the metadata of every folder on
disk, not just the current batch, so a partial run never drops attributions.

Two failure modes the script handles, both learnt the hard way:

- Sketchfab throttles bursts of file downloads, answering 403 or an HTML error
  page with a 200 status. Each archive attempt therefore re-signs its URL and
  checks the magic bytes instead of trusting the status.
- The `/models/<uid>/download` manifest is fetched once and reused for both
  archives. Re-signing per archive trips the burst throttle and the second
  signature comes back 403.
