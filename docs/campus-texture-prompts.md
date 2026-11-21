# Campus texture pilots and prompts

These prompts and tiles record the early base-color pilots. The [campus art handoff](../art/campus/README.md) lists the materials used in the current model. A small material library can cover most of the five regions. For example, one paving material serves the avenue, court, and training path, and one turf material serves both the court lawns and the oval infield. Reuse at the same physical scale is part of what makes the campus look coherent. [Campus design](milestone-1-campus.md)

## What to carry over from the art references

The mirrored game was open to the night lobby. The light floor stayed visually quiet behind the runner, pale structural elements read as broad shapes, and the blue window bays and warm foliage were easy to distinguish. The outdoor court reference shows the same hierarchy in daylight. Fine grain stays subordinate to clean joints, silhouettes, and the contrast between paving and lawn. The dirt reference shows a low-contrast warm surface whose edge is picked out by a pale rail and green turf. Study these relationships and describe them in words. All pilot generation inputs are text or a generated pilot tile. [Court reference](../design/tracen-academy/references/fountain-court.jpg) · [Training surface reference](../design/tracen-academy/references/training-surface.jpg)

| Keep fixed across requests | Change for each surface |
|---|---|
| Clean, hand-painted 3D animation background with matte, maintained finishes. Small value shifts within each material and restrained edge contrast. | Material and target sRGB color, secondary colors, mark size, and density. |
| Orthographic, perpendicular view with full coverage. Uniform base color independent of the scene light. | Tile, trim sheet or decal, plus the intended UV footprint in metres. |
| Sparse, soft marks and clean construction geometry. | Polycount-independent surface structure such as brick count, bond, stone size, mortar width, and edge phase. |
| One daylight setup and exposure for all screenshots of the campus. | Roughness per surface. Set in Blender so diffuse color and lighting can be tuned independently. |

## Copy-ready prompts

For a repeating surface, send the **shared block followed by exactly one surface block**. Keep the wording in the shared block fixed once it works on neighboring materials. The color is a target for the base coat, so a measured average will also reflect mortar and flecks. Use the expected world coverage to set UVs after generation.

### Shared block used in the pilot

```text
Use case: stylized-concept.
Asset type: single repeatable base-color texture for an original 3D campus environment.
Output contract: one square edge-to-edge material sample, orthographic view perpendicular to the surface. Flat, unlit base color with even values from edge to edge. Tile continuously left/right and top/bottom, including across mortar joints if present. The tile fills the entire image.
Style: clean hand-painted 3D animation background. Quiet matte surfaces, broad small value shifts, crisp simplified construction lines, sparse low-contrast mineral flecks. Newly maintained campus. Use soft pigment variation within the named palette. Let geometry and scene light provide depth.
Exclude: cast shadows, highlights, ambient occlusion, gradients across the whole image, perspective, props, frame, text, logos, watermarks, chipped edges, cracks, moss, photographic pore noise.
```

### Limestone paving · gate approach, court, training path

```text
Surface: pale warm-gray cut limestone paving, centered on #CBC6B7, with joints around #AAA698. At a 2 m × 2 m world repeat, use exactly 8 horizontal courses, each nominal 0.25 m high. Each course has four nominal 0.5 m rectangular stones, with every alternate course offset by one-half stone. Joints are narrow and straight, about 6 mm wide in world space. Only restrained patch-to-patch value shifts. Keep the limestone cool-neutral enough to sit beside the warm brick and cream trim.
```

For a jointed material, add the wrap phase explicitly. This tested addition assumes the first row starts on a vertical joint. Adjust the description if the asset uses a different bond.

```text
Wrap phase: center the top and bottom image boundaries in the middle of the same horizontal mortar joint, so each contributes half the normal joint width. In full-width rows center the left and right boundaries in the middle of the same vertical joint. In offset rows cut the outermost stones in half. When copied three times in both directions, every horizontal joint is the same thickness and the stagger continues uninterrupted.
```

### Terracotta brick · gate walls and piers

```text
Surface: warm dusty terracotta brick for an original campus garden wall, centered on #AF6D54, with subdued warm putty mortar around #B29983. At a 1.20 m × 1.20 m world repeat, use 16 horizontal courses, each nominal 0.075 m high, and 5 nominal 0.24 m bricks per course. Offset alternate courses by half a brick. Joints are narrow and straight, about 8 mm wide in world space. Use small warm clay variations and sparse soft flecks within the bricks, keeping the wall quiet at third-person camera distance.
```

### Compacted dirt · oval tread

```text
Surface: warm ochre-tan compacted dirt for an original campus oval, centered on #B78C68. The tile repeats every 2 m × 2 m in world space. A base of firm dry clay with sparse small softly painted tan and brown grains, evenly scattered. Keep the grain subordinate to the overall warm tan, with fine-scale variation only. Exclude footprints, wheel tracks, rake lines, large stones, grass, cracks and irregular patches that would form a repeating motif.
```

### Short turf · lawns and infield

```text
Surface: low-cut school lawn and oval infield, centered on #94B775. A 2 m × 2 m world repeat. Clean matte yellow-green with tiny soft groups of medium green pigment and very sparse slightly lighter flecks. Use uniform clipped growth, low contrast, and no directional brushwork. Exclude individually silhouetted blades, mowing stripes, bare soil, flowers and large dark patches.
```

## What the six pilot generations showed

I used the built-in GPT image tool with opaque output. All six originals are 1254 × 1254 PNGs. I checked them individually and in a 3 × 3 repeat. The edge figures are mean absolute differences in weighted 8-bit sRGB brightness between opposite outermost pixel rows or columns. Lower values mean a closer edge match. On jointed surfaces, inspect the actual repeat as well. Two identical edge pixels can still create a double-width joint, and a hard edge can be acceptable if it sits inside the correct mortar line.

| Pilot output | What changed | L/R · T/B | Decision |
|---|---|---|---|
| [Limestone paving](../design/tracen-academy/texture-pilot/limestone-paving.png) | Shared block plus paving | 2.6 · 21.7 | Eight evenly spaced courses and the intended half bond. Faint differences at the repeat edge. |
| [Limestone paving, specified wrap](../design/tracen-academy/texture-pilot/limestone-paving-wrap.png) | Added the wrap-phase paragraph | 3.1 · 12.0 | Use as the paving candidate. The vertical repeat improved and the courses still read evenly at reduced size. Check the left/right join and joint thickness on the path mesh. |
| [Terracotta brick, text only](../design/tracen-academy/texture-pilot/terracotta-brick-text.png) | Shared block plus brick | 1.8 · 1.5 | Use as the brick candidate. The five-brick bond, full-height courses and low-contrast brick faces read consistently in the repeat. |
| [Terracotta brick, with reference](../design/tracen-academy/texture-pilot/terracotta-brick-reference.png) | Same brick prompt plus the generated paving as a style reference | 2.6 · 35.4 | Reject for the gate. The model borrowed the paving's four-brick spacing and the tile joins introduce a short course. |
| [Compacted dirt](../design/tracen-academy/texture-pilot/compacted-dirt.png) | Shared block plus dirt | 1.5 · 2.2 | Use as the track candidate. The repeat is quiet. The average `#BB885D` is warmer than the target `#B78C68`. Review it beside the turf under scene lighting. |
| [Short turf](../design/tracen-academy/texture-pilot/short-turf.png) | Shared block plus turf | 1.1 · 1.3 | Use as the lawn candidate. The fine marks read as clipped grass and the repeat is unobtrusive. The average `#90BA63` is more yellow-green than the target `#94B775`. |

The exact extra sentence in the brick reference trial was:

```text
Input image 1 is a style reference only. Use its low contrast, sparse hand-painted flecks, and restrained edge treatment. Generate the specified new material with its own course count, mortar and palette.
```

**Default to the fixed text block for new material types.** The four material families already share a similar level of detail. Try an approved generated reference when making a close variant within one family, such as slightly cooler paving. A reference with strong joints can carry that geometry into another material even when its role is labeled. These results come from one generation per prompt. They give us a starting recipe and specific checks for drift.

## Grow the material set as meshes need it

| Surface | Format and first prompt target |
|---|---|
| Academy wall infill | 2 m square tile for warm ochre masonry around `#C99B68`. Quiet fine mottling and closely matched values across the repeat. Add a course count only where joints remain visible from the court. |
| Coping, cornice and arcade piers | Cream stone around `#EEE6D5`. Use a shared flat material first. If the mesh needs texture, request a horizontal strip with very light mineral variation and a left/right repeat. Keep the UV strip orientation consistent across modules. |
| Roof | Blue slate around `#66839C`. Start with a broad color and roof geometry. For visible seams, request a square top-down tile with soft, regular courses and specify the physical size of a panel. |
| Benches and gates | One wood strip with fine lengthwise grain for the benches and one grounded dark painted-metal material for the gate pieces. For a wood strip, specify the long direction and which two ends meet. |
| Small signs and motifs | Generate individual original motifs as transparent, front-facing decals. Give each its physical size and a clean transparent margin. Add readable text and wayfinding arrows as separate graphics or engine text so the message and placement can be checked directly. |
| Track curb, rail and start line | Use material color and mesh geometry for solid color bands. A track stripe can cross the dirt without interrupting the dirt texture repeat. |

For trims and decals, keep the style and palette lines and replace the tile output contract. A trim prompt needs the UV direction, which edges repeat, and the width of each strip. A decal prompt needs the underlying surface, frontal projection, physical size, true alpha, and how much transparent margin to leave. Request each surface or decal as its own generation. Record the exact prompt, reference input if any, repeat size, and filename for any candidate that advances to Blender.

## Texture fitting and acceptance

1. **Check the image before fitting.** Count the courses and inspect the four edges and all four corners in a 3 × 3 repeat. For dirt and turf, look for a regular checker pattern or distinctive blotch visible from a distance. For paving and brick, compare the centre joint with the wrap joint. If a textured tile drifts, regenerate with one change, such as the edge phase or fleck density, so the result can be compared to its predecessor.
2. **Set the UVs in metres.** For a 2 m square tile, an 8 m wide path spans four UV repeats across its width. Align the UV origin where the same paving crosses a region boundary. Map the brick vertically in 1.2 m repeats and align courses across adjacent wall faces. Use a continuous metric mapping over the dirt oval, including straight-to-bend transitions. A flat XY projection works for the first level track.
3. **Review the materials together.** Plug each sRGB image into Principled Base Color with repeating sampling and use consistent matte roughness. Keep the scene's existing sun and sky settings. Compare the gate, court, and track viewpoints in the milestone plan. Put brick beside coping and paving, and dirt beside the infield and pale rail. Check from standing height and while running to catch oversized joints, flicker, and over-saturated turf.
4. **Export one representative region and inspect it in Godot.** Confirm UV scale, mipmaps and filtering on the imported textures. Check a distant shot and a grazing view along the path. Keep source PNGs as masters and start runtime copies at 1024 px square if the joints and grain survive the resize. Use one shared material per use across regions to avoid carrying multiple independent copies of the same texture. Keep normal and roughness maps separate from base color. Start with constant roughness and use subtle relief only where it is visible. [Godot image import settings](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html) · [Godot glTF import](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html)

The pilot checks covered image files and 2D repeats. The candidates advance to the shared Blender material library after the lit, in-engine review. [Campus art direction and review cameras](milestone-1-campus.md#keep-one-art-style-across-the-campus)
