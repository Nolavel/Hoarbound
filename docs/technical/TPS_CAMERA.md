# TPS camera

Owner: Claude (`claudeflow`). Story: #170 and the doorway pass after it. Code:
`scripts/systems/camera/`, `scripts/environment/passage/`,
`scripts/actors/player/henry/components/passage_traversal_component.gd`.

The gameplay camera is an over-the-shoulder follow camera in the line of
Naughty Dog's player cameras (Uncharted 3, The Last of Us Part II) and Rockstar's
Red Dead cameras. Neither studio has published its camera-collision code, so the
method is assembled from what they presented, plus the shipped open
implementations it reduces to: Epic's Lyra, Unity Cinemachine and Daedalic's
Unreal Fest sample.

## What the player gets

- **Mouse look lands in the same rendered frame.** Look is never filtered and is
  never tied to the physics rate.
- **Henry and the camera move smoothly at any refresh rate.** This comes from
  physics interpolation.
- **Walls never put the camera inside geometry.** A wall between camera and
  Henry snaps the camera in front of it at once (Red Dead's "snap through"), and
  the camera eases back out.
- **Thin things never move the camera.** Posts, planks, trunks, people and loose
  props let the boom pass; when they cross the view they turn see-through.
- **Freedom of view is not a guaranteed physical orbit.** The mouse always
  turns the view. Where walls leave the camera body less room, in a doorway, it
  orbits less, and the view may look past it only while Henry stays in frame.
- **A doorway is composed before the jamb, and Henry never dithers in one.**
  Approach, pre-compress, guided passage, soft release. Past the threshold the
  traversal carries Henry clear of the frame even with the keys let go. His near
  parts dither out only as a last resort, where geometry leaves no room at all
  (head, shoulder, pack; the legs stay).
- **The mouse owns where Henry walks.** WASD turns by the control yaw, and only
  the mouse (or `set_look`) changes it.
- **The camera turns by itself only after the mouse has rested for 0.9 s**, and
  only as a view offset: it finds room, follows a walk behind Henry, or steers
  away from a wall. The next mouse motion makes the view the player sees the new
  control yaw, so nothing jumps.
- **Breathing is presentation only.** Gameplay rays (interaction, boarding,
  bedroll, cursor) use `TpsCamera.aim_origin()` and `aim_direction()`, which
  leave the sway out.

Author decisions (2026-10-01, #170): walls snap and thin or small things fade;
the camera recentres behind a walking Henry; mouse response is P0.

## Frame order

`TpsCamera._process` runs every rendered frame:

1. `player.get_global_transform_interpolated()` gives the target. If the target
   jumps more than `teleport_distance` in one frame, the camera snaps.
   `snap_to_target()` does the same on demand.
2. `InputSystems.consume_look_delta()` returns all mouse travel since the last
   frame. It reads `screen_relative`, so the stretch mode cannot rescale look.
3. The stance is read from Henry's capsule. Where its height sits between the
   measured standing and crouch heights picks the framing heights from
   `HenryMetrics`, and the feet stay on the ground.
4. The rods judge how open the space is, every frame, which sets the boom
   length. They cover the camera's half of the circle (straight back weighs
   most) and the ceiling over Henry, so a wall in front of him does not count.
5. The passage blend is set from Henry's `PassageTraversalComponent` (below),
   before the mouse is applied, so the soft stop reads this frame's doorway.
6. The rig is swept (below), then the fades are updated.

**Priority stack.** A lower layer never undoes a higher one.

| # | Layer | What it owns |
|---|---|---|
| 1 | Teleport / load safety | snap, no smoothing |
| 2 | Passage | blend, cone, shoulder share, boom cap, rise, FOV; turns auto-look off |
| 3 | Hard wall collision | sphere sweeps snap the boom in |
| 4 | Mouse | the control look; soft stop only at the passage's limit |
| 5 | Shoulder framing | side, lean, recompose to the centre line |
| 6 | Adaptive distance | openness rods |
| 7 | Auto-look | room search, recentre, whiskers; only after the mouse rests, never in a passage |
| 8 | Breathing | presentation only |

The body fade is not a layer. It is the last resort when 1–6 still leave the
camera inside Henry's reach.

**Spaces.**

| | Open ground | Interior (roof over Henry) | Narrow passage |
|---|---|---|---|
| Boom | up to 3.0 m (rods find room) | shorter: the ceiling rod and walls lower openness | 1.4 m less wall depth past 0.2 m, at least 1.0 m |
| Shoulder | 0.85 m | shrinks with the boom to 20 % | within half the free opening round the centre line |
| Physical orbit | free | free; walls snap the boom | cone from the opening |
| Auto-look | recentre only matters | whiskers, room search after rest | off |
| Recompose | — | when the centre line gives more room | same |

Interior has no separate parameter set: it falls out of the rods and the ceiling
cast. If testing shows it needs its own tuning, it gets its own profile.

The camera node opts out of physics interpolation. Teleport sites call
`reset_physics_interpolation()`: world spawn, sitting down and save load.

## Control and view

Unreal's split: `ControlRotation` drives the pawn, and camera modifiers change
only the view.

- `_yaw`, `_pitch_deg`: the control look. Only mouse travel and `set_look()`
  change it. `get_yaw()` returns it, and `Player._camera_relative()` turns WASD
  by it.
- `_auto_yaw`, `_auto_pitch_deg`: the automatic offset. The view is control plus
  offset (`get_view_yaw()`, `get_view_pitch_deg()`).
- The **orbit** is where the camera body stands, separate from the **view** it
  looks along. Outside passages they are equal. In a passage the orbit is the
  view clamped into the doorway's cone. The drawn rotation stays the view, so the
  mouse never loses a degree to the geometry.
- On mouse travel the offset folds into the control look, so the player takes
  over the view they see without a jump.
- While movement keys steer, the recentre target is zero and the offset glides
  back to the control look. WASD stays on the control yaw throughout.

## The rig

```
Henry (interpolated) ── feet (from the capsule)
  └─ safe point: on the capsule axis, under its top by the probe radius   [Lyra]
       └─ leg 1, sphere sweep, nothing passes ─▶ shoulder point            [Cinemachine "hand"]
            (pivot = feet + lead, lagged; + Henry's shoulder joints and the doorway rise;
             + shoulder/lean offset)
            └─ leg 2 ─▶ camera
                 centre: sphere sweep, thin things pass        → hard limit, snaps in
                 feelers: ±16°, ±32° yaw, +20°/−20° pitch rays  → soft limit, eases in
                 any release eases back out                    [Lyra DistBlockedPct]
                 camera overlapping a blocking body            → pull in; thin ones only fade
```

- **The safe point** sits inside Henry's own capsule, so a cast from it never
  starts inside a wall or a low ceiling. Under a 1.5 m slab, a crouched Henry's
  safe point is below the slab and the camera stays under it.
- **The shoulder is a real offset**: 0.85 m, shrinking to 20 % in tight space.
  A wider tight shoulder (45 % was tried) swings the boom onto the door jamb
  when walking through a doorway: 2 pops and 0.41 m instead of none and 0.82 m.
  The old `h_offset` "lens shift" was a translation that no cast saw
  (`Camera3D._get_adjusted_camera_transform`).
- **Feelers** (weights 0.75, 0.5, 1.0, 0.5): a hit at share `t` limits the boom
  to `t + (1 − t)(1 − weight)`. They pull the camera off a wall before the
  centre sweep would have to snap.
- **Follow lag trails only the orbit centre**: 16 across the ground, 10 in
  height. The orbit itself answers the mouse with no lag.
- **One smoothing per quantity.** The lag follows Henry's feet. The framing
  heights (stance, doorway rise) are added after it, each eased by its own
  exponential damp `1 − exp(−rate·Δt)`, ADT's `damp_factor`. A crouch or a
  doorway is never smoothed twice.

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

## Doorways (`PassageInfo`, `PassageTraversalComponent`, `TpsPassageFraming`)

Author's direction (after #170): Hoarbound's camera is not a 360° orbit that
must survive any geometry. In a normal door Henry never dithers. The order is
**approach → pre-compress → Henry stays visible → guided passage → soft release**,
never collision → collapse → fade.

### Where the passage comes from

`PassageInfo` holds, in world space:
- the door plane centre at floor height, the axis, the clear width and height;
- the wall depth, which places the safe exit points either side;
- the shoulder (player's, left, right, centre);
- optional yaw limit, camera distance and FOV.

1. **Authored** (preferred). A `NarrowPassage` node (origin on the floor in the
   middle of the opening, local Z across the wall), or an unlatched `HingedDoor`.
   The door derives it from its own frame, `opening_size` and `wall_thickness_m`.
   An open leaf takes its thickness off the hinge side. A latched door is no
   passage.
2. **Raycast guess** (fallback for unmarked geometry). Facing jamb rays find the
   gap, as before, and a corridor is still no doorway. It now steps along the axis
   to find where the jambs start and end, so the plane and wall depth are measured.
   Before, the guessed centre moved with Henry.

### Henry: `PassageTraversalComponent`

All distances are from the wall face, with Henry's capsule (r 0.5) as the body.

| State | When | What Henry does |
|---|---|---|
| Known | within reach + 1.5 m | nothing; the camera may frame a door it is backing into |
| Engaged | a key pushes toward the plane (≥ 25 % along the axis) within 1.0 m + 0.3 s × speed, or Henry stands in the frame | steered onto the centre line, bend full near the plane |
| Committed | engaged, a key along the axis, centre within 0.15 m of the wall face | carried along the axis: lateral input dropped, S reverses, released keys carry him on |
| Done | capsule 0.3 m clear of the far face (0.9 m from the plane for a 0.2 m wall), or stalled 0.5 s with no key | stops; no autopilot |

- An approach with no key held lets go after 0.5 s. Stopping short of the
  threshold leaves Henry where he is, and the camera opens back out.
- Only the player's own keys commit. The Hub, a working action and a scripted
  walk (`move_to_position`) never do; `Player` passes that in.
- No teleport: speed, animation and collision are the normal walk.

### Camera: `TpsCamera` with `TpsPassageFraming`

**Blend.** It is 1 while Henry's capsule or the boom behind him is in the frame.
It falls over 1.0 m of space, plus 0.3 s × speed, ×1.5 at a 90° approach. The
space is measured from Henry on his way in, and from the predicted camera on its
way out or when it leads Henry backwards. The prediction uses the passage boom,
not the current one, so the blend never feeds itself. Before Henry engages, only
a boom running along the axis into the opening counts, so walking past a door
along a wall leaves the camera alone. It closes at rate 8 and opens at rate 3.

**Composition, all derived from the passage:**

| | Rule | Shelter door 1.46 × 2.25, wall 0.2 |
|---|---|---|
| Boom | `passage_boom` 1.4 less wall depth past 0.2, ≥ 1.0; authored distance wins | 1.4 m |
| Shoulder | player's side, kept within `band × 0.5` round the centre line (band = half width − 0.3) | ≤ 0.22 m; slides across when Henry is off-centre |
| Rise | ≤ 0.15 m and ≤ half the room under the lintel | 0.15 m |
| FOV | +5° (authored wins), total ≤ 80° | 75° |
| Orbit cone, yaw | the boom keeps within the band to the far face, or to its tip if shorter: `max(atan(room/depth), asin(room/boom))` per side | ~90° in the plane, ~18° with the boom fully through |
| Orbit cone, pitch | same, against the lintel (−0.3) and the floor (+0.3) | ~17–45° elevation |
| View yaw soft stop | cone + (half horizontal FOV − 8°); an authored yaw limit caps it | ≥ 60° at 16:9 |
| View pitch soft stop | cone + (half vertical FOV − 8°) | |
| Auto-look | off; any standing offset glides out at 120°/s | |

- **The cone closes at once and opens softly** (release rate 3). It ramps in
  over 0.5 m as the boom tip nears the wall, so it never snaps in or out in one
  frame.
- **The mouse is never blocked.** It eases into the soft stop over 10°, and
  looking back in is always free. The control yaw changes only by the mouse.
  Once Henry and the camera are clear, the cone and the stop are gone.

### Recompose before fade

When the camera, after walls, would sit closer than 1.1 m to Henry's eyes, it
compares two booms with stateless casts in the same frame: from the shoulder,
and from the centre line. If the centre line gives at least 5 cm more room, the
shoulder gives way to it, fully at 0.8 m, with +3° FOV. It goes in at rate 12
and out at rate 2. With Henry's back to a wall the centre line is worse, so
nothing changes. Only then does the body fade, as before.

### Tight-space composition

Author's reference (2026-10-20): in a tight space Henry sits at the left of the frame
(right shoulder; mirrored on the left), eyes at 27 % of the width, so the room stays
readable. References: Cinemachine Third Person Follow (rig shape set by state, walls only
shorten the arm), Jacob Grossman's framing (NZGDC 2025: offset = framing × half-width at
the distance) and John Nesky's "50 Game Camera Mistakes" (GDC 2014: never fight the player).

- `_composition` comes from `measure_room()`: rods all round Henry, evenly weighted, so
  turning the camera never changes it. The boom keeps the view-based `measure_openness()`.
- Shoulder offset = `_boom × tan(eye angle)` from the real FOV and aspect: it scales with
  the boom, so Henry's screen spot holds while the boom breathes. Pitch does not move it.
- In a doorway the passage owns the framing; the composition gives way by `_passage_blend`.
- No lens shift: aim and walk always share the screen centre. Where a wall stops the
  shoulder, Henry honestly comes towards the centre (the rig bends).
- Above `tight_auto_look_cutoff` no room search or whiskers turn the view.
- `recompose` eases at 4 in / 1.5 out and keeps its goal until it moves by
  `recompose_hysteresis`.
- The doorway mouse soft-stop and view clamp apply only while Henry is in the doorway or
  walking at it (`_passage_traversal`); standing beside one the mouse is free.
- `get_composition()` is read by Quick Access, which then gathers its cards in a cross at
  the screen centre.

Measured with `tools/runtime/trace_camera_tight.gd` (727, full mouse turn): at the stove
the composition held 0.58–0.59 (was 0.50–0.80) and Henry's eyes 32–33 % (were 26–30 %);
the corridor turned the full circle (the mouse stuck at −81°, see passages below); the
automatic turn stayed at 0 (was up to 30° in a corner). Known limit: facing a wall in a
1.8 m corridor or a room corner the shoulder has no room and the camera comes close to
Henry, who fades.

### Shoulder lift

Back to a wall or in a corner the camera climbs over Henry's shoulder instead of pressing
into him (close quarters in God of War and The Last of Us). `_lift` follows how little
level room is behind Henry along the view (`_update_lift`, cast from inside him, so the
lift never changes the room it reads): full at 0.3 m, gone at 1.0 m, rates 3 in, 1.5 out.
At full lift the camera body climbs 70° up the orbit and the pivot rises up to 0.3 m under
the ceiling, while the view tilts only 35°: Henry sits low in the frame, the room ahead
stays visible. Yaw is untouched, so walking still follows the mouse; a doorway turns the
lift off. Measured in the 727 corner (full turn): Henry's head off screen in 1 frame of
240 (was 51), the camera closer than 0.8 m in 43 (was 121); facing the corridor wall
0 off screen (was 25).

### Body guard (no see-through Henry)

Author's rule (2026-10-20): Henry is never see-through in play. Many shipped games fade
the character (Witcher 3, A Hat in Time's geometry dithering); here the camera is kept
out of him instead, with Nesky's soft wall:

- Before each mouse step `_body_guard` predicts, with stateless casts from the last frame's
  pivot, shoulder offset and lift, how close the camera would come to the eyes at the new
  yaw or pitch. Closer than `guard_soft_distance` (0.8 m) the step is scaled down, at
  `guard_eye_distance` (0.6 m) it stops. Turning out of trouble is always free.
- Walking presses the camera too, where the guard cannot act: the lift then climbs up to
  4x faster (`_pressed`).
- The composition offset uses the distance the camera really has (`_dist_pct`), so a
  pressed camera keeps Henry on his spot instead of pushing him out at the side.
- Over the shoulder the view tilts down as far as Henry's eyes need to stay
  `shoulder_lift_frame_margin_deg` inside the lower edge, from where they really are.
- The body fade starts at 0.45 m (was 0.8 m), an emergency only; recompose keeps its own
  0.8 m (`recompose_full_distance`).

727 trace with S held into each wall or corner added: frames with Henry faded 0 in every
phase (were 42 corner turn, 59 corner pitch, 55 corridor turn, 26 restroom back-in). The
mouse is held off 41–47° of a full turn in the corner and the corridor. Known limit: backing
into the 3.6 × 2.8 m restroom wall the camera can only sit almost above Henry, and his
eyes touch the lower frame edge for 11 of 75 frames.

### Rooms frame Henry low-left; auto shoulder (2026-10-21)

- Any room counts as tight (`composition_open_share` 0.85, was 0.5) and the camera rises
  along its own up axis until Henry's eyes sit at `composition_eye_screen_y` (0.5 of the
  height), on the real camera distance, fading out as the player looks up (Grossman's
  pitch curves). 727 stove: eyes at 29–30 % / 46–47 % (were 33 % / 37 %), so the body
  no longer blocks the middle of the room.
- Auto shoulder: with the player's side under `swap_blocked_share` (0.7) of the offset
  free and the other side `swap_margin` (0.35) freer for `swap_after_s`, the camera
  crosses; it comes back after `swap_back_after_s` with its own side over
  `swap_free_share`. Never in a doorway and never while the mouse turns (Ghost Recon
  Breakpoint players switch theirs off because it fights them); `auto_shoulder_swap`
  turns it off. References: Sifu, a Borderlands 4 camera mod (which had to stop it
  swapping in every doorway). 727 corridor walk along a wall: crossed after ~0.4 s, Henry
  mirrored to the right; before he left the frame for 8 frames.
- Cinemachine Deoccluder's strategies map to this rig: pull forward = boom collision,
  preserve height = shoulder lift, preserve distance = auto shoulder. Its Smoothing Time
  is `collision_hold_time`, off by default: any hold (boom, boom while walking, lift)
  kept the camera in Henry longer in the trace (fades 0 → 8 backing into a wall) and
  blocked the shoulder cross.

## Open items (camera, 2026-10-21)

Found with `tools/runtime/trace_camera_tight.gd`, not yet solved:

- Backing into a wall in the 3.6 × 2.8 m restroom, and turning in the exam-room corner,
  the camera can only sit almost above Henry: his eyes touch the lower frame edge (13 of
  75 back-in frames, 22 of 240 corner-turn frames). Candidate: authored camera hints for
  tiny rooms, Cinemachine ClearShot style (a few placed shots, best one by shot quality;
  Nesky: hints matter most in small closed spaces).
- Turning next to a corridor wall still fades Henry for 7–8 of 240 frames: the body
  guard's stateless prediction and the smoothed rig disagree for a moment.
- Body guard thresholds (0.6 / 0.8 m), lift (70° body, 35° view) and auto-shoulder
  timings are untuned by hand; only trace numbers so far.
- `test_doorway_camera` still fails two checks it failed before this work (yaw_swing
  one-frame pops 0.68 m, stand_sweep_30 Henry off screen).
- `collision_hold_time` is available for hand tests but measured worse at every value tried.

## What stops the boom

`TpsBoomProbe.passes()` decides this per collider shape:

| Collider | Boom |
|---|---|
| Static or animatable body whose middle extent ≥ `thin_extent` (0.6 m): walls, doors, ground, buildings | stops; snaps in |
| Middle extent < 0.6 m: posts, poles, planks, trunks, small crates | passes; visuals fade |
| `CharacterBody3D` (NPCs, animals) | passes; visuals fade |
| `RigidBody3D` that is not frozen | passes; visuals fade |
| Frozen `RigidBody3D` | judged by size, like a static body |

This rule is derived from collider data, not from layers, so new content works
without tagging. One cast passes at most 16 such colliders (`MAX_PASSES`); the
next one counts as a wall. A long row of props therefore can never hide a wall
behind it: it fails toward the camera coming in, not toward it going through. If a level needs an invisible camera blocker (Unreal's Camera
Blocking Volume), a wide static body on a camera-only layer does that job.

## Automatic turns (`TpsAutoLook`)

All of them wait `auto_look_cooldown` (0.9 s) after the last mouse motion and
move only the view offset, never the control yaw.

- **Room search** runs when Henry stands still and the free boom is under 0.7 m.
  It looks for the cheapest view turn that gives room, rising over Henry before
  swinging along the wall (cost = yaw + 0.8·pitch), and glides there at 120°/s.
  The offset stays until the mouse takes it over or Henry walks off.
- **Recentre** runs on a walk no key steers (an F approach): the view follows
  Henry's heading at up to 90°/s at full sprint, unless he walks toward the
  camera (more than 110° off). While keys steer, its target is zero.
- **Whiskers** (Daedalic): booms swung ±20° and ±40° compare the room on each
  side, and while Henry moves the view leans toward the open side, up to 30°.

## Fades (`TpsCameraFader`)

- **Henry:** `camera_fade` is an instance uniform in
  `stylized_environment_body.gdshaderinc`, applied as a 4×4 Bayer screen-door
  discard. It ramps from 0 at 0.8 m from the eyes to 1 at 0.25 m. Each fragment
  is weighted by its own distance to the camera: full under 0.35 m, none past
  1.1 m. So the head, shoulder and pack go and the legs stay. The material stays
  opaque, so there are no sorting problems; his shadow dithers with him. Meshes
  without the stylized shader fall back to `transparency`, capped at 0.7.
- **Occluders:** the thin colliders on the camera-to-eyes line get
  `GeometryInstance3D.transparency` 0.7, and so do thin colliders the camera
  sphere sits inside. It eases in over 0.12 s and out over 0.35 s. Meshes wider
  than 1.5 m in their middle axis are never faded.

## Measuring it

- `tools/runtime/trace_tps_camera.gd` loads TestScene with the real Henry and
  drives the mouse and keys at `--fixed-fps 144` against 60 Hz physics. It
  records every frame against the render position and the `Head` bone: inside a
  collider, near-plane clipping, head occluded, body faded or hidden, and pops.
  Output: CSV and `summary.json` under `user://traces/tps_camera/<label>/`.
- `tools/runtime/capture_tps_camera.gd` takes the same stills for any camera
  build (lavapipe): `user://shots/tps_camera/<label>/`.
- `tools/runtime/capture_tps_doorway.gd` grabs the Key West shelter door at
  entry, middle and exit (straight, 35° off, and stopped with the mouse turned
  aside): `user://shots/tps_doorway/<label>/`. No frames were rendered for
  the doorway pass; the author reviews it locally.
- `tools/runtime/measure_henry_metrics.gd` rebuilds `HenryMetrics`.
- `tests/systems/test_doorway_camera.gd` is the doorway acceptance test, on
  the real Key West shelter door (1.46 clear with the leaf open, 2.25 high, wall
  0.2). It runs 12 scenarios:
  - W straight; W 35° off; stop 0.7 m short; W released past the plane;
  - W in, then S from the plane; S backwards from inside, camera leading;
  - hard mouse yaw ±100–200° inside; mouse pitch down and up;
  - left shoulder; crouched; leaf 40° open;
  - standing in the plane with 360° sweeps at −10/−40/+30.

  Every frame must have:
  - no dither, no camera inside geometry, no near-plane clip;
  - the head unoccluded and Henry in the frustum;
  - no pop (over 0.15 m in a frame and faster than 6 m/s);
  - FOV under 45°/s, and the control yaw turned only on mouse frames.

  After a traversal Henry must rest 0.6 m clear of the plane, and 90° of mouse
  must turn the yaw exactly 90°. Add `--fixed-fps 144` and a label for per-frame
  CSVs under `user://traces/tps_doorway/<label>/`.

### Doorway pass after #170: before

Key West door, `trace_tps_camera.gd shelter` at 144 fps, standing in the plane
with a 360° mouse sweep, on `c715600` before this pass:

| Pitch | Frames dithered | Max fade | Closest to the head | Largest one-frame pull-in |
|---|---|---|---|---|
| −10° | 192 / 432 | 0.79 | 0.33 m | 0.63 m |
| −40° | 158 / 432 | 0.88 | 0.30 m | 0.78 m |
| +30° | 84 / 432 | 0.18 | 0.66 m | 0.02 m |

After: not measured here. The author runs `test_doorway_camera` and the traces
locally; record the after column from that run.

Before (`a604f60`) → after (#170, with the review fixes), TestScene at 144 fps:

| Measure | Before | After |
|---|---|---|
| Frames where the view turns under continuous mouse | 42 % | 100 % |
| Lag behind the mouse at 129°/s | 30 ms | 0 |
| 13° flick: 90 % reached | 76 ms | next frame (7 ms) |
| Walking: camera step cv | 1.18 | 0.008 |
| Walking: Henry's drawn step cv | 1.18 | 0.012 |
| 360° sweeps, 8 poses × 3 pitches: frames with Henry cut out | 1865 | 0 (near parts dithered instead) |
| Doorway sweep: closest to the eyes | 0.22 m | 0.29 m |
| Leaving the door: near plane clipping the jamb | 36 frames | 0 (one 0.43 m wall snap on the jamb) |
| Sideways door pass: Henry cut out | 246 frames | 0 (near parts dithered, at most 0.72) |
| Sideways door pass: largest one-frame pull-in | 1.37 m | 1.05 m (wall snap, by decision) |
| Crouching: camera drop (head drops 0.68 m) | 0.00 m | 0.50 m |
| Under a 1.5 m slab: frames with the head hidden by the slab | 414 (31 %) | 0 |
| Thin pole: boom pops | 3, up to 0.95 m | 0; the pole fades |
| Teleport into the shelter | 1.3 s flight | snap |
| Back to a wall, mouse moving: view turned by itself | 74° at once | 0.1° (the test jiggle) |
| Back to a wall, mouse at rest: view turn | — | 60°, starting 0.9 s after the mouse stops |
| Then W: walking heading against the mouse's control yaw | 74° | 0° |
| Scripted walk 60° off: view / control yaw | — | 60° / 0° |
| Strafing with D: heading against the mouse's right | — | 0° |

Key West, the real shelter (1.5 m door), same harness with `scene=` and the
`shelter` scenario:

| Measure | Before | After |
|---|---|---|
| Scripted walk from the porch through the open door into the room | clean (closest 1.14 m) | clean (closest 1.18 m) |
| Doorway sweeps at pitch −10/−40/+30: frames with Henry cut out | 63 / 51 / 87 | 0 / 0 / 0 (dithered, at most 0.87) |
| Doorway sweeps: near-plane clips | 12 / 0 / 15 | 0 / 0 / 0 |
| Doorway sweeps: pops over 0.3 m | 4 / 2 / 0 | 1 / 1 / 0 |
| Doorway sweeps: closest to the eyes | 0.49 / 0.50 / 0.46 m | 0.31 / 0.31 / 0.62 m |

The camera now comes closer in the doorway. The old assist swung it away even
while the player aimed; the new one leaves the aim alone and dithers Henry.

Frames: `docs/runtime_previews/tps_camera/` holds before/after sheets from
`capture_tps_camera.gd` (lavapipe, 960×540). The poses are: doorway with the
mouse moving and at rest, corner aimed and at rest, crouched under a slab, a
thin pole, leaving the shelter, and open ground. With the mouse moving, the old
camera had already swung away from the player's aim; the new one holds the aim
and dithers Henry until the mouse rests.

## Known limits

- **There is physically no room for the camera beside Henry in a 1.2 m doorway**
  (capsule radius 0.5 m). The cone holds the camera body near the axis, and the
  view looks past it. 1.2 m is a stress test only: no break, no clip, control
  kept. Visual quality is judged on the production door.
- **The doorway standard is not fixed yet.** The tests cover 1.45 × 2.20 and
  1.60 × 2.30 with authored passages and the real 1.46 × 2.25 shelter door. Fix
  the Hoarbound standard after the author's run.
- **The capsule (Ø 1.0 m) is much wider than Henry (0.60 m).** His coat stops
  0.2 m short of a wall, and the pack (0.54 m behind his axis) reaches 4 cm past
  the capsule. That is a separate task, not camera tuning: it covers the feeling
  of walking into air, doorways, wall contact, stairs, the door leaf and the pack.
- **A partly open leaf is not in the passage data.** Henry pushes it as before,
  and the boom treats it as a wall until it swings clear.
- **A wall between camera and Henry still snaps the boom**, by decision. In a
  doorway the cone keeps the boom off the jambs, so normal passes should not
  snap at all.
- **While an automatic view offset stands, W walks along the control yaw, not
  the screen centre.** That is the price of WASD never following automatic
  turns. The first mouse motion folds the offset in, and steering keys glide it
  back out.
- **In a passage, W walks along the control yaw even when the camera body sits
  off it.** The view and WASD stay on the mouse; only the camera position bends.
- **Space queries run in `_process`.** That is safe while physics runs on the
  main thread (the project default).
- **Occluder fades use the transparent pipeline** while they are active.
