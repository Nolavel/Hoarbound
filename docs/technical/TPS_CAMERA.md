# TPS camera

`scripts/systems/camera/tps_camera.gd` (`TpsCamera`) is a third-person over-the-shoulder camera with one
rule: **the camera stands behind the view, and only the player turns the view.** Walls move the camera body;
nothing moves the look.

The guided camera it replaced (lift over the shoulder, swing round Henry, auto-look, doorway framing and
carry-through, auto shoulder swap, recompose, composition, body guard) is archived whole in
`archive/tps_camera_guided/` with its tests and its full design record. The owner played both and kept
this one: it answers the mouse. Do not bring a behaviour back from the archive without the owner's ask.

## What the player gets

- **Henry stands left of the centre in every space.** His chest sits at about 0.35 of a 16:9 frame's width
  in the open, in a 1.5 m corridor and in a 3 m room, and his body's right edge stays left of the centre:
  the middle of the frame is the world, not his back.
- **He stays solid.** He turns see-through only with the camera jammed against his body: his back on a
  wall or in a corner. With a metre of room behind him he never fades.
- **Nothing turns the view but the mouse or the stick.** No auto-look, no recentre, no tilt. One key (V,
  pad R3) turns the camera behind him on demand.
- **A doorway never takes the controls.** Released keys stop Henry; sideways keys steer.
- **Pillars and furniture turn the boom, thin posts fade.**

## One frame (`TpsCamera._update_rig`)

1. **Follow** (`TpsRigFollow`): the orbit centre trails Henry's feet with a lead along his intent; the boom
   pulls back a little at a sprint.
2. **Pivot**: the followed feet raised to his shoulder joints (`HenryMetrics`).
3. **Boom length wanted**: by openness (rods across the camera's half of the circle and one up:
   `near_distance` 0.95 m in the tightest space, `far_distance` 3.0 m in the open), shortened looking up,
   by an aim (`aim_boom_scale`, on a spring stepped at 120 Hz) and scaled by the player's setting.
4. **Shoulder offset**: `direct_side_per_metre` (0.4) of the boom's own eased length, at most
   `shoulder_offset * direct_side_scale` (1.19 m) and at least `direct_side_min` (0.34 m). Closer than
   that it stops at `direct_side_edge` (0.7) of the length, where his head stands at the frame's edge, and
   closer still it stays `body_fade_end` clear of his eyes, beside his head. The sideways room is read
   now and 0.2 and 0.4 s ahead by travel and turn (`TpsRigCollision.lateral_room`), so a jamb closes the
   shoulder in at `direct_side_in_rate` before it cuts it.
5. **Walls** (`TpsRigCollision`, Lyra's penetration blend): the shoulder leg and the centre sweep snap in;
   ten sphere feelers (`DIRECT_FEELERS`) and three lead sweeps (`DIRECT_LEADS`, by the shoulder's travel
   and the view's turn rate) ease the boom in before a wall cuts it; after a wall clears the boom holds
   `direct_out_hold` (0.35 s) and eases out over `direct_out_time` (0.6 s).
6. **Rise**: with the boom under `direct_rise_lengths` (2.0..1.0 m) the camera comes up from his shoulder
   joints toward his eye line (0.22 m), added after the walls so it cannot feed back; it is given back
   where it would stand the camera within `body_fade_end` of his eyes.
7. **Work frame** (`TpsRigWork`): an authored frame (the stove) blends over the result.
8. **Fades** (`TpsCameraFader`).

The shoulder offset and the rise read last frame's eased boom length. That is the only feedback in the rig
and it is damped (3 1/s out, 16 1/s in); the earlier squeeze-by-boom-share and lens widening were removed
because they made the frame breathe with every wall.

## Why these choices (owner's play test, 2026-11-11)

| Complaint | Measured in the 727 (headless `trace_camera_tight`) | Cause | Change |
|---|---|---|---|
| Henry fills the middle of the frame | head at 0.42..0.45 of the width in tight rooms | the shoulder was squeezed to 35 % as the boom was pressed | offset follows the boom's length; never squeezed |
| See-through too often | 31 % of frames; 100 % strafing by a wall | fade from 0.7 m to his eyes with the camera centred behind his head | fade from 0.36 m to his body's axis; beside him the camera sees past him |
| Jerks against walls | boom pumping in and out round a room | lens widening and shoulder squeeze by boom share; instant ease-out; lead sweeps starting in contact with the wall Henry walks at | all four removed or damped |
| Camera flew off on right mouse with a stone | 6..8 m from Henry after one 100 ms frame | the aim spring's explicit step is unstable over 73 ms | stepped at 120 Hz, clamped (`test_tps_camera_hitch`) |

The technique is the one Cinemachine's third-person follow documents (the collider pulls the camera along
the distance axis first and keeps the shoulder offset, with damping into and out of a collision) and the
framing of God of War (2018) and The Last of Us Part II: the character off-centre, the camera close over
the shoulder indoors, a fade only at contact.

**A 1.5 m corridor stays a poor view** (render, 2026-11-11): Henry with his pack fills the left 45 % of
the frame and the right wall, 0.4 m from the lens, most of the rest. Holding him left costs that there.

**Not solved, by geometry:** with his back flat on a wall there is no room behind his head. The camera
stands beside it, he leaves the frame's left edge and what of him is at the lens is removed. In the render
of that pose the pack's shoulder straps still draw: not fixed. A camera
that rose over him there is what the archived rig did.

## Henry's body (`HenryMetrics`)

The framing heights come from Henry as the game loads him, not from another
character's body ratios (ADT's 0.94 / 0.82 of 1.8 m were dropped; author's
comment on #170).

`tools/runtime/measure_henry_metrics.gd` loads `player.tscn` →
`HenryUALVisual` → `henry_outfit.glb` and skins every visible vertex of the
dressed body on the CPU through the live `Skeleton3D`. It averages 16 poses of
the idle and crouch-idle cycles (one pose varies by 1–2 cm), and writes
`data/characters/henry_metrics.tres`. Re-run it whenever the model, outfit,
scale or capsule changes. `TpsCamera` warns when the capsule no longer matches.

| Metres above the capsule bottom | Standing | Crouched |
|---|---|---|
| Crown of the hat | 1.79 | 1.08 |
| Eyes (midway chin–crown of the head) | 1.62 | 0.90 |
| Shoulder joints (`upperarm`) — **orbit pivot** | 1.40 | 0.86 |
| Coat over the shoulders | 1.52 | 0.97 |

| Silhouette, metres | |
|---|---|
| Between the shoulder joints | 0.38 |
| Widest at shoulder height, arms in, dressed | 0.60 (crouched 0.74) |
| Chest front to back | 0.36 |
| Pack and bear behind the coat (visual clearance only) | +0.32, 0.54 behind the capsule axis |
| Physics capsule | radius 0.50, height 2.00 / crouched 1.30 |

- **The pivot is at the shoulder joints**, 0.22 m under the eyes. With the
  pivot on the coat (0.10 m under the eyes), a camera pressed against a wall
  behind Henry sat 0.20 m from his eyes and hid him; `test_tps_camera_orbit`
  caught that.
- **The eyes** are used for line of sight and the body fade. The eye height is
  the midpoint of chin and crown, an approximation. A real eye landmark or an
  authored `CameraEyeReference` on the skeleton would be exact; not urgent.
- **Pivot study (author's call).** `framing_pivot_share` moves the pivot between
  the shoulder joints (0, 1.40 m, default) and the coat (1, 1.52 m); 0.5 gives
  1.46 m. Judge it by frame share, silhouette stability, head clearance, crouch
  and the doorway, not by anatomy. Run the doorway test once per value:
  `-- pivot0 pivot=0`, `-- pivot5 pivot=0.5`, `-- pivot10 pivot=1`. Compare
  `height_share_mean`, `height_share_std`, `min_head_m`, `faded` in each
  `summary.json`; `test_tps_camera_orbit` guards the back-to-wall case.
- **Between stances** the heights follow the capsule's own height (2.0 ↔ 1.3)
  with one damp. A crouch drops Henry's eyes by 0.72 m; scaling 1.8 m by the
  capsule ratio would have put them 0.20 m too high.

## What stops the boom

`TpsBoomProbe.passes()` decides this per collider shape:

| Collider | Boom |
|---|---|
| Static or animatable body whose middle extent is at least `direct_thin_extent` (0.25 m): walls, doors, ground, pillars, trunks, cabinets | stops; feelers ease the camera in front of it |
| Middle extent under 0.25 m: posts, poles, planks | passes; visuals fade |
| `CharacterBody3D` (NPCs, animals) | passes; visuals fade |
| `RigidBody3D` that is not frozen | passes; visuals fade |
| Frozen `RigidBody3D` | judged by size, like a static body |

The rule is derived from collider data, not from layers, so new content works without tagging. One cast
passes at most 16 such colliders (`MAX_PASSES`); the next one counts as a wall.

## Fades (`TpsCameraFader`)

- **Henry:** `camera_fade` is an instance uniform in `stylized_environment_body.gdshaderinc`, a 4x4 Bayer
  screen-door discard, so the material stays opaque and his shadow dithers with him. It ramps from 0 with
  the camera `direct_fade_distances.x` (0.36 m) from his body's axis (crown to knees) to `direct_fade_max`
  (1) at 0.22 m. Each fragment is weighted by its own distance to the camera, so his legs stay. Meshes
  without that shader (the pack and what hangs on it) cannot dither by fragment: one within 0.45 m of the
  camera goes with the body and one past 1 m stays solid (`body_fallback_reach`). At 80 % and a whole-mesh
  blend the render showed a ghost with the pack's insides; a part of him at the lens now goes entirely. An
  authored work frame fades by distance to his eyes instead (`body_fade_start`, `body_fade_end`).
- **Occluders:** thin colliders on the camera-to-eyes line, and thin ones the camera sphere sits in, get
  `GeometryInstance3D.transparency` 0.7.

## Input and settings

- Mouse look and the pad's right stick (`StickLook`: radial dead zone 0.15, speed = travel squared, 200
  and 120 deg/s, up to +60 % held at the rim). Only look and `camera_behind` are on the pad.
- `camera_behind` (V, R3) eases the view to Henry's facing; any look input cancels it.
- `switch_shoulder` (Z), lean (Q/E).
- Player settings (`CameraUserSettings`): mouse and stick sensitivity, field of view (-10..+15 degrees),
  camera distance (75..130 %), left shoulder by default, invert Y.

## Doorways

`PassageTraversalComponent` still eases Henry onto a doorway's centre line while the player pushes through,
so a 1 m capsule does not catch on a jamb. Its `carry_through` (carry Henry on after the door plane) is off
in the game; `test_passage_traversal` keeps it working for when it is wanted. The camera has no doorway
mode: feelers and leads handle a jamb like any wall.

## Tests

| Suite | Guards |
|---|---|
| `test_tps_camera_framing` | Henry's place in a 16:9 frame in the open, a corridor and a room; solid unless jammed |
| `test_tps_camera_direct`, `test_tps_camera_orbit` | a dead end with a wall 0.4 m behind him: never in a wall or in his head, view never turned |
| `test_doorway_camera` | door D1 of the real 727, fixed 60 fps: head in frame, no frame step over 0.4 m, no carry |
| `test_tps_camera_direct_spaces` | the real Henry crouched through a crawl space and up a stair ramp |
| `test_tps_camera_pillar` | a 0.4 m pillar turns the boom smoothly, a 0.1 m post fades |
| `test_tps_camera_hitch` | 100 and 250 ms frames with the aim held |
| `test_tps_camera_behind`, `test_stick_look`, `test_camera_user_settings` | the key, the stick, the settings |

`tools/runtime/trace_camera_tight.gd` walks six spots of the real 727 (turn, rest, pitch, back into a wall,
walk along one) and writes `trace.csv`; it runs headless in about 80 s. Headless draws a square frame, so
screen positions in it are not those of a 16:9 game: `test_tps_camera_framing` computes its own.

The residual 0.37 m frame step in `test_doorway_camera` (yaw swing) is the boom meeting a jamb under a
sudden 150 deg/s swing; a cap that comes down at a steady speed was tried and was worse (0.60 m).
