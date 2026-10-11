# Hoarbound Art Direction

Status: **production visual contract**, approved by the author on 2026-10-12.

This document is the visual source of truth for Hoarbound. It defines how the
finished game should read on screen. Technical rendering documents implement
parts of this direction; they do not redefine it.

The author-approved reference supplied during the 2026-10-12 art-direction
review is the clearest target for the intended look: full 3D scenes that read
as hand-painted illustration rather than realistic PBR. The durable contract is
written here so the direction does not depend on a social-media link remaining
available.

## North star

**Painterly 2.5D NPR — full 3D geometry, 2D painting logic.**

Hoarbound is a real-time third-person 3D game. Perspective, parallax, animation,
weather and interaction remain fully 3D. The image, however, should be organised
like a painted concept frame:

1. silhouette first;
2. a few large value and colour masses;
3. controlled light and shadow shapes;
4. broad surface brushwork and authored irregularity;
5. small material detail only where it improves recognition or focus.

A frame should read as a painting before the viewer starts inspecting material
microdetail.

## Core visual rules

### 1. Geometry serves shape, not realism

Assets may use proper production geometry, but the visible result prioritises
clear silhouette, readable planes and deliberate proportion over dense bevels,
surface noise or physically exact construction detail.

This is not "low poly" as a style requirement. Complex geometry is allowed when
it changes silhouette, interaction, deformation or animation. Geometry that only
adds realistic microstructure without changing the read is usually wasted.

### 2. Shading resolves into large masses

Light should describe forms through broad readable regions rather than long,
perfectly physical gradients everywhere. Lit planes, shadow planes and selected
accents should remain legible at gameplay distance.

The current stylized-shadow system is one implementation layer of this rule, not
the definition of the whole look. Hoarbound must not become "ordinary realistic
PBR with noisy shadows".

### 3. Shadows are colour, not black subtraction

Shadow colour belongs to the palette. Outdoor cold fill may push shadows toward
blue, violet or muted cyan while key light remains comparatively warmer or more
neutral. Interior firelight may invert that relationship.

Shadow design should support composition and mood while remaining coherent with
the scene lighting. See [LIGHT_AND_SHADOW_DIRECTION.md](LIGHT_AND_SHADOW_DIRECTION.md)
and [STYLIZED_SHADOWS.md](../technical/STYLIZED_SHADOWS.md) for the current
research and implementation contract.

### 4. Materials are identified by authored cues

Wood, cloth, painted metal, snow, ice, skin and concrete should read through:

- shape;
- base colour relationships;
- a few characteristic marks or breaks;
- controlled roughness/specular response;
- context.

Do not rely on photoreal micro-normal, dense grunge, procedural scratches or
uniform high-frequency detail to prove what a material is.

PBR may remain under the hood where it helps lighting and consistency, but it is
subordinate to the painted read. Specular response should be restrained and
used deliberately. Strong highlights belong where they help recognition,
material contrast or composition.

### 5. Brushwork is broad, sparse and surface-bound

Painterly variation should look authored. Prefer broad strokes, clustered colour
changes, broken edges and selective accents over evenly distributed noise.

Brushwork must stay attached to the object or world. Avoid fullscreen painterly
filters that smear the image in screen space or make the style swim with camera
movement.

Procedural sources are acceptable as tools for generating variation, but the
final result must not look procedurally uniform.

### 6. Detail has a hierarchy

Not every square metre deserves the same contrast or frequency of detail.
Primary forms and focal objects get the strongest shape language. Secondary
areas simplify. Distant scenery collapses toward larger, quieter masses.

The viewer should not have to parse equal detail on Henry, the nearest prop, a
house facade and the horizon at the same time.

### 7. The world and characters share one visual language

Henry, clothing, held objects, architecture, snow, vegetation, vehicles and
interiors must belong to the same image.

A realistic character in a painterly world, or a photoreal prop dropped into a
stylized scene, is a failure even if each asset is individually well made.
Lighting, palette, edge treatment, texture scale and material response should
feel related across asset categories.

### 8. Atmosphere behaves like a painted depth layer

Fog, sky, cloud masses, snowfall and distance should simplify the image and
control depth. Distant forms should lose contrast and detail intentionally,
not merely because of texture mipmaps.

The frozen Key West setting should retain traces of its former tropical colour
identity under the cold palette rather than collapsing into uniform grey.

### 9. Snow and ice are stylized surfaces, not white realism shaders

Snow should read through large value shifts, soft shape breakup, tracks,
wind-shaped accumulation and selective crust/ice accents. Avoid universal
sparkle and high-frequency glitter.

Ice can carry stronger local specular response than snow, but still needs to
fit the same painted value structure.

### 10. Outlines are not the foundation

Hoarbound does not use a universal comic outline as the main readability tool.
Silhouette, value separation, colour relationships, contact accents and
lighting do that work first.

Local edge accents are allowed when they solve a specific readability problem,
but a fullscreen Sobel-style outline is not the visual identity.

## What Hoarbound is not

The target is **not**:

- photorealistic PBR with a stylized LUT;
- realistic assets plus stylized shadows only;
- a generic cel/toon shader with two or three N·L bands;
- low-poly as an end in itself;
- a comic-book outline applied to everything;
- procedural grunge and noise used as a substitute for authored texture work;
- a fullscreen paint filter that makes an otherwise realistic scene look
  artificially smeared.

If a technically impressive feature pushes the final frame toward any of these,
it is the wrong feature for the project unless the author explicitly changes
the direction.

## Asset authoring target

For a typical production asset, work in this order:

1. establish silhouette and proportion;
2. establish the dominant 3–5 value/colour masses;
3. make the asset readable under the shared Hoarbound lighting language;
4. add broad painted variation and characteristic material cues;
5. add only the small details that survive gameplay distance or matter for
   interaction;
6. verify the asset in the actual game scene, not only in Blender or an isolated
   material preview.

Texture resolution is not a quality target by itself. A 4K texture full of
uniform noise can be less correct for Hoarbound than a simpler texture with a
stronger painted hierarchy.

## Scene review test

Before accepting a visual asset or rendering change, inspect the normal gameplay
camera and ask:

- Does the silhouette read immediately?
- Can the main light and shadow masses be understood before surface detail?
- Does the material belong to the same painted world as Henry and the snow?
- Is there any photoreal microdetail pulling the frame away from the target?
- Does detail reduce with distance and importance?
- Are the strongest contrasts where the player should look?
- Does the image still work without a fullscreen outline or paint filter?
- Does motion preserve the brushwork instead of making it swim or shimmer?

A render feature is not accepted because it is sophisticated or physically
accurate. It is accepted when it improves this target image in motion.

## Relationship to existing documents

This document owns **visual intent**.

- [LIGHT_AND_SHADOW_DIRECTION.md](LIGHT_AND_SHADOW_DIRECTION.md) — research,
  palette, shadow colour, brushwork and lighting direction.
- [STYLIZED_SHADOWS.md](../technical/STYLIZED_SHADOWS.md) — current production
  implementation of stylized shadow rendering.
- [../visual_fx_shaders.md](../visual_fx_shaders.md) — index of production VFX
  and shader systems.

If a technical implementation conflicts with this document, do not silently
reinterpret the art direction to match the implementation. Treat the mismatch
as a production issue and bring it back to the author.
