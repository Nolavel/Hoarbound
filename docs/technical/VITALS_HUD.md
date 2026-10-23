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

## Room warmth persistence

`ShelterState` saves each zone's accumulated fire warmth (`heat`, by zone name). A streamed-in or
loaded zone gets it back through `ThermalZone.restore_heated_offset` (capped at
`max_heated_offset_c`), so a warmed house stays warm across chunk streaming and saves.

## Verification

- Tests:
  - `tests/systems/test_vital_cluster.gd`: colours, blending, symbol vividness, warmth thresholds;
  - `tests/systems/test_cold_readouts.gd`: extremity model, stage thresholds, room warmth.
- Capture: `tools/runtime/capture_vitals_hud.gd` (blizzard, critical night, thawing at the stove).
