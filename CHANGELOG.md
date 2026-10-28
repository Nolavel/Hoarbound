# Changelog

Short record of notable production changes. Newest first.

The previous long-form development diary is preserved unchanged in [`archive/CHANGELOG_LEGACY.md`](archive/CHANGELOG_LEGACY.md).

## Unreleased

### Added

- Weather profile `clear` (no wind, no snowfall) for tests and captures. It is `manual_only`: it is set only by
  `set_weather`, never drawn by the weather roll (`WeatherProfile.manual_only`, `_pick_weighted` skips it).
- SPoV canned meat (owner's artist asset, `assets/source/spov_canned_meat/CanModel.rar`). `tools/blender/build_spov_can.py`
  builds `assets/items/spov_can/SPoV_Can.glb`: 10.4 x 6.1 x 7.1 cm (a 340 g luncheon-meat tin, the artist's proportions
  kept), 356 + 240 tris. The 40 lid-seam edges shared by three faces are split, and the pull ring is laid flat on the
  recessed lid at one end. The painted label is matte paper: the source Metallic map marked the whole surface metal,
  so the label is masked out of it. Items `spov_can` → `spov_can_open` follow the pineapple contract, with no tool
  needed: the first Use pulls the ring, the next eats 1,070 kcal (340 g x 3.15 kcal/g). The open can hides the ring
  and shows the meat. Owner: the emptied can is thrown on the floor. A new `ConsumableData.discard_leftover` tosses it
  as a falling body (`ConsumptionController.leftover_discarded`) instead of keeping an inventory item. No ring-pull animation yet; opening plays the existing `fix` action. One can lies on the
  bottom shelf of the 727 waiting-room cabinet, label to the door. The open-tin hint now names the ring or the knife
  (`ConsumptionController.open_action_key`). Test: `tests/systems/test_spov_can.gd`. Capture:
  `tools/runtime/capture_spov_can.gd`.
- Held lighter flame on RMB (`present_held`). While RMB is held, Henry raises the lighter before his chest
  (a second `StoveHandReach`, `PresentReach`, palm turned in), and after 0.3 s the flint wheel rolls and the flame lights.
  The lighter stands upright in the fist while raised; on release its authored HeldFit returns. The flame burns while RMB
  is held but goes out after 10 s anyway; a fresh press lights it again. The flame is now one node, `LighterFlame`,
  shared by the held lighter and the stove act. Capture: `tools/runtime/capture_held_lighter.gd`.
  Lowering fix (owner report: the hand jerked before letting go): the raised fist now keeps the hanging wrist
  roll (thumb up), so the hand no longer turns over at half weight. The arm eases down over 0.4 s. The lighter
  turns from upright back to its HeldFit in the hand's frame, so it no longer flips. Measured by a per-frame
  trace of the hand bone's roll axis.
- Authored lighter model (`assets/items/lighter/Lighter_game_ready.glb`, owner's asset) replaces the orange box
  everywhere: world pickup, held prop and the stove lighting act. `LighterStrikeVFX` holds it with the grip at the
  origin and the burner nozzle on its +Y axis; the flint wheel rolls on each strike. The flame is a tongue mesh with
  the stove log-flame shading (blue root, yellow body, view-facing edge, faded tip, `lighter_flame.gdshader`). It
  pivots on the nozzle and always burns world-up whatever the hand's tilt. At the stove the nozzle sits 12 mm under
  the tinder so the flame's middle licks it. Close-up capture: `tools/runtime/capture_lighter.gd`.
- Work gloves you can find and wear (#236, owner: the 727 cabinet). `tools/blender/build_henry_outfit.py` cuts
  `Outfit_Gloves` from the hands and fingers, from the wrist up under the sleeve, in dark leather brown. They are
  decimated to about 6,000 vertices and hide `Skin_Gloves` while worn. The pickup lies on the top shelf of the
  727 cabinet beside the mug (`GlovesShelter`), with a blocky pair as its world prop. The outfit now rebuilds with
  Blender 5.2 (`pip install bpy`); the previous meshes come out vertex for vertex.
- Wall thermometer in the 727 waiting room (#236), just inside the lobby arch (`WallThermometer`, nail at 1.7 m, placed
  from the landmark spec's furniture list). It is an ordinary glass thermometer on a board, hung by a wire loop from a nail, with a red column from −40 to +40 °C; the figure
  (`THERMOMETER_READING`, °C only) sits on a grey gradient plate below it and fades out between 2.5 and 3 m from Henry.
  It reads outdoor air plus its zone's warmth; the column and figure follow it smoothly. No interaction.
- Stove fire per log, ported from the `codex` branch (Codex's work, finished here). Each log has its own
  irregular geometry, char, flame and embers, plus weak ignition smoke. Henry's arm reaches in through
  `StoveHandReach` to take, insert and release each item. Tinder comes only from a Quick Access pocket or
  the hand, not the pack. Log poses and char origins survive save/load and refuel. `HeatSource` stays the
  only authority on fuel and heat. Codex's 11 MB of capture media stayed on its branch.
- Frostbite consequences (#236 stage 6, owner direction). Each body part gets frostnip, then frostbite, after
  its cold load is held long enough (0.6 for 20 min; 0.85 for about 36 min). The stage heals in warmth
  (frostbite over 6 h) and is saved. Six afflictions carry the effects:
  - numb hands slow fine work, so the lighter hold grows from 3 s to about 5 s and laying fuel takes longer;
  - frostbitten feet slow walking and allow no sprint;
  - frostbite drains health (4–5 per game hour, through the new `PlayerHealthSystem.drain`, without hit feedback).
  The modifiers reach movement, actions, fatigue and the stove through the new `StatusModifierCapability`;
  the three existing string-call readers moved onto it. `test_frostbite` covers stages, healing, afflictions,
  health, sprint, the lighter and gloves.
- Work gloves: a `hands_outer` slot and the `work_gloves` garment (insulation 4 °C, windproof 0.6). There is no
  visual mesh yet (needs a Blender outfit pass) and they are not placed in the world.

- Body part library (#236): `BodyPartDefinition` / `BodyPartLibrary` (`core/body/`, `data/body/`) describe the
  head, hands and feet. Each has its garment region, wind exposure, cold sensitivity, cold thresholds, HUD mask
  and bones. `ExtremityCold` and the HUD silhouette read the library instead of hard-coded regions.
  Wind now reaches each part by its own exposure and its cover's windproofing: the face takes the whole wind,
  booted feet about a third. A new part is data only. `test_cold_readouts` covers the library, the wind split
  and a data-only part.

- Daily air temperature (#236 stage 5): `ThermalManager` uses `data/climate/air_temperature_day.tres` when no
  curve is assigned (world.gd creates it in code, so it always ran flat at −18 °C). The air is coldest at
  05:30 (−28 °C) and warmest at 14:30 (−8 °C), with weather offsets on top. `test_cold_readouts` checks the
  extremes and the midnight wrap.

- Vitals HUD rework (owner design, #236; spec in `docs/technical/VITALS_HUD.md`). The round progress rings
  are replaced by gradient columns: a dark column fading upward and a state-tinted pigment over it that
  empties from the top, with a thin edge line and rounded bottom. Green, yellow and red blend across each
  threshold. The symbols stay half-tone until a vital nears critical. Trend chevrons sit above a rising
  column and below a falling one, doubled for a fast change. Body temperature and `FEELS ±N°` sit beside
  the warmth column. A faint front silhouette stands over it and frosts blue from the fingertips, toes and
  crown with the new extremity cold load. The block moved toward the corner: smaller columns, a larger
  health strip (260 × 16).
- Extremity cold (`ExtremityCold`, `ThermalManager.get_extremity_cold`): a 0..1 load on the head, hands and
  feet from felt cold, that region's garment insulation and its wetness (`EquipmentComponent.get_region_protection`).
  It is saved, warm sleep clears it, and it is a warning layer only.

- Floor snow prints (owner request): indoors Henry's boots leave white prints, the inverse of the snow print:
  white where the tread's grooves packed with snow outside, broken into clumps (`BootSole.floor_print_image`,
  the same lug pattern the snow shader presses). A step outside on snow fills the tread; each indoor step
  leaves 20 % of what it holds, so about ten prints fade out step by step, and the tread melts empty in about
  2 min in a 20 °C room. A print holds, then fades over its last half: 5 min in a 20 °C room, 25 min at
  0 °C (`FloorSnowPrints`, `test_floor_snow_prints`). The decal is a cube one sole long with the sole's
  shape in its texture: a thin, long decal box lost screen tiles of the print in Forward+ (seen on the 727
  floor; godotengine/godot#73945). The two prints bake in ~34 ms at load.
- Blizzard flow (`BlizzardFlow`, FUTURE_INTENT §10): blown snow as fog volumes on the wide streets
  (pavement ≥ 7 m, Key West's top ~15 % of road length) that run with the wind (|cos| ≥ 0.6, street-canyon
  channelling), up to six near Henry. Density is the blowing-snow extinction for the live 10 m wind, gusts
  included: Tabler's visibility V = 1.126e8·U^-4.85 m (TRB SR185) through Koschmieder 3.912 / V, capped at
  ~13 m visibility. It starts only past the snowpack's blowing threshold (5–10 m/s) with snow laid. Densest
  at the street and thinning with a 3 m scale height (body height); ~12 m billows with gaps and a 5 m tear
  octave advect downwind; volumes fade in and out over 2 s. Each billow core settles at the overcast it
  scatters (the environment ambient: Godot scales fog EMISSION by density), so the flow reads lighter than
  the air, not as dark bands as with a fixed 0.18 glow (measured at forced density). Flakes ride each
  volume and the ground streamers run along the flow streets, on screen only. Street centrelines come from the road ribbons `KeyWestRealityGround` already paves
  (`get_wide_streets`, `test_key_west_reality_ground`). The weather readout shows the flow.
- Key West mug model (owner request): `SurvivalItemVisual` draws `assets/items/mug/Mug_game_ready.glb` for the
  mug, mug of snow and warm water (held, world pickups, shelter cabinet) instead of the grey cylinder. The model is
  real scale (13 x 8.7 x 10 cm, base at 0); snow and water are a disc inside the measured 4.4 cm inner wall.
  Henry starts with the mug in the pack lid pocket instead of the pack, so one Quick Access pocket is free at start.
- Weather debug (debug builds, Key West), one key, 0. The first press shows the profile, scheduler or pin,
  blend, wind and drift gate, snowfall, visibility, cover, hour, sun beam, shelter state and the live streak,
  ground-drift counts. Each next press pins calm, snowfall, windy, blizzard in turn; the one
  after blizzard hands the weather back to the scheduler and hides the readout.
- Rooms frame Henry low-left (owner note): any room uses the tight composition and the camera rises until his eyes
  sit at mid-height (stove 29–30 % / 46–47 %, was 33 % / 37 %). Auto shoulder swap when the player's side is walled off
  and the other is free, with delays, never in doorways or during mouse turns (Sifu, a Borderlands 4 camera mod;
  Ghost Recon Breakpoint's complaints). Deoccluder-style hold measured worse and ships off. Open camera items are
  listed in `docs/technical/TPS_CAMERA.md` → Open items.
- Leeward wall drifts baked into the Key West wind map (owner request: the lee side of every house had
  deeper drifts, the windward side less).
  - `bake_key_west_snow_wind.py --reality`: ASCE 7-16 leeward drift per wall, height from the roof run along
    the wind (0.3–1.1 m at full cover, capped at half the wall), tapering over 4 hd; windward banks halved.
    `factor_max` 2.5 → 8.5. Chunk cover, clipmap rings and SnowField read the same map, so drifts are drawn
    and waded alike.
- Snow material and drift crests (testers: the snow read as jelly).
  - Causes, from close-up frames on Duval Street: no detail under the 2 m lattice and the ~0.7 m ripple, a
    near-uniform albedo (±3 %) and plastic specular, so shadowed snow was a flat blue fill; print floors drew
    topographic rings (`sin(depth × 110)` strata over lumpy floors) and glints were view-independent
    emission confetti. Deep trench walls showed agate rings; a debug render split albedo from normal and
    put them in the albedo: the shared painterly pass seeds its pigment noise with the surface normal,
    which on a curved trench wall sweeps through dozens of noise periods. Snow now passes the ground's up
    vector to that pass in both layers.
  - Now both layers share per-pixel grain on level snow (7 cm and 2.4 cm, each fading before a pixel spans
    it), albedo patches and grain hollows, ice facets that flash toward the sun in `light()` (none in shadow,
    none on packed floors), `SPECULAR` 0.3 and a cubic B-spline wind map for shading slopes. Print slopes use
    a three-texel Sobel without the outline jag; deep pits darken with depth; a boot's outline and tread are
    kept only on and around its sole, not where the wading body pressed deeper.
  - Lee drifts keep a trough at the wall foot (the lee eddy) and crest 3 m out, with only a 1-2-1 pass so the
    crest survives on the 2 m lattice; `factor_max` 8.5 so crests are not clipped.
- Snowpack firmness (owner request: furrows belong to fresh wet snow; a dry cold pack is a crust that breaks
  with difficulty, then the leg drops fast).
  - `SnowPresentationSystem.firmness` (saved): snowfall buries the crust, dry cold and wind harden it over a
    day, a thaw softens it. It sets the field's softness, crust strength and how deep and fast a broken crust
    drops; only loose snow (firmness < 0.5) lets the wading body and dragging toe cut a trench.
  - Tests in `test_snow_presentation`, `test_snow_resistance`, `test_snow_shell`; `snow-walk` CI runs both packs.
    Duval Street walk: fresh pack 3 plunges (drift pockets only), crust pack 29 with clean-walled postholes.
  - `snow-walk` reads the GPU print field under every standing boot (`SNOW_WALK_GHOSTS`) to chase the
    "walks through drawn snow without a mark" report: 0 of 509 boots in over 5 cm of snow left no print on
    this route, so the report is not reproduced here yet.
- Snowpack and boot prints (owner request).
  - `SnowResistance`: wind crust holds a boot until the step's load breaks it (strength varies in ~1.6 m patches,
    running breaks more), drifts hide soft pockets where a leg plunges almost to the ground; a plunge dips the
    stride and plays a crust snap. Collision stays on the ground. `test_snow_resistance`.
  - Prints are Henry's army boot outsole (`BootSole`): heel block, arched shank, ball, round toe, in both the
    persistent stamp and the contact soles. The packed field carries each print's sole uv, and `snow_ground` draws
    the exact outline and the lug tread per pixel.
  - `capture_snow_walk.gd` and the `snow-walk` job in `checks.yml`: TPS and leg-height videos of the walk.
  - Independent review (Sonnet agent + `/code-review high`): prints shade per pixel in coarse rings, narrower morph
    bands, no string `has_method`/`connect` seams, retry cap at the coast. It also caught that the wall lee ramps
    never ran over the baked map; they are now out of the drawn base until the chunk bake carries them.
- Henry is never see-through in play (owner rule). A body guard predicts where each mouse step would put the camera
  and soft-stops turns that take it closer than 0.8–0.6 m to his eyes (turning out is free); walking into a wall
  speeds up the shoulder lift; the framing offset follows the real camera distance; over the shoulder the view keeps
  his eyes inside the frame. The fade remains only as an emergency at 0.45 m. 727 trace: faded frames 0 in every
  phase (were up to 59). `docs/technical/TPS_CAMERA.md` → Body guard.
- Shoulder lift in corners (owner request): with little room behind Henry the camera climbs over his shoulder (70° up
  the orbit, view tilted 35°, pivot up to 0.3 m under the ceiling) instead of pressing into him. In the 727 corner his
  head left the frame in 1 of 240 turn frames (was 51) and facing the corridor wall in none (was 25).
  `docs/technical/TPS_CAMERA.md` → Shoulder lift.
- Tight-space camera composition (owner reference): Henry at the frame's left (eyes at 27 %) in cramped rooms, after
  Cinemachine Third Person Follow, Grossman's framing (NZGDC 2025) and Nesky (GDC 2014). Measured first with
  `tools/runtime/trace_camera_tight.gd` in 727: the composition followed the view (0.50–0.80 at the stove during one
  turn), a room search turned the camera 30° by itself, and the mouse stuck at −81° in the corridor. Now the
  composition reads room all round Henry (0.58–0.59), the shoulder offset scales with the boom (no lens shift, aim and
  walk share the centre), recompose eases with hysteresis, no automatic turns in tight spaces, and the doorway mouse
  stop applies only while Henry passes a door. `docs/technical/TPS_CAMERA.md` → Tight-space composition.
- Quick Access in tight spaces gathers in a cross at the screen centre (coats left/right, pack lid above, thigh below).
  The old diagonal orbit took each pocket's side from its projected anchor, so two pockets could land in one corner
  and overlap; places are now fixed and spaced from the real card sizes, and the cross is bounded as a whole.
- Stove fire burns unevenly (owner request). It catches small and grows with the `HeatSource` warm-up
  (0.08 -> 1 intensity, smoothstep): the firebox starts at 45%, the room light at 20%. At the nominal burn
  two Perlin layers replace the old sine product: a slow swell (~0.35 Hz, a little brighter or dimmer, never
  repeating) and fast flame jitter (~9 Hz); embers follow mostly the swell. Mean energies match the old ones.
  `test_stove_visual` now checks a dim catch and a nominal warmed burn.
- Interior shadow mode (owner request). Outdoors shadows keep the dry-brush edge. Under a shelter roof they
  return to the earlier value-noise edge (4186533).
  - `stylized_shadow_interior_mode` now feeds the shared shadow include and turns the brush mix down to 0.
  - `ShelterGradeBinder` fades it with the LUT, on `sheltered_changed` over `shelter_blend_s`.
  - 727 Fort St floor is dark old wood (`floor_old_wood_727.tres`), swapped for the glb `floor_vinyl` on import,
    so the stove shadows read on it.
- Colour grade crossfade (from Grok's `grok` branch).
  - Grok's rules are kept:
    - outdoor LUTs blend over ±0.5 h corridors at 05/07/17/21 h;
    - Shelter fades in and out over 0.5 s;
    - `blend_outdoor_profiles` and the capture tool.
  - His fullscreen blend pass is replaced. It graded the linear pre-tonemap image with the Environment adjustment
    off: a 0.22 mean colour pop at the start and end of every blend, and the painterly far wash was erased.
  - Now `LutBlendCache` bakes in-between LUTs for every profile pair on worker threads (UE4 CombineLUTs approach).
    The nearest of 16 steps goes into the Environment's own LUT; brightness, contrast and saturation lerp.
  - Ends match the snaps within frame noise (0.005 / 0.002). Each step is below 0.005.
  - `test_lut_blend_cache`; `docs/visual_fx_shaders.md` → Color Grade Blend.
- Dev street spawn (owner request): `World` → Developer tools → **Dev Spawn Street** picks one of ten streets from different parts of the island (Whitehead, Duval, Truman, White, Flagler, South and North Roosevelt, Sigsbee Road, Stock Island 5th Street and College Road). In debug builds Henry starts mid-street there instead of the scenario spawn. `KeyWestDevWaypoints.teleport_to` holds him until the street's chunk is live, the same way F6 does, then faces him and the camera along the street. Points live in `routes/dev_street_spawns.json`. Each sits on the centreline at the spot farthest from building outlines, on land: the minimum ground within 8 m is 0.16–2.71 m NAVD88, above MHHW. `test_dev_street_spawns` checks the dropdown against the file and each point against its generated chunk (live ground above sea level, outside every outline), and that Henry is held there. `capture_dev_street_spawn` takes a third-person frame per street.

### Fixed

- TPS camera steps in doorways (#240 stage 3 v2). The camera no longer flips to the other side of a door plane
  while the doorway holds the frame. A neighbouring door waits until the current one lets go, a hand-over's
  shoulder step is eased out, and a doorway may pull the shoulder at most 0.5 m off Henry. On the 727 route, real
  jumps over 0.3 m fall from 3 to 0, and `test_doorway_camera` no longer pops on the yaw swing. The tight-space
  trace is unchanged.
- A room Henry is not in now keeps warming or cooling. `ThermalManager` advanced only the zones Henry's probe
  overlapped, so a room left with a dying fire stayed as warm as when he walked out. Every loaded `ThermalZone`
  now advances (`ThermalZone.get_all()`); the wall thermometer made the stale reading visible.
- Negative temperatures in IM Fell English SC (FEELS, the thermometer) use an en dash: the font has no minus sign and
  draws "-" like a tilde (`TemperatureText.signed`).
- Stove transfers and the lighter hold no longer depend on where the IK palm lands. In the first port a log
  was laid only when the solved palm was within 4.5 cm of the target. In the 727 shelter workflow the arm
  stopped 0.44 m short and the log was silently never laid. Contact is now a point on the act's timeline;
  the arm only presents it.
- Pocket takes keep an item's runtime state. The flare rollback (`HeldOwnership.take` / `restore`), stove
  fuel and eating now use `take_pocket_instance()`; the id-only `take_from_pocket()` refuses stateful items,
  so those paths would have silently failed once items carry state.
- Warmth colour now follows the hypothermia stages (yellow from CHILLED 36 °C, red from HYPOTHERMIC 33 °C).
  The generic 66 %/33 % ring thresholds left 31 °C (the CRITICAL stage) yellow.
- Felt temperature is computed on world ready and on load. Before, it stayed 0 °C until the first
  quarter-hour clock step (about 19 s after a start or load), so `FEELS` would have read +0°.
- Room warmth survives streaming and saves: `ShelterState` stores each zone's accumulated fire heat and
  restores it (`ThermalZone.restore_heated_offset`). Before, a warmed house came back cold.

- Item integrity (Codex, e63bee8e; reviewed in #70): `ItemCatalog` no longer lets a repeated definition id silently
  replace the first (`validate_entries()`, an error at index time). A stackable item refuses an `instance_state`
  instead of dropping it. Pack ↔ pocket moves in the Hub and Quick Access swaps carry each item's state
  (`stow_instance`, `take_pocket_instance`, optional `pocket_states` in the equipment save; old saves load).
  id-only `take_from_pocket` refuses a stateful pocket item rather than erasing its state. `test_item_integrity`
  covers it (fixture now runs on the first frame, so the coat's pockets exist).

- Stove ritual edge prompt (owner request): F no longer makes the centre prompt vanish. Its brackets part to
  the screen edges (72 px in), the yellow strip splits into its two halves, one by each bracket: `[F] BACK`
  on the left, `STOVE` on the right. Any `InteractiveArea` can offer this through `get_session_prompt_data()`
  while it sits in the `active_work_session` group; the stove feed does from the door opening to F.
- Stove ritual (owner request): the ring no longer climbs to the top screen edge (it was lifted 70 px over a
  point 1 m above the cooktop, then clamped); it now sits at the bottom centre, 200 px above the lower
  edge (`bottom_offset_px`). The work view no longer turns sideways with the mouse (pitch only, 12 degrees): a
  left turn brought the eye into Henry's head and faded his body out. `test_stove_ritual` checks the lock.
- Quit to title from the stove ritual logged two errors: the ritual's teardown restores `PlayerState` to
  ON_FOOT after the key hints panel has left the tree, and the panel rebuilt itself detached. The panel now
  ignores mode changes outside the tree (`test_key_hints_teardown`).
- Boot tread readable at play distance (owner: the print "sometimes seems invisible"). The snow shader switched
  the lug pattern off once a pixel on the snow passed 2–6 mm; at the shipped render scale (0.77, FSR) a fresh
  print 2.5 m from the TPS camera spans 4 × 8 mm pixels (measured), so the tread showed only in steep
  close views. Now the pattern blends to its mean shade (lugs cover 34 % of the sole) between 4 and 11 mm
  pixels, measured as the pixel's area on the snow, the way a mip chain filters a texture; groove shade
  0.1 → 0.28.
- Spindrift removed (owner: the plume "bubbles" do not fit). `SnowSpindrift` and its spawning in `WindGusts`
  are gone; the original ground streamers stay. The blowing-snow threshold (`WindGusts.blowing_snow_threshold`)
  stays for the blizzard flow.
- A square of snow around Henry at scene start, then a hitch and it vanished (owner report). Road paving
  had been queued ahead of the chunk snow covers, so no cover was built (measured: 0 of 4 at frame 60)
  while paving ran. Henry's rings drew a square of snow over bare terrain until the queue cleared and the
  cover under him landed in one frame. Covers and paving now run side by side on their own budgets
  (3 ms / 1.5 ms), the cover under Henry first. The field rebuild that follows paving is sliced like a
  walking move instead of done at once.
- Quick Access cards overlapping at some camera angles (owner note).
  - Cause: the layout blended spread and cross by how much the cards overlapped, so a partial overlap gave a
    partial blend that left them on top of each other (`test_quick_access_layout`: 71 overlaps on the old code).
  - The layout is now spread or cross, never a mix; crowding or a tight framing latches the cross, and leaving
    it needs twice the clearance, so it cannot flicker. Same test: 0 overlaps over 7 distances × 12 angles.
- Quick Access drew an item into the hand while its pocket card still showed it. Drawing another pocket now
  trades places: the drawn pocket keeps the held item, the hand shows the new one, and the pocket whose item
  is in hand reads empty (`QuickAccessComponent.draw`, covered in `test_held_weight`).
- Ground drift passed through roofs: its particles had no collision mode (default off). They now collide
  with the snowfall height field, which also stays up in wind without snowfall. Streamers no longer start
  under a roof or a canopy.
- Static shadows' torn outlines boiled on every camera tick. The three-tone cut used hard `step`s, so the TPS
  camera's sub-millimetre damping moves flipped whole contour pixels each frame; the cascades themselves are
  texel-snapped and hold (measured). The cuts are now one pixel wide (`fwidth`): contour pixels changed by a
  1 px move fell from 0.112 % to 0.025 % (0.023 % with no stylisation), the torn look unchanged.
- Static shadows jumped every 2.5 s: the sun's direction was re-aimed every game minute (0.25° of azimuth, about
  11 cm at the tip of a 25 m pole shadow), and stable cascades hold only while the light does not turn. The sun
  now turns once per `sun_step_minutes` (4 game minutes, 10 s at the 60-minute day), eased over
  `sun_blend_seconds` (2 s); loads, clock jumps and acceleration snap (`test_sun_steps`).
- Snow under Henry's feet could stand 20 cm off the drawn snow. Measured at the Duval spawn: field top minus
  lattice ground 0.41 m against a drawn 0.21 m. SnowField sampled ground before the chunk streamed in
  (`KeyWestRealityGround.FALLBACK_Y` 1.0 m against 0.8 m real) and kept that cache across window moves. The
  shell now notes cells sampled off live ground and rebuilds the field in place once that ground streams in
  (same retry scheme as the chunk lattice); after the fix 0.211 against 0.209. Depth, and so how far a boot
  presses, is now measured down to the true terrain where its 1 m corridor tiles rise above the 2 m lattice
  (`test_snow_shell`). The crust lip (`rim_at`) is gated to crust: on loose snow its 8-tap rings drew echo
  contours around every print.
- Boot prints on streets showed white holes in the forefoot and heel. Measured at the Duval spawn: snow top
  1.011 m, road ribbon 0.876 m, terrain 0.802 m, so a full press (give 0.179 m) put the print floor 4 cm under
  the asphalt and the road mesh drew through it. Road ribbons are exported as DEM + 5 cm sampled every 32 m, so
  their lift over the terrain varies. `KeyWestRealityGround` now rasterises each chunk's road triangles into a
  copy of its height tile (frame-budgeted, the chunk under Henry at once). The new `get_surface_height` is
  the ground snow depth is measured to; decks over 0.3 m stay the physics ray's. The field rebuild retry
  also never fired when the first build already saw unstreamed ground (its counter began at 0); every fresh
  build now arms it (`test_key_west_reality_ground`).
- CI: report uploads (`suites` log, capture previews) no longer fail the run when the repository's artifact
  storage quota is full; every suite had passed on `main` while the job showed red for the upload alone.
- CI report artifacts (captures, videos, suite logs) are kept 3 days. The suite log and the Reality reports had
  no `retention-days`, so they stayed the default 90 days on every push and filled the storage quota. The
  GDExtension binaries keep their own retention: the local installer downloads them.
- Outer snow cover no longer crawls or pops while Henry walks (owner report; Codex's `codex` attempts kept the moving square).
  - Cause, measured with a fixed top-down height witness on Duval Street: the shell was one graded square mesh
    that jumped 3.2 m with the field window and blended into the chunk cover over a window-relative 6 m band.
    Each jump put every world point under different vertices and blend weights; the drawn height changed only
    on window moves.
  - Method (Batman: Arkham Origins, GDC 2014; God of War Ragnarök): one base snow surface everywhere, only
    Henry's deformation is local. With the chunk lattice the rings draw exactly the chunk cover's surface (terrain
    on its 2 m triangles + settled depth and wind ridges) and shading (`snow_far_shade`), plus prints that fade
    4.5–6 m out. A first pass blended a field-based near surface into the chunk one by distance; it breathed in
    a 4–8 m band (10.1M pixel-steps over 2 mm on the witness) and was replaced.
  - `SnowClipmap` rings: spacing doubles from 3.1 cm, the mesh follows Henry snapped to its coarsest spacing and
    morphs ring to ring by distance (geometry clipmaps, Losasso & Hoppe 2004; CDLOD, Strugar 2009). The chunk
    cover yields inside 6.25 m through the `snow_lod` global. SnowField mirrors the base for Henry's feet.
  - Wind relief: sastrugi with a steep lee face replace the blotchy ripple, the same in both layers and in chunk
    geometry; slopes are analytic (one noise lookup with its gradient).
  - Witness on Duval Street, 88 frames: largest step main 453 mm → first pass 43 mm → one base surface
    0.06 mm; steps over 2 mm and coverage flips 0 in every distance band. GPU on lavapipe 1347 → 1754 ms
    median (+30 %, software rasteriser).
  - The blue, sunken square in captures was the capture hiding every Control, including the snow passes'
    ColorRects: the shaped field stayed at the clear colour (7 cm packed everywhere). Captures hide only root UI.
  - 53k vertices on high instead of 113k. A/B evidence: `checks.yml` `snow-surface` job (new vs `main`).
  - `test_snow_clipmap` (CPU emulation of the vertex morph), `tools/runtime/capture_snow_surface.gd` +
    `analyze_snow_surface.py`, `checks.yml` → `snow-surface` job; `docs/technical/SNOW_COVER.md` → Drawn surface.
- The 727 corridor (1.8 m wide, doors on both sides) was guessed as a 1.76 m deep doorway, so the mouse soft-stopped
  in its cone along the whole corridor. Guessed openings deeper than `max_guessed_depth` (1.2 m) are corridors.

- 727 Fort St shell (walls, partitions, floor, ceiling) shades with the stylized shadow contract again. Reality chunks
  instanced the glb with its plain `StandardMaterial3D`, so indoor stove shadows lost their torn edge after the shelter
  moved from the First Exit hut into 727. A post-import script (`tools/import/stylized_landmark_import.gd`) converts
  the surfaces; `test_key_west_727_shelter` checks them.

- Editor docks no longer stretch the editor past the screen: ItemFitter (min 360×760) and Reality scroll inside their
  tabs. Godot AI dock: its one-line labels and buttons clip with an
  ellipsis. The 4.3.0 self-update had reverted its Inspector-group slot; restored. Customizations are listed in
  `docs/technical/GODOT_AI_INTEGRATION.md`.

- Godot AI and ItemFitter now default to the Inspector dock group instead of a separate lower-right group. Existing editor layouts retain their saved placement.
- Sky weather character, finishing Codex's cloud pass (owner review: windy clouds and the night barely differed).
  - Causes:
    - clouds followed snowfall only, so windy (snow 0.15) looked calm;
    - the sky shader's sun term is scaled by a Beer transmittance of about 0.02, so clouds had no lit side and
      read as dark smoke;
    - night clouds were black on black;
    - the volumetric fog and the paper-white wash greyed the night out.
  - Now `PainterlyDayNightManager`:
    - wind sculpts bodies (contrast, bellies, size, clearer air over them);
    - snow closes the deck;
    - a blizzard veils it;
    - the moon lights the deck at night.
  - New sky uniform `cloud_top_light`: a directional self-shadow, one height sample toward the light, gives lit tops
    and dark bellies.
  - The wash and paper colour follow daylight (paper → ink), and darks lift toward it.
  - Petronia Street capture, Codex → now:
    - Night sky mean: calm 0.195 → 0.054, blizzard 0.768 → 0.338 (no more white night sheet).
    - Night windy cloud local contrast: 0.0121 → 0.0232.
    - Day windy: 0.0122 → 0.0137. The day change is smaller because the camera sees mostly the hazy horizon band.
  - New `test_sky_weather_character`; `capture_sky_weather` shoots eight states (snowfall added). Rules in
    `docs/visual_fx_shaders.md`.
- Physics back on GodotPhysics3D (owner decision after the play test). Jolt ran slower on the owner's machine, with more hitches and erratic snow contact. `project.godot` names the engine explicitly; the Jolt measurements stay in `REALITY_HLOD.md`.
- Painterly wash erased every transparent surface. The pass reads the screen texture (opaque geometry only), writes every pixel and drew last among transparents (`render_priority = 127`). Falling snow and the 727 frosted glass vanished under it, and the owner saw no snow and a clear 727 window. Test pane: 127 → (0.74, 0.75, 0.76), the pane gone; −128 → (0.95, 0.35, 0.36). The pass now draws first among transparents (`render_priority = -128`).
- Painterly wash strength follows snowfall (owner rule): new `wash_strength` mixes the pass with the untouched frame, 10 % in calm weather up to 100 % in a blizzard (`PainterlyAtmospherePass.wash_strength_for`). Before, the full wash showed in calm weather too. `test_painterly_sky_rule` checks the curve, the live binding and the draw order.
- Main scene start moved to the 727 shelter (owner, 2869065b: `spawn_at_shelter = true` in `key_west_reality.tscn`). That commit also left stash-conflict markers in `project.godot`, so Godot could not parse it; resolved with `snow_field` kept in `[shader_globals]`. `test_key_west_reality_fresh_checkout` asserted a bunker start. It now checks the start the scene chooses: within 12 m of the route's `727_fort_st_entrance` goal with `spawn_at_shelter`, else before the bunker door. Both branches pass.
- Ground lost under the start after island-wide HLOD (CI `key-west-reality` red on f8082a57: the dev teleport trace had 9 of 9 targets wrong). At boot `KeyWestRealityGround` indexes every node in the stream container. HLOD cluster scenes carry their source chunk's `chunk_id`, so indexing a cluster dropped that chunk's terrain and building outlines. With HLOD only in Old Town the start chunks never had clusters; now `-8:3`, `-8:4` and `-9:3` do. Effects: heights fell back to 1.0 m, the F6 wait never ended, and snow ignored the fort-area outlines. A node with `cluster_id` is no longer indexed; its buildings are already in the chunk root's `snow_footprints`. `test_key_west_reality_ground` checks that a cluster leaves its chunk's ground and outlines. Trace after the fix: 0 of 9 wrong.

### Changed

- Road flare at night (owner picked variant C). The light's volumetric-fog tint drops from 1.0 to 0.3: the
  default tint filled the night fog with a red haze, which was the main cause of the "everything is red" read.
  Falloff is now inverse square (`omni_attenuation` 2), and the radius no longer breathes with the burn. All three
  are `HeldFlare` knobs (`fog_energy`, `light_attenuation`, `range_breath`). The particles are rebuilt:
  - the tip burns as a steady short jet (white core to orange to red);
  - sparks and spurts are streaks aligned to their velocity;
  - the large bits are slag that falls and cools;
  - smoke is a plume of 96 faint, spinning, noise-edged puffs. Before, it was 42 round quads that read as glowing balls.
  Capture: `tools/runtime/capture_flare_night.gd` (A/B/C outside, close-up frames, inside 727).
- TPS camera look-ahead v2 (#240 stage 5). The orbit centre leads along Henry's intent (the keys' world
  direction, `LocomotionIntentCapability` published by `Player`) and fades while intent and motion disagree; it
  shrinks 2.5x faster than it grows. Sprint reversal in the corridor: the lead no longer stays 0.44 m ahead while
  Henry brakes; worst lead against motion 0.15 → 0.02 m. The tight trace gains a corridor `reverse` phase.
- TPS camera keeps Henry's eyes inside the frame's lower edge when he is off to the side (#240 stage 4 tail).
  `keep_eyes` measured the eye angle over the full distance instead of depth along the view, so off-centre eyes sat
  at the bottom edge (restroom, backing in: y 0.98). Now exact (`TpsRigShoulderLift.eyes_pitch_limit`): tight trace
  eyes at the bottom edge 70 → 0. Stage 6 (context interests) waits on hazard data: `IceField` is not placed in any
  scene and there are no edge markers.
- `test_doorway_camera` is green (#240 stage 7), two runs; it is off the known-failing list. Standing in the door and
  looking up, the camera lost Henry in every frame of the 30° sweep (and 170 of 750 at 10°). On the doorway's short
  boom the camera barely dropped, unlike outdoors (checked: 0 lost frames 5 m outside). Now it drops as far as
  Henry's middle needs to stay inside the frame's lower edge (`TpsRigPassage._drop_pitch`). It also lost him sideways
  at the soft stop, which assumed he sat mid-frame; the stop now subtracts the angle the shoulder offset puts him off
  centre. The route trace snaps the camera on its own stuck-Henry teleports, as the dev waypoints do, and skips
  those frames: the 727 route now meets all three #240 criteria (no step over 0.3 m; largest 0.28 m).
- TPS camera swings round Henry in tight space (#240 stage 4, part 2). Shot choice now scores lift caps × orbit
  swings (0, ±20°, ±40°; the view stays the player's), adds a cost for Henry's eyes off the left or right edge, and
  is off in doorways. The prediction now follows `keep_eyes`' pitch limit, the side recompose leaves and Lyra's
  feelers (`TpsRigCollision.target_shares`). Without the recompose term it chased a wrong frame in a 20-frame cycle.
  Tight-space trace vs part 1: eyes off screen 11 → 0, within 0.8 m of the eyes 1,440 → 141, faded 0, bottom edge
  81 → 70. Along walls the camera stands off to the side and shows the corridor. 727 route: no real jumps.
  Backing into the exam corner or the restroom still looks down from above.
- TPS camera picks how far to lift over Henry's shoulder in tight space (#240 stage 4, part 1). Four lift caps are
  scored on a stateless prediction of the frame and eased with hysteresis. Along walls the camera now stays at the
  shoulder instead of looking down from above. Tight-space trace: eyes off screen 57 → 11 frames, at the bottom
  edge 543 → 81, faded 10 → 0. The exam corner and the restroom still lift; authored room hints are next.
- TPS camera rig split into behaviours (#240 stage 2). `_update_rig` now runs `TpsRigFollow`, `TpsRigAutoSwap`,
  `TpsRigComposition`, `TpsRigPassage`, `TpsRigShoulderLift`, `TpsRigRecompose`, `TpsRigCollision` and `TpsRigWork`
  on one `TpsRigFrame`, each owning its state and smoothing. Behaviour is unchanged: the 727 route trace and the
  tight-space trace match their pre-refactor output byte for byte.
- `tools/runtime/trace_camera_route.gd` (#240 stage 1) measures the camera on a 727 walk. It records eyes in frame,
  fades, jumps over 0.3 m, wall share, the share of the frame Henry covers, and mouse deviation.
- Hammer held fit re-authored by the owner in the Item Fitter: right hand, offset (-0.025, 0.08, -0.005), rotation
  80° about X. `test_held_fit` now pins this fit.
- Work gloves restyled after the owner's reference: an olive back, tan leather at the knuckles and fingertips,
  a dark palm, and an insulated dark gauntlet over the sleeve (`Outfit_GloveCuff`) with a strap and a red pull tab.
  Panels are flat colours painted per face and settled by a neighbour vote so decimation leaves no specks.
- The top-right "Room air" HUD readout is gone; the 727 wall thermometer replaces it (owner, #236).
- Stove look after the owner's review of the 727 capture:
  - flames are about 40 % taller and denser, and a caught log grows to full burn in 6 s instead of 10;
  - the shelter colour grade is 12 % brighter, so the room before ignition reads (frame mean 54 to 61 of 255);
  - the stove ring sits at screen centre, 100 px down;
  - the F BACK / STOVE prompt keeps its place but drops to 60 % opacity during the session.
- Stove ritual framing (owner: "we saw nothing inside the stove or what Henry does"). The TPS camera stayed high
  behind Henry, his back hid the door, and the iron stove was lost on the dark floor. The same TPS camera now
  eases onto a work framing while the door is open (`TpsCamera.set_work_framing`), the owner's composition:
  close over Henry's right shoulder, shoulder lower left, head left, firebox mouth mid-frame, door on the right.
  From behind, Henry kneeling square to the door hid it with his back, so he now kneels 0.3 m off the door axis,
  turned to the mouth, and the door folds back 160 degrees (was 105, swinging toward the camera).
  The stove's "Use" prompt no longer shows during the ritual. The mouse orbits it a little, walls still
  shorten the boom, and F eases back to the follow rig. No separate mini-game camera.
- 727 floor lighter and warmer (owner: stove and floor merge). The floor's real material is the external
  `floor_old_wood_727.tres` (the glb's `floor_vinyl` is remapped in the import), 0.23/0.16/0.10 to 0.40/0.29/0.18
  against the 0.13 iron. The earlier glb tint (6e90bb3) changed the remapped-away colour and showed nothing;
  reverted with its tool.
- Stove ritual replaces the stove's F cycle (owner spec). Before: F opened the door, the next F loaded the whole
  armful and readied the lighter, and RMB took cold logs back. Now `[F] Stove` walks Henry to a
  `StoveInteractionPoint` in stove space (the player's own scripted walk, no teleport, refused when his capsule
  does not fit). He turns to the door, it opens, and he crouches with or without a load: a new `CrouchCarry`
  state keeps the carry arms over the crouch legs. `PlayerState` WORKING roots him, the interact key is claimed,
  and the TPS camera stays. A three-arc ring (`StoveInteractionRing`, the pickup marker's language) shows fuel
  (one tick per log of the real capacity), tinder and fire.
  - RMB lays exactly one log per press. The inventory and `HeatSource.add_logs(1)` change together when the
    act completes; a cancel moves nothing.
  - LMB lays tinder, only with a log in. The press that laid it never reaches the lighter: release, then a new
    press strikes the existing lighter, and a 3 s hold lights the stove.
  - Logs can follow the tinder. A burning stove takes logs without relighting.
  - F closes the door and stands him up.
  - Tinder is new `HeatSource` state (`tinder_prepared`). It is saved and recorded by `ShelterState`, and kept
    when Henry leaves.
  - The work pose backs down instead of standing up through its clip while Henry stays crouched.
  - New `StoveInteractionController`; `HeatSourceFeed` keeps only the acts. `test_stove_ritual` covers the 12
    owner scenarios; `test_shelter_workflow` is updated. `capture_stove` now runs in 727 (it used archived
    Graciosa). Doc: `docs/technical/STOVE_RITUAL.md`.
- Window frost forms and thaws like real fern frost (owner: not natural). Before, one mask served both
  ways: the frost edge was a noisy band at a fixed distance from the frame, so growth and thaw were the
  same rectangle moving in and out (a square hole at 50 %). Now each texel has two dissolve thresholds.
  Growth starts at the bottom edge (cold conducts along the glass edge and cold air slides down it), then
  the sides, the top last, plus a few nucleation points (scratches, dust). The reach varies round the
  rim (seamless noise in angle): frost tongues far in on one side and hugs the frame on another
  (owner: not evenly from the edges). Fern fronds lead the front:
  tapering spines with barbs at the ice's 60°, two sizes. New frost is thin and turns opaque as it
  ages. Thaw clears the warm centre first along a soft, wet front. The thick fronds and the cold bottom
  corners go last (FUTURE_INTENT §3, frost retreating to the edges). Measured on the pane mask: 50 % left
  at thaw 0.55, 10 % at 0.80. The pattern is metric (pane size from screen derivatives), so the 727's
  wide panes no longer stretch it. Fronds far from the frame point any way, which removed a rosette at
  the centre. Barbs smaller than a pixel blend to their mean instead of aliasing. Random, never preset
  (owner): the 727 draws its frost afresh each load (`growth_seed`) and a new thaw path each time the room
  starts to warm (`melt_seed`, swapped while warmth is 0 so nothing jumps). `frosted_glass` (727) thaws
  as the stove warms the room; the generated `frosted_window` uses the growth mask.
- Ground drift travels as a wave (owner note: it appeared in place, straight). Each `SnowLift` streamer is now a
  sweep: the emitter runs downwind for 1.6–2.4 s at 0.45 of the 10 m wind along a shallow arc (bow 5–9 % of
  its length, side at random), snapped to the ground, shedding its four layers into a world-space trail that
  swells in and dies out. A 12 m/s sweep is ~9 m (was a fixed 5 m patch); it ends at a kerb over 0.6 m or a
  slope. A sweep starts only when its start, middle and end are on screen and it crosses open snow (no
  footprint at either end, no canopy over the start). Both drift sources use it: the wind drift ahead of Henry
  and the blizzard flow streets (`test_snow_lift_sweep`). The head now rides the drawn snow top
  (`SnowField.get_snow_top`): it stood on the physics ground, 0.23–0.49 m under the snow at the Duval spawn
  (measured), so the grains were buried and the drift barely showed on snow. On lit snow the grey grains
  (0.8) still matched the surface, so the grains are lighter (0.95) and the sweep drags a soft cool shade
  over the snow under its trail (owner's idea from the spindrift round). The technique is a moving emitter leaving a world-space
  trail (Godot `local_coords = false`), as trail emitters do.
- The world shows finished (owner note: a square of bare snow at start that went away a minute later). The
  startup card now holds until boot work is done, through a new `BootLoadCapability` (`core/contracts/`):
  `KeyWestRealityGround` reports the chunks live at boot until their paving and snow cover are built, and
  builds them at full speed under the card; `SnowShell` reports a pending re-read of ground that streamed in
  (weather rebuilds do not count: the old window stays drawn, and in a blizzard they run all the time).
  The card waits at most 30 s and logs who was still pending. A field sample over ground that never streams
  (open sea past the chunks) is not boot work: it held the first run at the 30 s cap.
- In falling snow the sun dims with visibility (Koschmieder extinction 3.912 / visibility over a 30 m beam
  path): ~7 % of the sun in a 45 m blizzard, ~59 % in 220 m snowfall, 75 % in 400 m windy weather. The lost
  beam returns as ambient fill, 0.3 per unit of lost sun, in the sun's own colour (snow scatters it
  unchanged) and never in shelters. 1.86 in grey washed out the LUT grade (ambient 3.1 against a 0.55 base);
  the sky tint at 1.8 turned a blizzard blue; 1.2 in the sun's colour made a blizzard 132 % of clear day.
  Measured on snow at the Duval spawn (linear): 81 % of clear day in windy weather, 74 % in snowfall, 53 % in
  a blizzard, with the clear-day colour balance (blue minus red 35–38 against 33). Before, a blizzard kept full sun and hard shadows (`test_sun_steps`).
- Fort Zachary Taylor collision simplified in Blender: `tools/blender/landmark_collision.py` (Blender 5.2 `bpy`, Decimate Collapse 0.2) adds a `FortSurfaceCollision-colonly` copy of 8,238 faces (was 41,197) to the fort `.glb`; the visual mesh is byte-identical. Error from every source vertex and face centre: mean 0.8, p99 5.1, max 12.5 cm. The fort chunk's `Buildings` attach drops from 66–80 ms to 12 ms (`measure_attach_parts`, `kw_gen_-9_3`). A 1 m ray grid against the exact surface: p99 8 cm. `HeightMapShape3D` was measured and rejected (285 ms to build). New `test_landmark_collision`; method and table in `REALITY_HLOD.md`.
- **Legacy Key West island removed** (owner approval, 2026-10-15). Gone: `key_west.tscn`, `key_west_first_exit.tscn`, the `key_west_test` profile, `KeyWestFirstExit`, the legacy city (`ChunkedCityMassing`, `KeyWestCityVisuals`, `KeyWestStreetProps`, `far_city/`, `snow_chunk/`), the NOAA preview crop, six legacy-only tools and three legacy-only tests. The legacy branches in `runtime_performance_policy`, `dev_diorama_map` and `snow_shell` went with them (none ran under Reality). The CI preview job keeps its Reality captures only. `capture_quick_access` now runs on Reality; `test_world_profiles`, `test_stylized_shadows` and `test_island_terrain` check Reality or Graciosa instead. Kept on purpose: `IslandTerrain`/`IslandHeightmap` (Graciosa, the hut template generator), the terrain shader, the Reality Library sources and the NOAA sources. Record: `docs/technical/LEGACY_ISLAND_REMOVAL.md`.
- Owner tasks, 2026-10-15:
  - Facade windows on every generated building, frosted. Panes are 1.0 × 1.4 m on a 0.9 m sill, every 3.2 m along each straight facade (outline points within 0.35 m of a line), one row per storey from `levels` or the measured wall height. Material `frosted_window.gdshader`: frost from the GDExtension lab pattern, a painted sash frame and meeting rail, lit like the walls. Empty houses are 100 % frosted. The 727 glass keeps 60–80 % per window and its heated room clears to 20 % as the stove warms it. Duval St chunk: 12,891 panes on 458 houses; `test_window_frost`.
  - Snow on trees: on the up-facing tops of fronds, limbs and twigs with the live snow cover; trunks bare; windward rime (`tree_snow.gdshader`). Wires, fences and pole tops already had snow.
  - HLOD island-wide: 114 chunks, 995 clusters (was the 2×2 Old Town block).
  - East audit: Boca Chica has no houses by the extent rule; airport buildings are in the data; DEM voids are water (`docs/technical/EAST_KEY_WEST_AUDIT.md`).
  - All 459 chunks regenerated (`kw_chunk_builder.12`), chunk and HLOD digests recorded.
- Painterly wash sky rule (owner decision): the sky takes 10% of the wash in clear, windy and ordinary snowfall weather, and heavy snowfall raises it gradually to 100% (`smoothstep(0.45, 0.95, snowfall_density)`, so a blizzard washes the sky fully). `PainterlyAtmospherePass` follows the live `WeatherController` (`conditions_updated`, already blended per profile). Rule in `docs/visual_fx_shaders.md`; new `test_painterly_sky_rule` checks the curve and the live binding in the main scene. `DEV_DIORAMA_MAP.md` updated for the 90 m camera.
- Painterly wash keeps the authored sky: sky pixels (no depth) counted as the farthest distance and took the full far wash, so the parallax clouds and horizon haze went flat white (sky saturation 0.097 → 0.028, luma 142 → 213 at Duval St). New `sky_affect` uniform, as `Environment.fog_sky_affect` does for engine fog: the sky takes that share of the wash. Measured at 0 / 0.1 / 0.25: saturation 0.096 / 0.067 / 0.044. Default 0.1 pending the owner's pick; at 0 the sky is untouched but washed far buildings stand white against it.
- `capture_stylized_shadows` inside frames on the 727 room: the fixed inside camera sat at the legacy hut's stove offset, 5.43 m from Henry, but the 727 wall on that line is 4.35 m away, so `02_inside_noon` and `03_inside_stove_night` showed a wall and no Henry. The camera is now pulled in front of the first wall on the line from Henry (spring-arm rule, 0.35 m margin) once his chunk is live.
- Painterly wash (Codex, from `main`) kept to the player camera: its fullscreen quad sat on render layer 1 and its vertex shader covers the screen of any camera that draws it, so the dev diorama map drew it too, as a full far-distance wash (map luminance spread 0.171 → 0.020, a flat white sheet). The pass now lives on its own layer 18 (`RenderLayers.SCREEN_PASS`, `screen_pass`), which the map camera leaves out; the player and hub cameras still draw it (screen mean 0.632 → 0.665 with the pass). `test_dev_diorama_map` checks the map camera's mask.
- Dev diorama map: the first render at 90 m showed the map washed grey. The world's depth fog (`fog_mode` depth, default 10–100 m ramp) is opaque at 100 m, and the map camera sits 90 / sin 64° ≈ 100 m from Henry. The map camera now has its own environment without fog (flat ambient, dark background). The header shows the camera height from its constant (it still read 30 m).
- `capture_tps_doorway` on the 727 door: Henry stopped 1.4 m short of the opening on every pass. The tool aimed him from the zone centre, but the 727 door sits in a side wall, about 64° off that line, so he walked into the wall. The way in now follows the door's own axis, as `test_doorway_camera` does. A headless run is a dry run (walk and log, no PNGs); all eight moments are reached. Removal plan: step 4 (legacy branches in `snow_shell`, `runtime_performance_policy`, `dev_diorama_map`, `world.gd`) moves into the deletion change, since each branch serves only the legacy scene that still runs in CI.
- Dev diorama map framing (owner request): camera 30 → 90 m and FOV 36° → 50°, about 160 × 100 m round Henry, so the address labels within 95 m fall in view; labels keep one screen size at any height (`fixed_size`); Henry's marker is a large saturated red dot with a white rim.
- Dev diorama map on Reality: house numbers and street names now come from the Reality building index (`RealityIndex.map_label_entries`, the same entry format as the legacy city) when there is no `ChunkedCityMassing`; 30 labels around Duval St, 28 around 727 Fort St. Labels are rebuilt only when the set changes (they were freed and recreated every 0.75 s, so on a slow renderer they never drew). The map camera's fixed 30 m / 36° view covers about 20 × 12 m round Henry, so most labels sit outside it; that framing is the map's own tuning. `capture_dev_diorama_map` moves Henry to Duval St (no addresses near the fort start) and renders on Reality.
- Legacy island removal, step 3 (capture tools): `capture_sky_weather`, `capture_dev_diorama_map`, `capture_motion_matching_street`, `capture_stylized_shadows` and `capture_tps_doorway` load the Reality scene and no longer force the legacy `key_west_test` profile. New `CaptureWorldSupport` gives them ground height from either world and waits until the chunk at a point is live and the streamer quiet; the shadow capture finds the shelter and its way out from the scene's ShelterZone and door instead of the legacy bunker/shelter coordinates. `capture_sky_weather` verified on lavapipe (calm/snowfall/blizzard frames from Reality, cloud threshold 0.30 → 0.255 → 0.205; `docs/runtime_previews/sky_weather/`); the other four compile and are being rendered one by one. `capture_key_west_first_exit` films the legacy route and goes with the island; `capture_quick_access` (Codex's, from `main`) is left to Codex.
- Legacy island removal, step 2: `test_stove_world_time` and `test_doorway_camera` run on the Reality scene (the 727 stove and door). The doorway test now waits until the door's chunk is live and the streamer is quiet before its scenarios. On the 727 door the mouse-freedom checks that failed on the legacy door pass; Henry still leaves the frame in the full-turn stand sweeps, as on the legacy door, and briefly in the yaw/pitch swings (camera tuning; known-failing list updated). `test_stove_world_time` passes.
- Legacy island removal, step 1: the palm and leafless-tree meshes moved from the legacy `KeyWestStreetProps` into the shared `WinterTreeMeshes` (`scripts/world/props/`); the Reality chunk builder uses it and no longer touches legacy code, the legacy props delegate to it. Byte-identical: chunks -6:3 and -7:3 rebuild with the same digests (17fc605d…, e5f3ec47…), partial verify identical.
- New `suites` workflow: every headless suite under `tests/systems` runs on every push, report-only (`checks` stays the gate on `main`, as its header says the suites still churn). `tools/ci/known_failing_suites.txt` lists the two camera suites still failing, with reasons; `run_tests.sh` reports them without counting them and fails if a listed suite starts passing, so the list cannot go stale.
- `test_street_props_streaming` (legacy island) follows the current street props: every kind, palms, bare trees and power poles included, is filed per city chunk; it expected the earlier island-wide silhouettes and counted the merged crossings mesh as instances. It passes.
- Dev diorama map: its camera is moved in `_process`, but the project runs physics interpolation, so the map drew and projected the camera a tick behind (Henry's marker landed off the map centre). The camera now has physics interpolation off, as Godot advises for nodes moved in `_process`. `test_dev_diorama_map` also set a position before the node was in the tree and checked the projection before the shown containers had laid out; both fixed. It passes.
- Snow suites match the shipped snow shell: `test_snow_contact_pipeline` checks the game's `DeterministicSnowShell` (local 256² contact over 6.4 m) and only failed to find its unnamed contact camera, now named `ContactCamera`; `test_snow_shell` expected the base shell's packed field at 1024² and `world.gd` to build `snow_shell.gd`, while the packed field is 896² since the cost pass (`SNOW_COVER.md`) and `world.gd` builds `deterministic_snow_shell.gd`. `SNOW_COVER.md` no longer says the packed field is 1024² or that the game's contact capture is 1024².
- Fixed a stale authored passage: Henry's passage traversal kept an authored doorway (NarrowPassage or HingedDoor) after its node was freed, because unmarked-geometry detection is skipped while an authored passage is held; in the streamed world that is any door in a chunk that unloads. It now drops an authored passage whose source node is gone. `test_passage_traversal` passes (its corridor check stood inside the freed 1.45 m test door).
- Failing-suite repair, part 1 (these 10 suites failed since the start of this repository's history; Jenova once forced every Godot exit code to 0, so they looked green): `test_door_draft` drove the door's hinge transform instead of its angle state; it now sets `current_angle_rad` and lets the hinge and breach exposure follow, as the game does. `test_held_fit` and `test_held_light` pinned the pre-"flare pass 2" sideways pose; the authored fit (upright out of the fist at chest height, checked in a render) is now the reference, and the nozzle rule is "above level and never back into Henry". TPS camera: with Henry's back to a wall the shoulder recompose, built up at an earlier yaw, now lets go at the fast rate when the centre line would bring the camera closer (its documented rule); `test_tps_camera_orbit` goes from 3 to 2 failed checks, the rest is boom smoothing near the 0.25 m fade end (owner's camera tuning). `tools/runtime/capture_held_flare_pose.gd` renders the held flare from three sides with the authored or a given fit.
- The game now starts in Key West Reality: `run/main_scene` and the title menu's `game_scene` are `key_west_reality.tscn` (owner decision, proposed in #219). The legacy island still loads and is prepared for removal: the hut cabinet fade volume and dressing moved to the shared `ShelterCabinet` (the 727 shelter no longer calls legacy code), `test_key_west_first_exit` loads the legacy scene by path, and `docs/technical/LEGACY_ISLAND_REMOVAL.md` lists what blocks deletion (Reality's chunk builder still uses the legacy street-prop tree meshes), what to delete, what to keep, and the order.
- 3D physics switched to Jolt (built into Godot; the default for new projects since 4.6; ours ran GodotPhysics as an older project). The 11 ms `attach_part` in #219 was a collision rebuild, not node attachment. GodotPhysics builds a chunk's concave building collision on the main thread twice in debug builds: once when the loader's queued `shape_set_data` flushes, once in `CollisionShape3D.set_shape`. Jolt builds it once, lazily and faster. Buildings instantiate 9–18 → 2–3 ms; a frame that finishes loading a Buildings part 19–22 → 10–12 ms. The full suite shows the same 10 failures as before (they fail on current `main` too and are not in CI); the 727 loop passes; gate frame times are unchanged (p50/p95/p99 6.83/14.32/17.26 vs 6.86/14.53/17.33 ms on one machine). Revert = remove one line in `project.godot`. Henry's movement feel still needs the owner's check. Details: `docs/technical/REALITY_HLOD.md`.
- Dev teleport (F6) no longer drops Henry through the ground or into a building. Before, on an unloaded chunk it read the ground's 1.0 m fallback (Henry fell 0.95 m through the terrain at Whitehead x Petronia) and an address put him on the building's centroid (inside 727 and 907 Whitehead). Now Henry is held at the target, physics off, until the chunk under it is live (`KeyWestRealityGround.has_ground_at`), as UE World Partition waits on `IsStreamingCompleted` before a teleport ends; he is then set down on the first spot where his own capsule overlaps nothing, as `UWorld::FindTeleportSpot` does: for an address, 2 m out from the wall facing the most open ground, then rings around it. `tools/runtime/trace_dev_teleport.gd` in the real scene: 3 of 9 targets wrong → 0 (`docs/runtime_previews/key_west_dev_teleport/`); in CI.
- Reality dock: Go to now frames the whole building. In Godot 4.8 F only re-centres the editor orbit and keeps its distance (4 m on a fresh view), so a sized marker cannot fix it; Go to now centres on the building's bounds (from `editor_index.json`, shown as an unsaved box), measures one wheel notch and moves the view out or in until the bounding sphere fits. Measured in the real editor: 7.7 → 29.6 m at 907 Whitehead (needs 25.9), 7.3 → 16.0 m at 1009 Windsor Ln (needs 13.8).
- HLOD debug view: F3 in a debug build tints every proxy (Tier 1) orange and every drawn detail cluster blue, fog-free so it reads in a blizzard (`KeyWestRealityHLOD.set_tint_tiers`, off in release). The tier capture uses the same tint and now also enters Old Town from Duval St; on the owner's GPU no cluster shows both or neither, and runtime differs from all-detail on 0.11 % of pixels or less.
- Dev navigation in the Reality scene (debug builds only): F5 cycles a target through the First Exit route goals and listed addresses (727 Fort St, 907 Whitehead St, resolved through the editor index), shown as a 150 m beacon seen through buildings plus a distance and compass line; F6 teleports Henry there. `KeyWestDevWaypoints`, `test_key_west_dev_waypoints`.
- Fixed the 727 door vanishing a second after a shelter spawn: chunks prewarmed at boot were live before the far view connected, so when the far cell arrived its mesh (with 727's building prism) drew over the detailed chunk. The far view now syncs with the streamer's states on connect, as the HLOD view does. Traced with `tools/runtime/trace_727_door.gd`; guarded in `test_key_west_reality_hlod`.
- `StreamingSystem` scales with the cells near the player, not with the island: `pump()` walks only cells in QUEUED/LOADING/READY/ASSEMBLING, and `scan()` reads a 256 m grid of load bands plus the live cells. At 7,803 cells (the island in 128 m clusters) `scan()` 27–36 → 0.3 ms and idle `pump()` 13–14 → 0.003 ms on the owner's laptop. API, signals, budgets and hysteresis unchanged; `test_streaming` checks the grid against the bands; `tools/runtime/benchmark_streaming_scale.gd` reproduces the numbers.
- HLOD on the owner's GPU (Intel HD 620, LOW, 1080p): `measure_key_west_hlod.gd --all-detail` swaps every proxy for its detail scene, an A/B on one build. Draw calls fall 41–67 % as on lavapipe; FPS gives no verdict, because run-to-run noise (125–334 ms on unchanged controls) is ten times the effect. The game runs at 3–8 FPS on this GPU, bound by GPU load and script time, not draw calls. Data and reading: `docs/technical/REALITY_HLOD.md` §3c.
- Reality HLOD v1 on the Old Town sector (chunks -6:1 -5:1 -6:2 -5:2, `config/hlod.json`): generated buildings stream in 128 m cluster cells of the same `StreamingSystem` (detail within 230 m, out past 350 m), and while their chunk is loaded an offline proxy (merged by material, roof snow folded in, no collision) stands in for each cluster that is out; `KeyWestHLODBuilder` writes a deterministic manifest (stable ids, sorted sources, bounds, source hash, counts) and rebuilds only dirty clusters; Reality dock: cluster bounds, tier preview, fresh/dirty, counts, sources, Build selected, Rebuild dirty; CI rebuilds the proxies from clean, checks the digest, partial == full, missing/duplicate/orphan ids, and walks detail → HLOD → detail. Baseline, design and numbers: `docs/technical/REALITY_HLOD.md`. Proxies load when the chunk's far cell comes in (2,500 m), so the main thread never waits for one; streaming and HLOD stages are timed in the gate and in a boundary stress test.
- Reality winter pass: the dynamic snow on Reality now reads a wind field baked from Reality's own buildings and land (`snow_wind_reality.png`, chosen by the world profile; the legacy bake had a Truman Annex block that does not exist); static snow caps on 13,214 roofs (ASCE 7 slope and exposure factors, windward thinner, lee cornices past the eaves), ridges on fences and wires, caps on pole tops, in a per-chunk `Winter` group (data layer `winter`, never deformed). Chunks now build identically alone or in any order (named collision shapes; the node digest sorted metadata keys by StringName address); CI checks a partial rebuild against the full one. Generator `kw_chunk_builder.11`.
- Reality edit layer: per-chunk edit records (remove, move) tagged with a data layer (`base`, `winter`, `loot:<set>`, `story:<state>`); only `base` changes the generated world, the rest travel with the chunk export; the Reality dock records them with undo. `blender-shell` writes one building's measured shell (glTF) and sizes for Blender, and a returned model registers at the shell's origin.
- Reality editor (stage 1, read-only): `key_west_reality_editor.tscn` shows the whole island as far meshes with detail chunks around the 3D editor camera, and the "Reality" dock finds buildings by address, name or id, frames them (Go to, then F) and identifies the building under the marker or the first one the camera's look ray meets; index from `key_west_reality.py editor-index`.
- Replaced the rejected Jenova experiment with the production GDExtension/godot-cpp path: portable core, real controller adapter, checksum-verified three-platform CI artifact and local installer.
- Added the Quick Access HUD, its 3D anchor rig and supporting UI shader material.
- Reality partial export (`export-editor --chunk`): a chunk now keeps the pieces of roads and areas owned by a neighbouring chunk (22 roads were missing from `-7:3`), and the island chunk list in `manifest.json` stays whole; 3 chunks re-exported alone match the full export. Editor and partial-rebuild plan: `docs/technical/REALITY_EDITOR_PLAN.md`.
- Key West Reality is playable as a separate review scene (`key_west_reality.tscn`, F6; the legacy scene stays the default): First Exit bunker set into Fort Zachary Taylor's courtyard face, every template pickup at a rule-chosen real site (same ids, counts, persistence), `PickupLedger`, and the full 727 loop (repair, fire, warm/dry, eat, sleep, save, reload) checked in the real World.
- Reality world: frozen sea (shared frozen-sea look on water polygons and on terrain below mean sea level), far view from generated per-chunk meshes streamed like the legacy far city, parking and aprons draped on the DEM (flat plates floated over sunken lots and blocked drives), courtyards open in building collision, traversal report. Generator `kw_chunk_builder.9`.
- Reality: roads, paths and parking take the terrain's snow response (they showed through the thin settled cover in patches); buildings that a mapped way runs straight through are no longer generated (owner decision; listed in `reports/buildings_removed_on_ways.json`). Generator `kw_chunk_builder.10`.
- Snowfall: the particle height field re-renders when a chunk streams in, so a roof that arrives after Henry (load inside 727) stops the snow indoors.
- Reality roads: a line now lives in every chunk it crosses (929 roads, trails and rails were drawn only while their single owning chunk was loaded) and samples the ground at least every 32 m; same-machine A/B shows no frame-time change. Generator `kw_chunk_builder.8`.
- Reality vegetation: lidar tree trunks no longer stand on roads (crown centres over streets moved to the road edge: 2,061 → 43 on a ribbon); 54,372 dead-shrub stem clumps from mapped scrub/wetland/mangrove/garden/wood areas (lidar low vegetation weighted), leaning downwind; trees and stems sit on the chunk terrain surface. Interchange re-exported, generator `kw_chunk_builder.6`. Stems ride up with the drawn snow (`snow_stems.gdshader` reads the shell's published `snow_field`), so they poke out at any snow depth.
- Reality chunks: water and canopy slabs now respect polygon holes (islands in water, clearings in canopy were filled); generator `kw_chunk_builder.5`, digest re-recorded.
- Added owner-local cross-language capability contracts under `core/contracts/`; `SaveManager` is the first production consumer, with legacy save providers adapted at the boundary and no extra Port nodes required.
- Added paired English/Russian canonical architecture contracts; full-project ECS is rejected in favor of the Godot/component + domain-core model with selective ECS/DOD only where justified.
- Added canonical player-experience and Key West design doctrine documents and linked them from the PRD / agent workflow.
- Replaced the historical long-form changelog with this concise production log.

## Changelog rule

Record outcomes, not the development session. Prefer one short bullet per meaningful change. Put implementation evidence, experiment history, benchmark dumps and long rationale in the relevant issue, PR or canonical document instead of duplicating them here.
