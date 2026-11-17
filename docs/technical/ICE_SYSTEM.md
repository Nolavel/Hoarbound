# The frozen sea — architecture

Status: **implemented** (`scripts/systems/ice/`)
Tests: `tests/systems/test_ice_field.gd` — run via `tools/ci/run_tests.sh`
Tool: `tools/runtime/capture_ice_map.gd`

---

## 1. What it is

The sea around the island is ice, not water. Walking out from shore it thins,
creaks, cracks and gives way, and falling through is a survival emergency
rather than a death. It is the slice's signature moment.

## 2. Cost: constant, whatever the bay's size

The sea is a grid of tiles, but **only the tiles around the player are ever
touched**. `active_radius_tiles = 2` gives a 5×5 window — twenty-five tiles,
regardless of whether the bay is one hectare or twenty. A test asserts the
window does not grow when the player is four kilometres offshore.

Tiles are stored sparsely: a tile that has never been walked on has no entry at
all, and reports its base thickness computed from geometry. Memory tracks where
the player has actually been, not the size of the map.

## 3. Thickness

Base integrity comes from distance to the island outline:

```
distance <= solid_until_m (12 m)   ->  1.0, fully solid
distance >= thinnest_from_m (90 m) ->  minimum_thickness (0.18)
between                            ->  linear interpolation
```

The outline is a `shore_polygon` on the XZ plane, so it reuses the same kind of
polygon data `locations_data.json` already stores for zones. `distance_to_shore()`
returns negative on land, which is also how the field knows where ice is not.

`minimum_thickness` is deliberately not zero. Ice that is 0.0 far out is an
invisible wall; ice at 0.11 is a risk the player can choose to take.

## 4. The ladder

Integrity drives four stages, and **the order is a guarantee, not a
convention**:

| Stage | Integrity, as a share of the tile's own thickness | Feedback |
|---|---|---|
| `SOLID` | above 62 % | nothing |
| `CREAKING` | below 62 % | **audio only** — "you can still turn back" |
| `CRACKING` | below 32 % | cracks, camera shake, faster creaking — "turn back now" |
| `BROKEN` | 0.0 | the tile gives way |

The thresholds are relative on purpose. Read as absolute integrity, thin ice far
out would sit in `CRACKING` before anyone stepped on it, and the warning that is
meant to come first would never sound.

A test walks a tile all the way down and asserts the first warning emitted is
`CREAKING`, not `CRACKING`. The player always gets a warning they can act on
before they get one they can only react to. If a future change reorders these,
the suite fails.

`stage_changed` fires only on transitions; `load_tile_changed` fires every step
for the loaded tile, which is what a shader mask and a creak loop want.

## 5. Load and recovery

Standing on a tile drains it; gait scales how hard:

| Gait | Multiplier |
|---|---|
| Crouch | 0.45 — the careful way across |
| Still | 1.0 |
| Walk | 1.6 |
| Sprint | 8.0 — running the bay is the gamble |

What matters is load **per metre**, not per second: sprint covers ground twice
as fast as walking (`MovementController`: 8 vs 4 m/s), so it spends half as long
on each tile. At the old 3.2 against 1.6, sprint and walk put exactly the same
load on every metre of ice — which is why sprinting was never the gamble. At
8.0 a sprint loads each metre 2.5 times harder than a walk.

`IceGaitBinder` supplies this. It reads `MovementController.is_currently_sprinting()`
and the body's horizontal velocity and pushes the result into the field — an
adapter, so `MovementController` itself is untouched and stays in nobody's way.
Vertical velocity is ignored, so falling is not mistaken for running.

**There is no crouch in the project.** No input action, no controller state. The
0.45 multiplier is therefore currently unreachable, and `IceGaitBinder` reports
`CROUCH` only if someone binds `crouch_action`. That matters for design: the
careful way across the ice does not exist yet, so right now the player's only
choices are walk or gamble. A test asserts `CROUCH` is never reported while no
action is bound, so this cannot be forgotten silently.

Stepping off lets a tile recover at `recovery_per_second`, capped at its natural
thickness, so a bay can be crossed repeatedly but not carelessly. Broken tiles
never come back: the hole stays in the world.

## 6. Falling through

`ColdWaterImmersion` listens for `tile_broke`. Going under:

1. Soaks clothing to 1.0 immediately — which strips most of the clothing
   insulation in the thermal model, so the cold bites long after climbing out.
2. Drains body temperature at `immersion_body_loss_per_hour` (14 °C/h), billed
   in game hours like every other survival rate.
3. Stops the ice simulating until the player is out.
4. Refuses to let the player climb out for `climb_out_delay_s`. The thrash is
   the beat; an instant exit would make the whole thing a stumble.

This is the *Long Dark* lesson: the trap is a story, not a reload. The player
survives the water and then has to solve the cold.

`ThermalManager.apply_body_temperature_delta()` is the seam this uses — a public
method for events the ambient model does not cover, rather than the immersion
reaching into private state.

## 7. What the map tool is for, and what it already found

`tools/runtime/capture_ice_map.gd` draws the bay top-down: thickness shading,
the shore route against the ice shortcut with both distances, and a simulated
sprinted crossing. It prints a verdict.

The first measurement, on the original tuning, reported a free shortcut: a
sprint survived because mid-bay ice (0.18) was thicker than a sprint could drain
from one tile, and because the tool itself assumed a 5.5 m/s sprint instead of
the controller's 8.

**Retuned by the author's call in issue #7** — thinner ice and a heavier sprint,
no crouch:

| Setting | Was | Now |
|---|---|---|
| `solid_until_m` | 12 | 8 |
| `thinnest_from_m` | 90 | 26 |
| `minimum_thickness` | 0.18 | 0.11 |
| `drain_per_second` | 0.055 | 0.0375 |
| `sprint_multiplier` | 3.2 | 8.0 |

On the same bay (deepest point of the route 38 m out) a sprint now breaks
through about 29 m from shore, mid-bay, while walking crosses intact, slow walk
included. `test_ice_field.gd` locks this in, so a later retune that makes the
shortcut free again fails the suite.

**Rescaled for real walking speed (2026-09-24).** Walk went 4 → 1.5 m/s and
sprint 8 → 4.5 m/s. Drain is per second, so a slower gait stands longer on
each 4 m tile. `drain_per_second` 0.0375 → 0.0140625 (× 1.5/4) keeps the damage
per tile walked identical. `sprint_multiplier` 8 → 12 does the same for the
sprint. The walk-holds / sprint-breaks test is unchanged.

One consequence to know about: standing still on the thinnest ice breaks it in
about eight seconds. The bay is for crossing, not for stopping on.

## 8. Not built yet

- **Visuals and audio exist only in the isolated lab** (`tests/scenes/ice_lab.tscn`,
  §9). No game scene uses `IceField` yet; Coast / Thin Ice is a later slice.
- **No swim state.** `ColdWaterImmersion` owns the timing and the cold. In the
  lab Henry stands chest-deep on a lake bed inside the hole and the lab director
  places him on the rim; the character controller still has no in-water movement.
- **Broken tiles do not persist.** The ice is not a save participant yet, so
  holes vanish on load. `IceField` needs the save contract.
- **Crouch exists now** (`MovementController.is_crouching()`, Ctrl), and
  `IceGaitBinder` reports `CROUCH` from it; §5 is out of date on this point.
- **No wind direction or snow cover.** Thin ice hidden under fresh snow is the
  obvious next twist, and the weather profiles already carry snowfall density.

## 9. The lab — cracks, hole and sound (isolated)

`tests/scenes/ice_lab.tscn` is a standalone scene with Henry, a shore and 64 × 64 m
of bay ice. It is the only place the presentation below runs.

| Stage | What the player gets | Owner |
|---|---|---|
| `CREAKING` | groan loop, louder with load — **nothing drawn** | `IceCrackPresenter` |
| `CRACKING` | cracks from the load point, a crack sound and a camera shake per growth step | presenter + `thin_ice.gdshader` |
| `BROKEN` | jagged hole under Henry, shards, splash, fall to chest-deep water | presenter, `ice_hole_fx.tscn`, `IceLabDirector` |

- **Data and presentation stay separate.** The presenter reads `IceField` signals
  and never writes to it. Crack growth is presentation memory: it only grows, so
  cracks stay visible after the ice recovers.
- **Maps.** A window of `window_tiles`² texels: the crack map holds growth and
  the crack origin, the hole map holds the hole flag and its centre. The shader
  draws cracks from the 3 × 3 neighbouring tiles in world space, so there is no
  tile seam.
- **One hole outline.** `IceHoleShape.radius_at()` defines it and the shader
  mirrors it with integer-only phases. The fall-in check and the drawing agree.
- **Sounds** are deterministic placeholders from `tools/audio/synth_ice_sfx.py`.
- **Evidence.** `test_ice_crack_presenter.gd`, and the stills from
  `tools/runtime/capture_ice_lab.gd`.

Before this goes into the game:
- the window must follow the player, as the snow window does;
- the camera shake belongs in the TPS camera solver, not in a lab node;
- real recordings must replace the placeholder sounds;
- the ice needs a save participant in the game world.
