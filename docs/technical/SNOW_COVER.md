# Snow cover — the contract between weather and snow shaders

Scope: `SnowPresentationSystem`, the `snow_cover` and `frost_amount` shader
globals, and every material that reads them. Decided in issue #16.

## The boundary

```
WeatherController (authority: profiles, blending)
ThermalManager    (authority: outdoor air)
        │  read-only
        ▼
SnowPresentationSystem   ← the only writer
        │  RenderingServer.global_shader_parameter_set, on change only
        ▼
shader globals: snow_cover, frost_amount
        │  `global uniform float …;`
        ▼
props / environment materials (via shaders/environment/snow/*.gdshaderinc)
```

**The snow layer does not know what the ground is made of.** Terrain3D is a
placeholder that may be replaced by a Blender mesh, so no snow work goes into
its shader and no terrain geometry is deformed. Ground snow, when it comes, is
its own layer on top: decals or a local snow shell around the player.

## Globals

| Name | Type | Range | Meaning | Default |
|---|---|---|---|---|
| `snow_cover` | float | 0–1 | **Settled** snow on up-facing surfaces — world state, not the weather. | 0.5 |
| `frost_amount` | float | 0–1 | Rime on steep faces, grown from edges inward. | 0.3 |

Declared in `project.godot` under `[shader_globals]`. A shader that declares
`global uniform float snow_cover;` does not compile if the name is missing
there, so the declaration is part of the contract and is tested.

## Settled snow is state, not a weather mirror

Each weather profile carries `snow_cover` — the level that weather *tends to
leave*. The global does not jump to it. `SnowPresentationSystem` owns a settled
value that moves with game time:

| Situation | Behaviour |
|---|---|
| Snow falling, weather's level above settled | builds at `build_per_hour` (0.6) × snowfall density |
| Weather's level below settled | settles at `settle_per_hour` (0.03): a blizzard's 1.0 takes about a day to settle to calm's 0.35 |
| Outdoor air above 0 °C | extra loss, `melt_per_hour_per_c` (0.02) per degree |
| Fresh world | starts at its weather's level, not bare |

Rime follows the outdoor air (0 at −2 °C, 1 at −25 °C) but moves at
`frost_per_hour` (0.25): it grows and sheds over hours, never snaps across a
threshold. Both values are saved under the `snow` key and restored on Continue.

| Profile | `snow_cover` target |
|---|---|
| calm | 0.35 |
| windy | 0.50 |
| snowfall | 0.80 |
| blizzard | 1.00 |

## Rime grows from edges

Rime needs something to grow from: corners, edges, the cold base of an object,
cavities. It does not appear as uniform noise across a face. `frost_weight()`
takes an `edge` factor, 1 on an edge and 0 mid-face; as `frost_amount` rises the
front moves inward, and noise only breaks up that front.

- **Real assets:** bake an edge/cavity (curvature + AO) mask and assign it to
  `edge_mask` on the material. White is where rime gathers.
- **Placeholder boxes:** set the per-instance `box_half_extents` and
  `box_center_offset` to **the whole surface the piece belongs to**, so seams
  between pieces of one wall do not read as edges. The test shelter does this.

## Rules

- **One writer.** Nothing else calls `global_shader_parameter_set` for these
  names. `SnowfallVFX` may *read* `snow_cover` in its own shader; it does not
  write it.
- **Write on change only**, with a 0.002 threshold. Never read back through
  `RenderingServer` at runtime — that stalls on the render thread. Tests read
  `get_written_snow_cover()` / `get_written_frost_amount()` instead.
- **Frost follows the air outside, not the felt temperature.** A warm shelter
  does not melt rime off the outside of its walls.
- **Readers are free.** `SnowfallVFX` or any shader may read `snow_cover`;
  nothing but `SnowPresentationSystem` writes it. `test_snow_presentation.gd`
  scans `scripts/`, `core/` and `world/` for other writers and fails on one.

## Quality tiers

| Tier | What runs |
|---|---|
| Low (HD 620 class) | cover + rime from the shared include, decal footprints, bounded snowfall particles. No compute, no POM. |
| Medium (Forward+) | as high, but the per-frame contact capture is 512² (packed field stays 1024²). Gain unproven on a real GPU. |
| High (Forward+) | the above, plus — later — a local L0 accumulation field, POM near the camera, compute evolution. |

Nobody enables compute on the low tier by default.

## Material checklist for the dressed slice

Snow reads as a world only when everything outside uses the same include.
Before the slice area is called done, each of these carries
`snow_surface.gdshaderinc` (through `snow_prop.gdshader` or its own material):

- [ ] Ground — a snow shell or decal layer over whatever the terrain becomes
- [x] Test shelter walls and roof
- [ ] Crates, barrels and other outdoor props
- [ ] Rocks and shore objects
- [ ] Dead trunks and vegetation that stands above the snow
- [ ] Path markers and signs
- [ ] Ice edge along the bay, where it meets snow — cover only; ice integrity
      and its crack visuals stay with `IceField`

## Footprints

```
HenryUALVisual skeleton (read only)
        │  foot_l / ball_l / ball_leaf_l, and _r
        ▼
FootContactSensor (on player.tscn)
        │  foot_planted(side, ground_point, heel→toe forward, speed)
        ▼
FootprintSystem (composition root) — pooled Decals
```

- **Signal.** `foot_planted(side, position, normal, forward, speed)`. The normal
  is the ground's, from the same ray; `forward` runs heel to toe *along* that
  ground, so a print on a slope lies on the slope instead of hovering flat.
- **Contact rule.** The ball of the foot within 6 cm of the sampled surface,
  with Henry on the floor and moving faster than 0.35 m/s. Contact distance is
  measured along the hit surface normal rather than world Y. A foot rearms
  either after an obvious 9 cm ground clearance or after its animated ball bone
  rises 4.5 cm relative to that foot's last planted pose in Player-local space.
  The animated phase is observed before the ground ray, so a brief Terrain3D /
  collider-seam probe miss cannot silently lose the next step. Small planted
  jitter remains below the rearm threshold. The contact rule itself remains
  testable without a scene.
- **Orientation.** The decal's +Y is the ground normal (it projects along −Y);
  the print image has the toe at the top, which a decal maps to its −Z, set to
  the heel→toe direction along the ground. Left
  and right prints are cropped from the ADT stamp `pin_step_walk.png`.
- **Terrain-agnostic.** Decals project onto whatever is below. Nothing is
  deformed; real depth belongs to a later local snow shell.
- **Fill.** A print lasts 240 s with no snow falling and 25 s in a whiteout,
  scaled by `WeatherController.get_snowfall_density()`. A pool of 64 reuses the
  oldest print first.
- **Decals are the low tier, not persistence.** Once walking cadence is fixed,
  64 prints recycle well before 240 s. Growing the pool is not the fix; the
  high-tier answer is a local L0 accumulation field that stamps write into.
- **The sensor is the shared source** for anything that needs to know a foot
  landed: footstep audio and ice load can listen to the same signal.

### Known: stride length comes from the animation, not from here

Walking at `MovementController.walk_speed` (4 m/s) with the current walk clip
plants a foot roughly every 1.3–2.7 m. The prints are honest about that: the
clip's cadence is slow for the ground speed, so Henry glides. Tightening it is
an animation/locomotion blend change in `HenryUALAnimation`, not in this system.

## Snow shell (high tier)

`SnowShell` (`scripts/systems/world/snow/snow_shell.gd`, built by `world.gd`)
is the local layer the decals defer to. It reads the settled cover from
`SnowPresentationSystem` and never writes `snow_cover`.

```
SnowField (CPU, 20 cm)          ground + settled depth + drifts + lee piles
        │  ImageTexture (top, depth, cut)        get_depth() / get_snow_top()
        ▼                                                  │
contact camera (ortho, looks up, layer 20) ── lowest height of anything in the snow
        ▼                                                  │
packed accumulator (2 × SubViewport ping-pong, 5 cm) ── max packed, fills back in
        ▼                                                  ▼
snow_ground.gdshader: top − packed + rim          MovementController speed
```

- **One source of truth.** `SnowField` computes the snow on the CPU when the
  window moves: settled 5–25 cm by cover, wind drifts up to 30 cm, lee piles up
  to 60 cm behind anything standing on the ground. Windward faces are scoured,
  hollows fill. Snow thins to nothing at `sea_level_m` and never lies below it.
  Gameplay reads the same numbers the shader draws.
- **Key West settled shape.** The baked city wind map already records static lee
  deposits, windward scour and sheltered banks. Both the streamed chunk cover
  and Henry's shell shader derive visible settled height from the same terrain,
  baked wind texture, shore fade and world coordinates. `SnowField` mirrors the
  baseline for gameplay and tracks; its CPU grid updates in bounded steps.
  Henry's moving window adds packed tracks. The local ray-derived lee, scour
  and blurred bed remain for scenes without the baked map. Baked prevailing wind
  fixes settled ridge orientation; current gusts drive weather effects instead.
  Cover changes rebuild the field even while Henry stands still. The local
  mesh keeps its 3 cm core for prints, then grows to 50 cm spacing at its rim.
  In the outer 6 m it approaches the same two-triangle interpolation as the
  static 2 m chunk mesh; a small grid of far-cover vertex inputs is refreshed
  when that 2 m lattice shifts. This matches the geometry at the square edge
  while keeping the detailed surface and packed tracks close to Henry.
  SnowField also prepares a 40 cm settled-normal image row by row under its
  existing rebuild budget, publishing it with the matching height image.
  The fragment shader uses those normals in the core and computes the slope
  directly across the outer transition. Height, normal and far-grid textures
  update in place when their dimensions are unchanged.
- **Geometry presses the snow.** Anything on render layer 20 (`CONTACT_LAYER`)
  packs the snow where it is lower than the snow top: Henry's whole mesh, and
  resting `ItemPickup`s, tagged by `tag_contact()`. A print is the real boot
  silhouette at the real depth; a dropped item leaves its own shape. No print
  is scripted. The main camera never draws layer 20's contact quad.
- **Packing** is capped at `max_pack` (85 %) of the settled depth: compressed
  snow remains under a boot. The model follows Sumner, O'Brien & Hodgins,
  *Animating Sand, Mud, and Snow* (1999): a boot compresses part of the snow
  and displaces the rest (`displace_powder` 30 %, `displace_crust` 5 %) onto a
  rim just outside the sole, heaped towards its travel. The packed field is
  signed: negative texels are that heap. Wind crust also tilts up slabs at the
  pit edge (shader lip, crust only).
- **Walls and collapse.** Each accumulation pass runs one mass-conserving
  erosion step: where a wall rises more than the snow holds per texel, a share
  (`liquidity`, randomised by `crumble`) sheds across that edge into the pit.
  Powder walls hold `repose_deg` (65°), crust `crust_wall_deg` (84°): snow is
  cohesive, and a 40° repose cone drew prints half a metre wide. A wall a boot
  still touches does not shed (Sumner's inside slope). The drawn slope uses the
  same two angles, so stored and drawn walls converge while the floor rises
  with what fell in. Deep prints also drop crust clumps on lift, as before.
- **Fill.** Packing relaxes back in 900 s calm, 45 s in a whiteout.
- **Henry stays consistent.** His collider stands on firm ground; his boots
  reach the bottom of the pit they made. `MovementController.snow_speed_multiplier`
  falls from 1.0 at 5 cm to 0.6 at 50 cm of snow, `snow_accel_multiplier` to
  0.45: deep snow is slow to get going in.
- **Standing.** Standing still (under 0.15 m/s, on the floor) both boots count
  as planted and rest in their prints; the step sensor only plants moving steps,
  so idle feet used to be lifted onto the snow top with the hips following 60 %
  of it, and Henry stood with bent knees. Hips now follow the lower boot fully.
- **Broken edges.** `snow_ground` breaks each print outline with world noise
  (`jag_crust_m` 2.5 cm, `jag_powder_m` 1 cm), tints cut walls blue with faint
  strata of past snowfalls, runs crack seams (cellular F2−F1) out from crust
  lips, and lets freshly broken grains glint more.
- **Footsteps.** `WorldAudioBinder` reads depth and softness under each plant
  and picks a bank by what the boot meets. The banks are synthesised by
  `tools/audio/generate_snow_footsteps.py` (field recordings tried first did not
  fit): crumpling transients with power-law energies (Fontana & Bresin 2003)
  exciting resonances under a heel-roll-toe force envelope (Cook 2002, PhISEM),
  plus a compression whump, ground knock, crust fractures, leg swish or
  stick-slip squeak per surface. Re-run the tool to retune; it rewrites the WAVs
  and the `.tres` banks.

  | Boot | Bank |
  |---|---|
  | snow under 2 cm | ground (`footstep_event`, none yet) |
  | sinks under 5 cm | `snow_thin` — short crunch on frozen ground |
  | sinks 15 cm or more | `snow_deep` — leg swish, long dark whump |
  | crust (softness < 0.6) | `snow_crust` — slab fractures, then powder |
  | air above −1 °C | `snow_wet` — soft low grains, slush |
  | otherwise | `snow_step` — dense dry crunch |

  On top: gain rises (−6 → +2 dB) and pitch falls (1.08 → 0.82) with the sink;
  running is louder; dry snow below −8…−20 °C layers `snow_squeak`; a boot
  pulled out of a print deeper than 8 cm plays `snow_pull` (`SnowShell.foot_lifted`).
- **Deep snow gait.** Knee-deep (0.5 m) snow leaves 38 % of the speed and 45 %
  of the acceleration, and each boot planted in it dips the speed by up to 45 %
  for ~0.2 s: wading comes in surges. The swinging leg drives its knee up
  (`WadeModifier` 22° hip, 18° knee) and ploughs the lower half of the snow past
  wade depth with the shin instead of stepping over it; a toe ploughing below
  the snow top throws clods ahead (`Plough` spray).
- **Snow on boots.** `BootSnowComponent` packs a clod onto the toe cap of a boot
  pulled out of a print deeper than 8 cm: most in wet snow near 0 °C, a fifth
  of that in dry cold snow. A brisk lift-off may shake 30–80 % off in falling
  clods; warmth melts it in ~45 s (it goes slushy first), −20 °C air takes ~15 min.
- **Running.** A landing at run speed packs up to 55 % of the give at once and
  sinks the rest twice as fast; the window is built 0.9 s ahead of Henry's
  travel and rebuilds at up to 12 ms/frame once he nears its faded rim, so
  prints no longer vanish behind a running Henry.
- **Legs.** `SnowFootModifier` drives each boot's lift with a damped spring
  (slight overshoot reads as weight), pins a planted boot where it landed
  against the clip's glide (up to `lock_reach_m`, then it slides, never snaps),
  and gives the hips a downward kick on each plant scaled by snow depth.
- **What the rays find.** Each field cell casts a ray down. A steep face, or
  anything over 1 m above the ground, is a wall: the shell is cut there and
  snow piles in its lee, scaled by how much wall is around (a lone post
  shelters little). A broad, low, open surface (deck, crate) carries snow. A
  surface with a roof above is indoors: no snow and no lee pile. Where the
  ground under the snow jumps, the shell is discarded rather than hanging a
  curtain between levels. Key West uses exact source building polygons to
  classify house walls independently of streamed building collision. Depth is
  softened over ~0.5 m in scenes without the baked city map.
- **Snow bed.** Without a baked city field, snow settles on the ground
  box-blurred over ~1 m and never below it, so terrain facets and small hollows
  fill in. In Key West the near and far heights share the baked baseline.
  Where the snow thins under ~2 cm the shell is discarded and the ground shows,
  instead of the two surfaces z-fighting at the shore.
- **Prints.** Below `wade_depth_m` (30 cm) only planted soles press: a sole of
  two overlapping ovals (heel and forefoot, so it has a boot's waist) is set
  where each foot lands and held until it lifts, so the gliding walk clip
  leaves separate prints. The heel digs `heel_dig_m` extra on strike and the
  ball `toe_dig_m` as the clip lifts the heel, scaled by pace and softness: a
  print is deep at both ends and shallow under the arch. On toe-off in powder
  a burst of grains is flicked ahead. Deeper, Henry's whole mesh ploughs.
- **Drag.** A lifted foot's toe follows the *visible* boot (the walk clip's foot
  plus SnowFeet's lift) every frame and presses only as deep as it actually dips
  into the snow; following the clip's foot under the snow ploughed one wide
  furrow along every swing: toe-off scuffs and touchdown
  marks in shallow snow, drag furrows where the swing stays low. Nothing
  presses while the toe is above the surface.
- **Window.** 25.6 m, moved in 3.2 m steps; packing is shifted with it. The
  mesh remains 3 cm in a 2.75 m half-width core and coarsens to 25 cm at the
  edge. This is 113,569 vertices instead of 167,281 with the former 3.5 m core.
- **Cost.** Contact capture remains 1024². Packed snow and each of its three
  shape passes are 896² (2.86 cm per texel, formerly 1024² / 2.5 cm), reducing
  each pass's pixel area by 23.4%. The accumulator skips neighbour field and
  contact samples when the packed-height difference cannot overcome either
  material's talus. These are source-level changes; GPU/FPS results await a
  representative HD 620 runtime comparison.
- **Measured budget** (lavapipe CPU box, `main@9ec6f03`, Key West):

  | Place | `SnowField.rebuild` avg / max | Ground samples | `SnowChunkCover.build` |
  |---|---|---|---|
  | Old Town | 478 / 573 ms | 16 384 | 316 ms |
  | Fort Street | 758 / 864 ms | 16 384 | 259 ms |
  | Open coast | 669 / 735 ms | 16 384 | 291 ms |

  Ground rays are ~25% of a rebuild; the rest is GDScript field math. The wind
  field image is ~65 MiB and is shared by every SnowField.
- **Incremental rebuild.** Wind-independent layers live on a grid with a 20-cell
  apron and are only recomputed in newly exposed strips plus each layer's blur
  reach (3 904 rays per 3.2 m move). Wind-dependent depth is reassembled over the
  window each move, sliced at 4 ms per frame; walking now peaks at 23.5 ms physics
  frame (p95 7.3 ms) instead of a 0.5–0.9 s hitch.

### Chunk snow streaming

Chunk cover geometry is baked with `tools/world/bake_key_west_chunk_snow.gd`
and stored per city chunk under `data/world/key_west/snow_chunk/`. The runtime
loads only active chunk meshes, then applies the live weather material. Source
generation remains a fallback for missing or incompatible bake files: it uses
the 12-chunk LRU and 4 ms slices, with a synchronous near-window build to avoid
a missing cover. Re-bake when terrain heights, footprints, authored exclusions,
or the cover geometry algorithm change. Run the bake with Godot 4.8 dev6 .NET:
`Godot_v4.8-dev6_mono_win64_console.exe --headless --path . --script res://tools/world/bake_key_west_chunk_snow.gd`.
Key West uses exact city source polygons and
authored exclusions for cover holes; the First Exit shelter registers its own
outline after the overlapping OSM buildings are excluded. Each polygon is
triangulated once per build; its triangles are indexed into the 2 m cells they
cross. Only those cells are clipped, so snow reaches the wall without square
street gaps or triangles crossing the building. A malformed source polygon that
cannot be triangulated is left uncut and warned about.

The far shader cuts out its cover inside the moving SnowShell square. SnowShell
prepares the replacement field and mesh before publishing that square to the
far shader and does not cast its displaced surface into the shadow map. Packed
material and normal contributions now fade over the same outer 6 m as height;
the thin-cover cutoff matches the far shader at the border.
Local cut cells and the different terrain tessellation can still make the
handoff visible; a representative runtime walk is required to accept it.

### Storm layer

`snow_storm_share` (written only by `SnowPresentationSystem`) mixes the baked
city wind field: R is the old prevailing base, G the fresh storm pattern.
Snow falling in wind drives the share toward `wind / storm_wind_mps`; without
snowfall it consolidates back to `calm_storm_share` over hours. SnowField keeps
both factors per cell, so a share change rebuilds depth only. A settled-cover
change of at least 0.02 also rebuilds depth, independently of window movement.

### Persistent tracks

`SnowTrackStore` files packing leaving the window as 3.2 m tiles (32² bytes,
5 mm steps) stamped with a fill clock (Σ -ln(1 - fill)). Restoring multiplies
by exp(-(clock - stamp)), the same fill-in the accumulation pass would have
applied. The shell saves the store under `snow_tracks`. Bytes are signed
around `ZERO_BYTE` (32), so displaced rims down to −16 cm survive a window move;
saves without `zero_byte` are lifted on load.
