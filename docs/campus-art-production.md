# Tracen Academy exterior production brief

This brief records the blockout inventory and proposed surface treatments. For the current Blender sources, furnished interiors and runtime export, use the [campus asset handoff](../art/campus/README.md).

This is the original exterior art brief. Open the [current campus handoff](../art/campus/README.md) for the delivered models, material sources and preview gallery.

Plan for **24 individually authored assets across the campus exterior**. Eight landmarks deserve a custom silhouette and sixteen reusable pieces deserve one carefully made master each. Budget **10 additional assemblies** to fit those pieces to the remaining buildings and grounds. That gives us **34 reviewable items**. A fountain with a bowl, figure and water surface counts once. Eight dormitories built from the same plan also count once. This estimate assumes the runner can explore the grounds and see building exteriors. Enterable interiors would need a separate inventory. [Numbered design map](../design/tracen-academy/campus-blockout-map.jpg)

**Start with the view through the gate.** Finish one entrance pier, a short wall return and one 4 m classroom bay. Put them back in the existing scene, with the clock tower at the far end of the avenue. This single view tells us whether the masonry holds up at arm’s length, whether the façade reads across the court, and whether the two belong to the same school. For surface images, start by fitting the **four existing candidates** for brick, paving, dirt and turf. The number of new images needed to begin is **zero**. [Gate reference](../design/tracen-academy/references/gate.jpg) · [Avenue reference](../design/tracen-academy/references/avenue.jpg) · [Pilot textures and generation prompts](campus-texture-prompts.md)

## Blockout inventory before the modeling pass

The initial blockout contained 1,237 scene objects. Of those, 539 are placements of six linked collections. A change to one course-post master reaches 288 placements, a beam change reaches 197, and a classroom-bay change reaches 30. The avenue tree, court lantern and court bench each have eight placements. Other scenery, including the woodland crowns and dormitory shells, repeated visually in local meshes. Keep a replacement aligned to its source pivot, width and ground elevation. Edit repeated pieces in the kit and fit unique assemblies in their campus district. [Master scene](../art/campus/campus.blend) · [Linked kit](../art/campus/kit.blend)

The enlarged model is the dimensional reference for this work. The entrance is 8 m wide. The main route turns east before the fountain and enters the primary dirt course through a 6 m opening. The primary lap has two 94 m straights and two 30 m radius bends, about **376.5 m** on the centreline. The nested courses are essential to the aerial silhouette. Concentrate trackside detail on the runnable circuit. [Campus layout and handoff](milestone-1-campus.md)

## The 24 assets to author individually

### Eight landmarks

| ID | Landmark and map location | Where to spend the modeling time | View that decides whether it is finished |
|---|---|---|---|
| L01 | Entrance gate, pin 4 | Build one pier with a stepped stone foot, cap overhang, plaque frame and lantern seat. Mirror it, then fit the wall returns. Align brick courses around the corner and under the cap. | Stand just outside the gate and orbit one pier. Its crown and plaque have visible depth, and the opening still frames the tower. |
| L02 | Clock tower, pin 3 | Work from the spire down through the clock chamber, sloping skirt and open belfry. Tune the relative heights first. Give the dial a projecting bezel and readable hands. | In the gate view at half size, the spire, pale dial and belfry remain three distinct shapes between the trees. |
| L03 | Main entrance pavilion, pin 3 | Give the centre bay deeper window reveals, tall paired glazing, recessed doors, front steps and a projecting cornice. Fit the side bays to its storey heights. | From the fountain, the front doors sit behind the columns. From the east path, the side return meets the main roof cleanly. |
| L04 | Fountain, pin 2 | Retain the 6 m basin. Shape the coping, pedestal and central sculptural figure against the façade. Check a plain clay silhouette before refining the figure. Give water its own recessed surface. | Walk around both sides. The figure reads in profile and the near rim stays in front of the water at a low camera angle. Check contact at the coping, submerged floor, upper bowl and bronze casting. |
| L05 | Curved covered walk, pin 2 | Fit the paired arms, blue roof and junctions with the building. Set the arch rhythm along the curve using M05. Give the walk a visible underside and a deliberate ending on each side of the east exit. | The court aerial reads as a curve. From beneath it the supports land on the ground, and the runner can see the route out. |
| L06 | Stump Courtyard, pin 5 | Shape an irregular stump with flared roots, a broad collar of cut growth rings and a recessed hollow in the top. Arrange the existing benches around the clearing. Verify the runner lands on the solid floor of the hollow and can jump out. | From the west walk, the stump distinguishes this garden from the fountain plaza. |
| L07 | Sports Hall, pin 7 | Preserve the long teal gable. Give the eaves thickness, differentiate the end elevation from the long side and deepen the entrance canopy. Repeat the structural bays. | The hall is identifiable by roof and span in the aerial. The entrance can be found from the dining terrace. |
| L08 | Racecourse stands, pin 10 | Shape the canopy profile, stepped seating, aisles and concourse. One repeated seating section can supply most of the length. Keep the officials’ tower as part of this assembly. | From the near bend the seat tiers read below the canopy. From the campus side the concourse has an identifiable entrance. |

### Sixteen reusable pieces

| ID | Master | Build once and reuse |
|---|---|---|
| M01 | Gate wall and coping | A repeatable wall length with a return/end treatment. Test a straight run and a 90° corner against the L01 pier. |
| M02 | Four-metre classroom bay | Refine the linked `Facade bay 4m`. Give the sash a recess, a sill and a shadow under the lintel. Check three bays together before updating all 30. |
| M03 | Academic wing corner | Build a pilaster and return that absorb the end of a bay. Check front, rear and side elevations on the quadrangle. |
| M04 | Roof edge and cornice | Make a short fascia, coping and soffit profile with a corner variant. Its projected edge should catch daylight above the windows. |
| M05 | Arcade bay | Model the arch opening, springing points, pier foot and underside. Fit one straight and two adjoining curved bays before building out L05. |
| M06 | Secondary window band | A simpler sash and sill for dorms, gym and service wings. Group by floor and vary the bay spacing to fit the building. |
| M07 | Avenue tree | Refine the linked trunk fork and overlapping crown masses. Rotate and scale instances within the height range that preserves the tower sightline. |
| M08 | Woodland tree cluster | Compose a tall, middle and low crown with an uneven outer edge. Make a few arrangements from these crowns for the course belt and housing edges. |
| M09 | Hedge and planter edge | Create a clipped hedge section and a turning end. Lower it at the track reveal. Use the same planting edge around the plaza lawns. |
| M10 | Bench | Refine the linked seat, supports and feet at runner scale. A narrow gap between seat and frame gives the side profile depth. |
| M11 | Lantern | Refine the linked post, lantern head and cap. Adapt the same head to the gate pier. Keep the lit and shaded sides legible in daylight. |
| M12 | Sign and plaque carrier | One framed sign face with mounting and post variants. Swap the graphic for the entrance plaque, east turn and course entrance. |
| M13 | Course post | Refine the linked upright, rail attachment and terminal cap. Review a terminal at each side of the 6 m opening. |
| M14 | Course beam | Preserve the linked 1 m span and its longitudinal axis. Put detail in the cross-section so stretching a span on a bend preserves its thickness. |
| M15 | Path border and curb | Make a straight profile and a corner treatment for paving and lawns. Keep the running surface flush at the court and rail opening. |
| M16 | Shopfront bay | Recess one doorway and broad window beneath the dining arcade. Repeat with restrained sign-panel variations. |

## Ten assemblies for the rest of the map

Each row is one fitting and review job. Use the existing footprint as the starting point. Approaching a secondary building should reveal a believable entrance, side wall and roof return. Beyond the running route, spend the next hour on the roofline or courtyard opening before adding smaller window details. [Illustrated campus aerial](../design/tracen-academy/references/campus-aerial.webp)

| ID | Blender collection or district | Assembly decision |
|---|---|---|
| A01 | Main classroom wings and `west_academic_quadrangle`, pin 3 | Fit M02–M04 to the front, side and rear ranges. Align floors, close corner gaps and keep the western quadrangle visibly open from above. L02 and L03 occupy the centre. |
| A02 | `the_alley`, pin 6 | Keep the narrow passage between staggered wings. Use M06 and give a front-facing entrance enough depth to read along the passage. |
| A03 | `west_campus_pavilions` and low garden pavilions | Derive the small halls from one low façade and roof treatment. Vary length, orientation and garden setbacks across the row. |
| A04 | `dining_and_shops`, pin 9 | Fit M16 under the existing canopy. Pair the terrace edge and benches with those at the front plaza. |
| A05 | Gym building in `gym_and_courts`, pin 8 | Use a compact flat roof, a distinct entrance and higher windows along the court side. Check its silhouette beside the taller gabled Sports Hall. |
| A06 | Tennis courts in `gym_and_courts`, pin 8 | Fit one court, net and perimeter treatment, then repeat it. Use accurately drawn lines and muted red surrounds. |
| A07 | `west_playing_field` | Keep a broad green plane. Give the goals a modeled outline and lay out the lines together so the field remains readable from the overview. |
| A08 | `outdoor_amphitheatre` | Refine one terrace wedge and repeat it around the fan. Preserve the radial aisles and shape the stage shell so its opening faces the seats. |
| A09 | `dorm_blocks`, pin 12 | Finish one courtyard block with M06, roof parapets and a street entrance. Repeat it across the eight footprints. The two rows can share geometry and keep their rose and blue roof accents. |
| A10 | `training_oval`, `training_path` and bordering grounds, pin 11 | Fit M13–M15 to the primary circuit. Preserve the start stripe, rail gap and nested sand, dirt and turf bands. Use M08 for the outer tree belt and M12 at the approach. |

## Which surfaces need pictures?

Use an image when the eye needs **flat information** such as mortar joints, paving seams or quiet changes in ground color. Use geometry for a silhouette, an opening, or an edge whose shadow moves as the runner turns. The gate illustrates the split well. Brick bonds belong in a repeating image, the cap overhang belongs in the mesh, and plaque lettering belongs in an editable graphic. One gate image would fix the viewing angle and shadow direction across all three. The reference pictures serve as visual comparisons during review. [Gate close view](../design/tracen-academy/references/gate.jpg)

| Surface | First-use decision | Fit and acceptance |
|---|---|---|
| Gate brick and masonry returns | Use the existing text-only terracotta pilot. | Start at a 1.20 × 1.20 m repeat. Check 16 courses per repeat, half-brick offset, vertical alignment around the pier and joint thickness at the wrap. [Brick candidate](../design/tracen-academy/texture-pilot/terracotta-brick-text.png) |
| Avenue, court and east path | Use the existing wrap-adjusted limestone pilot. | At 2 × 2 m, the 8 m avenue spans four repeats. Carry the same origin, scale and course direction across region boundaries. Inspect the east turn at a grazing angle. [Paving candidate](../design/tracen-academy/texture-pilot/limestone-paving-wrap.png) |
| Primary dirt circuit | Use the existing compacted-dirt pilot. | Map 2 × 2 m in ground coordinates through straights and bends. During a lap, check for a visible repeating blotch and for an orange cast beside the turf. [Dirt candidate](../design/tracen-academy/texture-pilot/compacted-dirt.png) |
| Plaza lawns, infield and turf bands | Use the existing short-turf pilot near the player. Distant strips can share its average color. | Start at 2 × 2 m. Compare the lawn with the tree canopy in daylight. The pilot runs yellower than the target swatch. Check that the infield remains quiet in the overview. [Turf candidate](../design/tracen-academy/texture-pilot/short-turf.png) |
| Ochre infill, cream trim, slate and wood | Start with shared colors. Consider one low-contrast wall tile if the close façade looks empty, a horizontal trim sheet if several cornices need mineral variation, or one grain strip if bench slats read poorly at arm’s length. | Decide on each candidate separately in the first finished court view. Reuse an accepted sheet across applicable pieces. Set the grain along the slat and roof courses along the eave. |
| Clock, signs and court markings | Draw clock indices, lettering and arrows as editable vector artwork. Use flat graphic strips or mesh lines for sports markings. A small decal atlas can hold the approved graphics. | Check spelling, hand positions, line widths and alpha edges at the actual display size. Keep the dial bezel, plaque mount, rail and net frame in geometry. |
| Window glass, fountain water, painted metal and foliage | Use material color, roughness and modeled forms first. Give water a quiet highlight, windows a cooler value and crowns broad groups of color. | Orbit windows and water so a highlight responds to the view. Judge foliage from both sides of the avenue. A distant group should read as a continuous canopy with an irregular edge. |

**UV work comes before commissioning more tiles.** At the start of exterior production, 568 of the 686 blockout meshes lacked UVs. The first fitting pass prioritized the primary dirt circuit, infield turf, east path ribbon and track approach extension, then checked repeat scale across the avenue, court and gate walls. Unwrap only the pieces receiving images. On level ground use a shared metric XY projection. On vertical brick faces use horizontal distance and height, and place the seam at a corner with the course phase matched. Export these coordinates as UVs so the same mapping reaches Godot.

Keep the opaque pilot originals as sources. Try 1024 px runtime copies in the shared materials, inspect a 3 × 3 repeat, then look down the avenue and run a bend. In Godot check mipmaps on the imported 3D texture and repeat/filter settings on the material. If joints shimmer, inspect the UV scale, line contrast and filtering before increasing image resolution. For any later generation, record its prompt, physical repeat and the camera view it improves. [Texture fitting and pilot results](campus-texture-prompts.md) · [Godot image import and filtering](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html)

## Keeping the school recognizable in daylight

| Decision | Reference and working rule |
|---|---|
| Choose the reference for the question | Use the illustrated aerial for **where buildings sit** and the court aerial for **how the arcade meets the wings**. Use official daylight game views for the relationships between warm walls, pale trim, cool windows and green canopy. The wider community recreations help read the architecture hidden behind the game UI. Use the Miho photograph for rail construction and spacing. Its surface grain and weathering belong to a different visual treatment. [Reference index and provenance](../design/tracen-academy/references/README.md) |
| Set the large colors together | Start with ochre wall `#C99B68`, ivory trim `#EEE6D5`, slate roof `#66839C` and muted glass `#728D98`. Keep the sports hall’s deeper teal and the dorms’ rose/blue accents local to those buildings. Put a wall, pilaster, window and eave beside one another in the court light before changing any swatch. These sRGB values are project starting colors. [Official game view](../design/tracen-academy/references/academy-in-game.jpg) |
| Give the architecture depth at two distances | From the gate, spend contrast on the roof against the sky and the clock against its chamber. From the court, spend it on the undersides of cornices, the reveals around windows and the roof over the covered walk. Keep plaster and glass interiors broad and quiet. Check the image at half size and in grayscale. If the mortar reads before the tower or arches, reduce its contrast. [Avenue](../design/tracen-academy/references/avenue.jpg) · [Fountain court](../design/tracen-academy/references/fountain-court.jpg) |
| Paint vegetation in masses | Give an avenue crown a shaded underside, a middle green and a lighter upper mass. Break the outline at branch clusters and leave sky gaps around the spire. In the shelterbelt, vary crown height and the overlap of adjacent groups. Reserve individually visible twigs or leaf clusters for the nearest trees. [Avenue tree rows](../design/tracen-academy/references/avenue.jpg) |
| Separate materials with light response | Start masonry, paving, dirt and foliage near roughness 0.75–0.95. Try a lower roughness on glass and water in the same shot. Keep metal accents small enough that the dial and rail still hold their shapes. A soft break between light and shade and a quiet base color will carry more of the game’s daylight look than a heavy outline on every edge. [Official scene and track views](../design/tracen-academy/references/README.md) |
| Freeze the comparison light | The saved Blender baseline uses `Late morning sun` at strength 3.25 and a 12° angle, the `Daylight` world, AgX, Medium High Contrast and exposure 0. Save a baseline render before editing. In Godot match sun direction, shadow softness, sky fill and the appearance of the same swatches by eye. Blender’s light strength and view-transform settings are specific to its renderer. |

## Order of work and review

| Pass | Items | What to bring back for review |
|---|---|---|
| 1 · Gate looking toward the tower | L01, L02, M01, M02, M04, M07, M11, M15 **(8)** | Make the pier, wall return and façade sample first. Fit brick and paving on that short stretch. Compare full-size and half-size renders from `02 · Gate to tower` with the reference, then propagate the bay and tree masters. |
| 2 · Enter the front plaza | L03–L05, M03, M05, M09, M10, M12 **(8)** | Review `03 · Fountain court` and a side view beneath the arcade. Check the fountain silhouette, the ground contact of benches and piers, and the visibility of the east exit with a runner-sized proxy. |
| 3 · Run to the stands | L08, M13, M14, A10 **(4)** | Compare `04 · First bend` with the trackside reference. Fit dirt and turf together. In Godot follow the approach, run beside each rail, return through the opening and check the stripe and start marker at Blender (40, 136, 0). |
| 4 · Finish the wider campus | L06, L07, M06, M08, M16, A01–A09 **(14)** | Review the Sports Hall beside the gym, one dorm before repeating it, and one rear academic corner from the path. Finish with `01 · Campus overview`, `05 · Academy precinct` and `06 · Campus plan` beside the illustrated aerial. |

For each pass, save a before/after pair with the same camera, exposure and output size. Judge the silhouette in plain material first, then with the proposed surface treatment. When the Blender view reads well, export a representative region and compare the same view at the intended play resolution in Godot. Walk sideways past a repeating bay, orbit a nearby prop and run along the ground surface. These movements expose flat façades, stretched UVs, flickering strips and distracting repeats that a still image can hide. Adjust the master, repeat the comparison, then distribute it to the other placements. [Playable milestone review](milestone-1-campus.md)
