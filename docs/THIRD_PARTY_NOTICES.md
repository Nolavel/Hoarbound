# Third-Party Notices

## Licensing of this project itself

`/LICENSE` holds Hoarbound's own terms: copyright reserved, not open
source. Until 2026-09-23 that path held an unrelated third party's MIT licence
(`Copyright (c) 2023 mohsenph69`, author of the Godot-MTerrain addon), which
arrived in commit `5496269` with terrain experiments and was never replaced —
so the project was formally published as MIT by someone unconnected to it. That
was never an intentional grant. See issue #5.

## Godot Engine

<https://godotengine.org> — Copyright (c) 2014-present Godot Engine
contributors; (c) 2007-2014 Juan Linietsky, Ariel Manzur. MIT License,
<https://godotengine.org/license>. Godot bundles further components under their
own licences; the full list comes from `Engine.get_license_text()` and
`Engine.get_copyright_info()`. **Must ship with builds.**

## Quaternius Universal Animation Library (UAL1, UAL2)

Mannequin, armature and animation clips in `assets/animation/ual/`. CC0 1.0
(public domain dedication); no attribution required, credited anyway. Details
and provenance in [`assets/animation/ual/NOTICE.md`](../assets/animation/ual/NOTICE.md).
Henry's outfit GLB is derived from the UAL1 mannequin.

## Motion Matching capture data

Source BVH captures are staged at run time (CI and local tools) and stay out of
Git. The baked locomotion database derived from them,
`data/motion_matching/henry_cmu_locomotion.res`, is committed and ships with
the game (author decision, 2026-10-07): poses retargeted onto Henry's UAL
skeleton plus matching features, with each range's source URL and SHA-256.

- Carnegie Mellon University Graphics Lab Motion Capture Database — CMU states
  that its motion data is free for all uses. The tools use the public BVH
  conversion mirror documented in `tools/ci/prepare_cmu_sample.sh`. The
  committed database contains CMU material only.
- The 100STYLE Dataset — Ian Mason. Only the original `Neutral_SW` and
  `Neutral_TR1` captures are staged (pinned SHA-256). Licensed under Creative
  Commons Attribution 4.0 International; <https://www.ianxmason.com/100style/>.
  Not baked into the lab database until its retarget profile is verified
  (see `docs/motion_matching/retarget_audit.md`).

## Audio — provenance not yet recorded

`assets/audio/music/intro/intro_game_01.mp3` and the files under
`assets/audio/sfx/` have no recorded source or licence. Until they do, they
must not ship in a build. Owner: the author.

## Code ported from Nolavel/ADT

Parts of the body and interaction layer (items, catalog, garments, equipment,
inventory, interaction, hold prompt, input claim, player state) are ported from
`Nolavel/ADT` — *Vertical Trespass* / *Another Digital Thriller*.

ADT's licence reserves all rights and forbids reuse of its source in another
project **without prior written permission from the copyright holder**. Both
projects are owned by the same copyright holder, who granted that permission for
this port on 2026-09-23. What was taken, and what changed on the way across, is
recorded in [`technical/PORTED_FROM_ADT.md`](technical/PORTED_FROM_ADT.md).

### Asset from Nolavel/ADT: foot print stamp

- Source: `Nolavel/ADT` → `assets/textures/pins/pin_step_walk.png` (500×500 RGBA).
- Used as: `assets/textures/snow/footprint_left.png` and `footprint_right.png`,
  each foot cropped with a 6 px margin; pixels otherwise unchanged. Tinted at
  runtime as compressed snow by `FootprintSystem`.
- Same copyright holder and the same written permission as the code port
  above; the author pointed to this asset for footprints on 2026-09-23 (#16).

## Fade Volume

- Source: https://godotshaders.com/shader/fade-volume/
- Author: dairycultist
- Published: August 29, 2026
- License: CC0
- Hoarbound changes: color/alpha control, numerical guards, reusable BoxMesh scene.

## Stylized shadows, not a post processing

- Source: https://godotshaders.com/shader/stylized-shadows-not-a-post-processing/
- Author: ShaderError
- Published: May 22, 2023
- License: CC0
- Hoarbound changes: reimplemented for stock Godot without the source shader's
  custom `sample_directional_shadow()` engine modification. The shadow lookup is
  moved through `LIGHT_VERTEX`, and the directional `ATTENUATION` is cut into
  three tones inside `light()`.

## Simple Overcast cloud layer

- Source: https://godotshaders.com/shader/simple-overcast/
- Author: tentabrobpy
- License: CC0
- Hoarbound changes: multi-layer angular parallax, depth sampling, wind, cloud-shape
  contrast and integration into the combined Freeman atmosphere shader.

## Freeman's Sky Shader

- Source: https://godotshaders.com/shader/freemans-sky-shader/
- Upstream: NiwlGames/GodotStarterAssets, shaders/sky_full.gdshader and
  shaders/sky_quarter.gdshader.
- Author: Niwl Games.
- Published: June 16, 2026.
- License: CC0-1.0.
- Hoarbound integration: official full-resolution and quarter-resolution variants are
  retained for reference. Production uses
  shaders/environment/freemans_parallax_clouds.gdshader, which combines the
  Freeman atmosphere with HFN's CC0 Simple Overcast-derived parallax cloud layer.
  The atmosphere receives a dedicated solar direction from DayNightManager,
  while scene LIGHT0 continues to illuminate clouds as sun or moon.

## Wind Driven Falling Particles

- Source: https://godotshaders.com/shader/wind-driven-falling-particles-leaves-petals-feathers/
- Author: ProfesorShader
- Published: July 12, 2026
- License: CC0
- Hoarbound production adaptation: procedural snowflake geometry, WeatherController-
  driven wind/gusts, live steering of airborne flakes, Terrain3D HeightField
  collision, rare foreground flakes and render-only high-wind velocity stretch.
  The source shader's autonomous wind range/change and vortex are not used.


## Fonts

| Font | Author | Licence | Files |
|---|---|---|---|
| Averia Libre | © 2011 Dan Sayers | SIL Open Font License 1.1 | `assets/fonts/Averia Libre …/OFL.txt` |
| IM Fell English SC | © 2010 Igino Marini | SIL Open Font License 1.1 | `assets/fonts/IM Fell English SC/OFL.txt` |
| Special Elite | © 2011 Astigmatic (AOETI) | Apache License 2.0 | `assets/fonts/Special Elite/LICENSE.txt` |
| CGF Locust Resistance | Chris Garrett | Free for personal and commercial use | `assets/fonts/CGF Locust Resistance/LICENSE.txt` |

CGF Locust Resistance came over from `Nolavel/ADT` (same copyright holder and
permission as the port above); ADT's `docs/CREDITS.md` records its licence.
ADT's BlackRock is a project-only typeface and was deliberately not brought over.
OFL and Apache-2.0 notices must ship with builds.
