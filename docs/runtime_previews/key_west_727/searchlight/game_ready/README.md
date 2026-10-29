# NORTHBEAM game integration review

The owner approved the Blender geometry. The reproducible source is
`assets/items/searchlight/source/candidate_v2/searchlight_geometry_review.blend`;
`tools/blender/finalize_searchlight.py` bakes a 1024² BC, normal and ORM atlas
and exports the game GLB. The GLB contains 9,932 triangles, four meshes and
four materials, retaining separate glass and NORTHBEAM markings. Mesh QA passes
with two reported seam/contact warnings; the atlas budget check passes.

The `searchlight` ItemResource is CARRIED and weighs 2.8 kg. The single authored
727 pickup has world ID `searchlight_727_reception` and sits on the reception
counter beside the entrance. It uses the existing pickup
ledger, inventory and right-hand HeldFit. The Hub Use route draws it from the
pack. RMB toggles the held SpotLight3D; per-instance inventory state retains the
switch value across save/load, while stowing removes the live light.
The 727 runtime capture asserts that the pickup is on the reception countertop
within 3 m of the entrance, then picks it up through `ItemPickup` and presents
the owned item. It has its own persistent world ID, so a taken copy stays gone.

Light: warm SpotLight3D, energy 12, range 18 m, 27° cone, shadows enabled,
shadow bias 0.03 and normal bias 0.3. Lens glow is a separate unshaded optical
card over the clear glass. Forward+ fog energy 0.12 and local FogVolume density
0.012 keep atmospheric scatter subtle. The inertia solver is critically damped
with a 0.13 s response and bounds of 5° and 0.03 m; the same result drives the
hand solver and model rather than delaying the TPS camera.

Validation: Godot 4.8-dev6 .NET import and dotnet build passed. The focused
`tools/runtime/test_searchlight.gd` checks item size, optical nodes, lamp
shadows, on/off, inventory state save/load, pickup ledger save/load and spring
bounds. The 727 capture uses Forward+/Vulkan on llvmpipe at 640×360. This is a
software GPU; its timing is not a target-hardware performance result. The
144-frame indoor capture took 335 s including PNG writes and two viewports.
Neither a target-GPU frame cost nor a hardware visual review has been measured.

`off.png` and `on.png` use the same camera and night hour. `outside_on.png`,
`outside_walk.png`, and `outside_off.png` document the outdoor and switch-off
states. `searchlight_727.mp4` is a 15 s capture: indoor camera turn, outdoor
walk, then off/stow. The captured indoor beam is heavily occluded by Henry,
and the outdoor frames are too dark to judge the lens detailing. The hand/beam
placement and optical appearance need another art pass and a hardware review
before treating this as a final game-ready lighting result.

Daylight review (12:00, Forward+/Vulkan llvmpipe): `727_lit.png` shows Henry
with the searchlight switched on in the actual 727 scene; `henry_grip.png`
shows the right hand and handle at close range. These frames use the same
runtime item, rig and light as the night capture, with normal 2.0 exposure.
