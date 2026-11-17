# Archived guided TPS camera

The third-person camera Hoarbound used until 2026-11-11, kept whole so it can be read, compared or brought
back. The owner replaced it with the direct rig after playing both: the direct rig answers the mouse and
leaves the view alone; this one framed Henry by itself.

What it did that the live camera does not:

- lifted over Henry's shoulder (up to 70 degrees) and looked down at him with his back to a wall;
- swung round him to find room, turned the view by itself after the mouse rested (auto-look, whiskers,
  recentre behind a sprinting Henry);
- crossed to the other shoulder by itself when one side was walled off;
- closed its frame before a doorway, held the orbit in the doorway's cone, eased the mouse into soft stops
  there, and carried Henry through once he had crossed the door plane (`carry_through`);
- widened the shoulder or crossed to the other one by itself when the mechanism under the crosshair stood
  behind Henry on screen (`tps_interaction_framing.gd`, archived 2026-11-12: in door D1 it fired on hundreds
  of frames and crossed shoulders with no key pressed);
- moved the boom onto the centre line (recompose) and held Henry's eyes at a fixed place in the frame in
  tight rooms (composition); slowed the mouse near his body (body guard).

## Contents

| Path | What |
|---|---|
| `camera/` | Every `tps_*.gd` of `scripts/systems/camera/` and `passage_traversal_component.gd`, as last wired together |
| `tests/` | `test_tps_camera`, `test_doorway_camera`, `test_passage_traversal`: its guarantees, with `direct_rig = false` |
| `docs/TPS_CAMERA_guided.md` | Its full design record: every behaviour, its reference and its trace numbers |

The folder carries `.gdignore`: Godot does not load these scripts, so their class names do not collide with
the live ones.

## Seeing it run

It was last wired into the game at commit `a5bad6ca` (`TpsCamera.direct_rig = false`,
`PassageTraversalComponent.carry_through = true`). Check that commit out to play it or run its suites:

```
git checkout a5bad6ca
tools/ci/run_tests.sh test_tps_camera test_doorway_camera test_passage_traversal
```

To bring one behaviour back into the live camera, port its `TpsRig*` class from `camera/` and call it from
`TpsCamera._update_rig`; each is a `TpsRigBehaviour` that reads and writes one `TpsRigFrame`.
