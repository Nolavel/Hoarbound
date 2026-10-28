# Vitals HUD

Bottom-left survival block (`scenes/ui/hud/vitals/vital_hud.tscn`, `VitalCluster`, `HealthStrip`).
Owner-approved on 2026-10-23 (issue #236, stages 0–1 plus the silhouette of stages 3–4).

## Layout (1080p, anchored bottom-left)

From top to bottom, 20 px from the left edge:

1. **Silhouette** (96 px tall) standing over the warmth column.
2. **Rising chevrons** above any column whose value climbs.
3. **Four columns**: thirst, hunger, sleep, warmth. Each is 36 × 112 px with 16 px gaps
   and rounded bottom corners.
4. **Falling chevrons** under any column whose value drops.
5. **Health strip**: 260 × 16 px, 20 px above the bottom edge.

Body temperature (`34.9°`) sits beside the warmth column at about 60 % of its height.
`FEELS −27°` sits at its foot. Both use IM Fell English SC with a dark outline.

## Columns

- **Back**: `shaders/ui/vital_column.gdshader` in `back_color`. It is dense at the bottom and fades
  to transparent at the top.
- **Pigment**: the same shader, inset, tinted by state. It **empties from the top down** to
  the vital's level, with a thin edge line along its cut.
- **Colour**:
  - green above the warning level, yellow between warning and critical, red below critical;
  - blended across a ±0.06 band at each threshold (`state_color_for`), never switched;
  - the drawn fill and colour ease toward the value (`display_rate`).
- **Thresholds**:
  - thirst, hunger, sleep: `warning_progress_threshold` 0.66 and `critical_progress_threshold` 0.33;
  - warmth: the `ThermalManager` stages. CHILLED (36 °C, 0.93) starts yellow and HYPOTHERMIC
    (33 °C, 0.58) starts red (`ThermalManager.get_stage_threshold_normalised`). 31 °C,
    the CRITICAL stage, can no longer read yellow.
- **Symbol** (`shaders/ui/vital_icon.gdshader`):
  - half-tone (desaturated, about 40 % opacity) while safe;
  - sharpens to full colour, tinted by state, as it nears critical (`vividness_for`);
  - a drain nudges it, a refill swells it.

## Trends

Over each 1.5 s window a move of at least 0.002 shows one chevron, and a move of 0.01 or more shows two.
Chevrons sit above the column when rising and below it when falling, in the column's colour.

## Temperatures

- **Body temperature** (grey, small): `ThermalManager.get_body_temperature_c()`. It is the game's
  representation of Henry's core, not a device reading.
- **FEELS**: `get_felt_temperature_c()`, the felt temperature *where Henry stands*: air, weather,
  shelter, wind through the clothes' windproofing, nearby fires and exertion. Clothing insulation is
  not in this number; it shows in the warmth trend and on the silhouette.
- Strings `HUD_BODY_TEMPERATURE` and `HUD_FEELS_LIKE` (`localization/strings.csv`). By the owner's
  choice the Russian column also reads "FEELS".
- Outdoor air follows `data/climate/air_temperature_day.tres` (ThermalManager's default curve between
  `ambient_min_c` −28 °C and `ambient_max_c` −8 °C). It is coldest at 05:30 (−28), about −11 at noon,
  warmest at 14:30 (−8), about −20 at 21:00 and −23 at midnight. Weather offsets add on top
  (blizzard about −6).
- The felt temperature is computed on world ready and on load
  (`ThermalManager.refresh_felt_temperature`), not only at the next quarter-hour clock step.

## Silhouette and extremity cold

- **Masks**: `assets/textures/ui/game/biomonitor/body_front/` (base, head, hands, feet), derived
  from MIT data (see `LICENSE.txt` there). The base is drawn at 11 % opacity.
- **Frost** (`shaders/ui/vital_frost.gdshader`): blue frost creeps from the extremity tip inward
  as load rises: fingertips to forearms, toes to ankles, crown down.
- **Load** comes from `ExtremityCold`, which `ThermalManager` owns
  (`get_extremity_cold(&"head" | &"hands" | &"feet")`):
  - effective region temperature = felt + the region's garment insulation − its wetness × 8 °C;
  - load 0 at −5 °C, full at −35 °C;
  - it builds at rate 1.5 per game hour and eases at 2.5 per game hour;
  - cover per region comes from `EquipmentComponent.get_region_protection` (garment `body_region`);
  - there are no gloves yet, so the hands are bare.
- Warm sleep (`restore_body_temperature`) clears the load. It is saved in the `thermal` save
  (`extremities`); old saves load with no frost.
- This is a warning layer, not an injury system. Consequences are stage 6 of #236 and need the
  owner's decision.

## Body part library

Body parts are data, not code (`core/body/`, `data/body/`).

- **Library.** `BodyPartLibrary` (`data/body/body_parts.tres`, loaded by path like `ItemCatalog`) lists
  the `BodyPartDefinition` resources.
- **Definition fields:**
  - `id`;
  - the garment `body_region` that covers the part;
  - `wind_exposure` (the share of wind chill that reaches it);
  - `cold_sensitivity`;
  - `safe_c` / `severe_c`;
  - the HUD `silhouette_mask` and `frost_from_top`;
  - the skeleton `bones`, kept for later visual effects.
- **Current parts:**

  | Part | Wind exposure | Sensitivity | Bones |
  |---|---|---|---|
  | head | 1.0 | 1.0 | `Head`, `neck_01` |
  | hands | 0.8 | 1.15 | `hand_l`, `hand_r` |
  | feet | 0.35 | 1.0 | `foot_l`, `foot_r` (name assumed from the same rig convention) |

- **Effective temperature per part:** felt air without wind, minus the wind chill × the part's
  exposure × (1 − its cover's windproofing), plus its cover's insulation, minus its wetness × 8 °C.
  `ThermalManager` hands the cold model the still air and the raw wind chill separately.
- **Adding a part** (ears, eyes) is a new definition plus a mask on the silhouette frame. The cold
  model, the save and the HUD pick it up without code.

## Frostbite consequences

- **Stages by duration, per part** (`ExtremityCold.FrostStage`):
  - **Frostnip**: the load held at or above `frostnip_load` (0.6) for `frostnip_hours` (0.33 h).
  - **Frostbite**: the load held at or above `frostbite_load` (0.85) for `frostbite_hours` (0.6 h),
    about half an hour at a −28 °C wind chill (Environment Canada wind chill tables).
  - Time above a threshold decays while below it, so a brief chill does nothing.
  - **Recovery**: frostnip clears after `frostnip_heal_hours` (0.25 h) at or below `thaw_load`.
    Frostbite steps back to frostnip only after `frostbite_heal_hours` (6 h) warm.
    Warm sleep (`restore_body_temperature`) clears every stage.
  - The stages and their timers are saved in the `thermal` save; the first layout (a bare load
    per part) still loads.
- **Afflictions**: `ThermalManager.frost_stage_changed` drives a frostnip / frostbite affliction per
  part (`resources/status/frost*_*.tres`, referenced from the part definition). `AfflictionComponent`
  registers them from the library.

  | Affliction | Modifiers | Health per game hour |
  |---|---|---|
  | frostnip_hands | fine motor ×1.35, work ×1.15 | — |
  | frostbite_hands | fine motor ×1.7, work ×1.35 | 4 |
  | frostnip_feet | movement ×0.92, sprint ×0.5 | — |
  | frostbite_feet | movement ×0.8, sprint ×0 (no sprint) | 4 |
  | frostnip_head | fatigue ×1.05 | — |
  | frostbite_head | fatigue ×1.1 | 5 |

- **Health**: frostbite drains it through `PlayerHealthSystem.drain`. There is no damage shake or
  immunity window, regeneration stops, and it can kill.
- **Where the modifiers act**: `StatusModifierCapability` (`core/contracts/`). `AfflictionComponent`
  publishes it on the player, and consumers read it without the string calls they used before:
  - `MovementController`: speed and the share of the sprint left (0 = no sprint);
  - `TimeCostedActionSystem`: work, i.e. laying a log or tinder;
  - `FatigueComponent`;
  - `HeatSourceFeed.get_light_seconds()`: the lighter hold, 3 s → about 5 s with frostbitten hands.

## Gloves

`work_gloves` (`data/items/work_gloves.tres`) is a garment in the new `hands_outer` slot: insulation
4 °C, windproofing 0.6, waterproofing 0.3. The hands' cold load reads it through
`get_region_protection`.

**Visual**: `Outfit_Gloves` comes from `tools/blender/build_henry_outfit.py`. It is cut from the mannequin's hands and
fingers from the wrist up, under the sleeve's cuff, and decimated to about 6,000 vertices. Panels follow the owner's
reference: olive back, tan knuckles and fingertips, dark palm. `Outfit_GloveCuff` is the insulated gauntlet over the
sleeve, with a strap and a red pull tab.
`HenryUALAnimation.GARMENT_PARTS["Gloves"]` shows it while worn and hides `Skin_Gloves`. Rebuild it with Blender 5.2
as a Python module: `pip install bpy`, then `python tools/blender/build_henry_outfit.py [--render dir]`.

**Placement**: the top shelf of the 727 cabinet, beside the mug (`GlovesShelter` in
`first_exit_gameplay.json`, owner's choice). Capture: `tools/runtime/capture_gloves.gd`.

## Room warmth persistence

`ShelterState` saves each zone's accumulated fire warmth (`heat`, by zone name). A streamed-in or
loaded zone gets it back through `ThermalZone.restore_heated_offset` (capped at
`max_heated_offset_c`), so a warmed house stays warm across chunk streaming and saves.

## Verification

- Tests:
  - `tests/systems/test_vital_cluster.gd`: colours, blending, symbol vividness, warmth thresholds;
  - `tests/systems/test_cold_readouts.gd`: extremity model, stage thresholds, room warmth.
- Capture: `tools/runtime/capture_vitals_hud.gd` (blizzard, critical night, thawing at the stove).
