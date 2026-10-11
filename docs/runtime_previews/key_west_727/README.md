# 727 Fort St shelter — captures

`tools/runtime/capture_key_west_727_interior.gd` takes these inside the real
`key_west_reality.tscn` (World, weather, snow and streaming; lavapipe, downscaled to
960×540).

- `approach_fort_st`, `porch_door`: the measured exterior, the porch roof and the main
  door with its entry ramp.
- `cutaway_plan`, `cutaway_oblique`: roof and ceiling hidden, so the furnished
  game-invented clinic plan shows.
- `lobby_from_door`, `waiting_stove`, `waiting_to_lobby`: the heated shelter zone, with the
  hut stove, cabinet, mattress and rest crate.
- `corridor`, `exam_room`, `dental`, `storage_benches`: the unheated clinic rooms. The hut
  tool and supply benches are in storage.
- `henry_by_stove_game_camera`: Henry in the waiting room, seen through the TPS game camera.

Snow particles inside are the weather VFX, which does not know about roofs. The legacy hut
behaves the same.
