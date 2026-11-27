# Tracen Academy campus

## Open the current model

Open [campus.blend](campus.blend) in Blender. Keep [kit.blend](kit.blend) beside it so the linked materials and reusable models load. Both Blender files contain their image dependencies.

Press **Z** and choose **Material Preview** to see through the windows while navigating. Choose **Rendered** for Cycles lighting and refraction. Play frames 1–73 to see the fountain loop. The file opens at the gate. The Outliner has 12 cameras in `Interior review cameras`. Select one and choose **View → Cameras → Set Active Object as Camera** to jump into a room.

In a Godot project, place the asset folder at `res://art/campus` and run the daylight preview scene. It applies the clear glazing and moving water materials and instances the grass from [grass-scatter.json](grass-scatter.json). The GLB carries the furnishings, all 18 review cameras, transmission parameters and the three-second `FountainFlow` clip. [Godot preview scene](campus-preview.tscn) · [Full-campus GLB](campus.glb)

## Furnished interiors

The rooms use the campus palette of cream plaster, oak joinery, dark teal enamel and brushed brass. Navy, sage and rust fabrics distinguish the residence rooms. Repeated furnishings share editable mesh data. The additional galleries, seminar rooms, faculty offices, workshops and training rooms are in the `Furnished campus rooms and circulation` collection. Each interior spotlight is mounted at a visible pendant or table lamp.

[Interior preview gallery](../../design/tracen-academy/previews/indoor-rooms.jpg) · [Campus guide](../../design/tracen-academy/campus-guide.png)

| Campus guide | Furnishings | Blender cameras |
|---|---|---|
| 1 · Main gate | Campus office with directory, visitor seating and a reception desk | I10 |
| 3 · Academy | Classroom desks and chalkboards, upper-level seminar rooms, an honors gallery and a library with reading lamps | I01–I04 |
| 4 · Stump garden | Garden lodges with a potting bench, tools and tea service, plus a reading nook by the upper path | I11 |
| 5 · Sports hall | Marked timber court, volleyball net, equipment racks, café and bakery, and a conditioning gym with lockers | I05–I07 |
| 6 · Amphitheatre | Rehearsal seating, music stands and equipment cases in the sheltered stage | I12 |
| 7 · Training oval | Timing booth, officials’ office and grandstand concourse | I09 |
| 8 · Residences | Twin bedrooms, study tables and common-room seating in all eight courts | I08 |

## Room access

The academy entrance connects to the reception hall, both classroom corridors and the library. The east corridor continues into the return gallery. Internal passages connect the four west quadrangle ranges, the west teaching wing and its returns, and the garden reading nook and cloister. The classroom wings and library have stairs between their modeled floors. Each residence courtyard has stairs and landings that connect the four ranges on each floor. The bedroom wings are 0.82 m deeper, with 1.22 m clear doorways and standing space beyond the swing in all 48 bedrooms.

The `Room access markers` collection contains 229 standing positions in 92 floor zones. The [room route data](interior-access.json) records their positions and 103 routes across entrances, stairs and connecting passages in Blender metres. Blender clearance checks use a 1.70 m tall, 0.35 m radius capsule. In Godot, convert a Blender position `(x, y, z)` to `(x, z, −y)`.

The Godot checks drive the runner through each route in both directions, work the bedroom doors, and verify contact with the solid fountain and stump. Run them from the project root after importing the campus.

In the playable scene, `CampusCollision` builds the surface, tree-trunk and fountain physics bodies at startup. Its physics bodies appear under the builder in the remote scene tree while the game runs. The fountain collision follows the solid basin, pedestal, bowl and bronze sculpture, including the floor below the water. The upper brass band has an open center so the bowl holds a clear water surface. The stump has a real opening from the cut rim down to a solid recessed floor.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --fixed-fps 60 --script res://game/tests/campus/walk-campus-links.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --fixed-fps 60 --script res://game/tests/campus/check-residence-doors.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --fixed-fps 60 --script res://game/tests/campus/check-campus-landmarks.gd
```

## Exterior previews

| View | What it shows |
|---|---|
| [Campus overview](../../design/tracen-academy/previews/campus-overview.jpg) | The grounds, academic buildings, residences, sports district and nested tracks |
| [Courtyard in Godot](../../design/tracen-academy/previews/courtyard-godot.jpg) | The academy façade, fountain, planting and benches at runner height |
| [Courtyard glazing](../../design/tracen-academy/previews/courtyard-glazing.jpg) | The view through the windows in Blender Material Preview |
| [Exterior finishes](../../design/tracen-academy/previews/exterior-finishes.jpg) | Close views of marble, brick, oak and metal |
| [Hedges and grass](../../design/tracen-academy/previews/planting-detail.jpg) | Shrub structure, loam beds and grass by the path |
| [First bend](../../design/tracen-academy/previews/training-oval.jpg) | The compacted clay track and rail at runner height |
| [Fountain motion study](../../design/tracen-academy/previews/fountain-flow.mp4) | The three pours, spray and ripples from the water review |

## Exterior and route

The gate origin is Blender (0, 0, 0), with +Y into campus and Z up. The gate opening is 8 m wide. From the fountain court, the route turns east toward the outer rail opening and the start marker at (40, 136, 0). The primary dirt oval is about 376.5 m around its centerline. Blender clearance checks covered the approach and three running lines, and Godot rendered the route at runner height. The playable milestone covers the runner, camera collision and lap tests. [Layout and playable milestone](../../docs/milestone-1-campus.md)

In the playable Godot scene, both gate lanterns cast shadows from beside the glass panes. The limestone caps shade the recessed brick joints while warm light reaches the entrance paving. Press **T** to advance the clock to **22:00** and inspect the piers from the path.

The frontage has 30 linked classroom bays, a clock tower and covered walks around the court. The three original bronze goddesses pour into a marble-lined basin. The courtyard stump retains flared roots and exposed growth rings around a deep hollow. Detailed azaleas and boxwood sit in planted beds, and Blender scatters curved blades near paths and lawns. The GLB shares shrub meshes and uses lighter blade geometry. The original blockout and campus directory artwork are available for reference. [Original Blender blockout](blockout-sources.zip) · [Campus directory artwork](../../design/tracen-academy/campus-guide.png)

## Asset sources

| Source | Use |
|---|---|
| [Quaternius Stylized Nature MegaKit](https://quaternius.com/packs/stylizednaturemegakit.html), CC0 | Fitted avenue and woodland tree meshes |
| [MakeHuman graphics assets](https://www.makehumancommunity.org/about/license.html), CC0 | Face meshes adapted for the three fountain figures |
| [ambientCG Grass 005](https://ambientcg.com/view?id=Grass005) and [Poly Haven Leafy Grass](https://polyhaven.com/a/leafy_grass), CC0 | Shared turf and lawn finishes |
| [Poly Haven Japanese Cedar Bark](https://polyhaven.com/a/japanese_cedar_bark), CC0 | Tree bark color and relief |
| [ambientCG Marble 014](https://ambientcg.com/view?id=Marble014), [Poly Haven Sandstone Cracks](https://polyhaven.com/a/sandstone_cracks) and [Brown Brick 02](https://polyhaven.com/a/brown_brick_02), CC0 | Adapted marble, carved stone and clay detail |
| [Poly Haven Dirt](https://polyhaven.com/a/dirt), [Damp Sand](https://polyhaven.com/a/damp_sand) and [campus texture pilots](../../docs/campus-texture-prompts.md) | Color and relief for the compacted clay course |
| [Poly Haven Kloofendal 48d Partly Cloudy](https://polyhaven.com/a/kloofendal_48d_partly_cloudy_puresky), CC0 | Graded sky panorama for daylight and reflections |

The campus architecture, fittings, lettering, bushes and fountain were authored for this project. Exterior production used zero Tripo generations. [Exterior production brief](../../docs/campus-art-production.md) · [Campus reference images](../../design/tracen-academy/references/README.md)

## Refresh the GLB

Run from the repository root on macOS. The exporter evaluates modifiers, bakes editable lettering and sports curves for export, and writes `campus.glb` and its grass scatter data together. Keep both outputs beside the preview scene.

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b art/campus/campus.blend --python-exit-code 1 -P art/campus/export_glb.py
```
