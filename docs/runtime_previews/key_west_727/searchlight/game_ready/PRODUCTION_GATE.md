# NORTHBEAM pre-main production check

Scope: battery indicators and runtime in `codex` (`93dba44a`), on top of the
already integrated searchlight item. The four existing windows are rendered as
dim emissive overlays; the lamp remains the only light source. Battery life is
48 game hours, recorded per item in `searchlight_runtime_hours`.

## Verified locally

- Godot 4.8-dev6 .NET import and script compilation: clean.
- .NET solution build: 0 errors, 0 warnings.
- Input bindings: 30 bindings, no undeclared overlaps.
- Filename/UID gate: clean after removing two tracked orphan camera `.uid` files
  whose source scripts and scene references no longer exist.
- `tools/runtime/test_searchlight.gd`: charge thresholds, saved runtime, fade,
  intermittent output below 1%, and full shutdown at zero passed.
- `tests/systems/test_pickup_gesture.gd`: a real F tap stores NORTHBEAM; the
  stored CARRIED item can be drawn into the right hand.
- 727 runtime clock check: a quarter game hour with the lamp on advances its
  saved runtime; a second quarter hour after stowing does not.
- Forward+/Vulkan llvmpipe captures: four green, two green/two red, low charge,
  and no LED emission at empty were visually inspected. The original 727 night
  and daylight captures were also reviewed.
- Eight daylight 727 Forward+/Vulkan `grip_orbit/` captures show a continuous,
  torso-relative beam sweep within ±65°; the palm frame follows the grip
  without the arm turning through the character's back. The first orbit review
  exposed fingers aligned along the handle, which did not form a grip. The
  corrected captures replace those frames: fingers now cross the lengthwise
  handle and curl around it.
- `lens_aura.png` and `lens_divine.png` are both bound to the lens shader and
  combined for optical glow. The scene beam uses the single `SpotLight3D`.

## Open before unconditional main acceptance

The full system runner executed 116 suites. It flagged six with a shortened
90-second per-suite timeout. `test_doorway_camera.gd` passed on a repeat with
the normal 180-second timeout. Five failures remain:

1. `test_key_west_reality_hlod.gd`: script accesses index 0 of an empty array.
2. `test_render_layers.gd`: layer 21 is not named `snow_tile_experiment`.
3. `test_snow_architecture_contract.gd`: expected multi-channel deformation
   contract does not match current implementation.
4. `test_snow_contact_pipeline.gd`: walking contacts still write the live
   heightfield contrary to the test contract.
5. `test_snow_surface_clipmap.gd`: expected radial L0/L1/L2 installation is
   absent.

Those suites and their owning snow/HLOD/render-layer files are unchanged by
the NORTHBEAM battery commit. They were not separately rerun on `main`.

The night 727 capture remains very dark around Henry. A controlled 2 cm
forward lamp-position experiment did not visibly improve it and was reverted.
Night art direction needs further review; target-GPU performance is unmeasured
because the available Vulkan device is llvmpipe. These are limits of the
current evidence, so this check does not certify the new battery work as a
fully production-ready main integration.
