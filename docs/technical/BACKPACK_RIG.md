# Backpack rig — knowledge map (#260)

The one place that says where every part of Henry's backpack is, why it is there, and which check
keeps it there. **Change a value here and in code together, run the stand, and only then render.**

Stand: `godot --headless --script tests/systems/test_backpack_rig.gd` (seconds, no render).
Inspector: `tools/runtime/inspect_backpack.gd -- <dir>` (pictures plus a fault report, on demand).
Worn video: `tools/runtime/capture_backpack_worn.gd -- <dir>` (slow, only when asked).

## Spaces

| Space | Origin and axes | Used by |
|---|---|---|
| Pack space (`BackpackModel`) | origin at the bottom of the back face; +Y up, +Z out to the front panel, +X right | canvas, slots, pockets, handle, bedroll, loops |
| Skeleton rest space | Henry's model at rest; faces +Z, +X is his left; spine_03 at (0, 1.3148, -0.0049) | strap anchors, coat measurements |
| `PackRig` | on spine_03 via `BoneAttachment3D`; -Z away from Henry | sway pivot, canvas fit (`BODY` scaled to `backpack_size`) |

`.tscn` stores a `Transform3D` basis **by rows** (`x.x, y.x, z.x, x.y, …`). Writing it by columns
swaps the anchor normals and twists the straps.

## Body and coat (measured, rest pose)

| Fact | Value | How |
|---|---|---|
| Coat back at the shoulder blades / at the pack bottom | z −0.21 / −0.135 | rays on `Outfit_Jacket` |
| Collar and hood ring | out to 0.178 from the spine axis, y 1.49–1.61 | `Outfit_Hood` bounds |
| Shoulder joint | about 0.20 out | bones |
| Coat side under the arm (y ≈ 1.2) | 0.155–0.16 out | rays |
| Idle pose | hunched: spine_03 about 7 cm lower than rest | bone poses in play |

## Worn pack placement (`HenryUALAnimation`)

| Value | Setting | Why |
|---|---|---|
| `backpack_offset` | (0, −0.03, −0.285) | back face just outside the coat |
| `backpack_lean_deg` | 12.5 | back face follows the coat's back line, so the bottom does not stick out |
| Sway (`PackRig`) | pivot at the middle of the back face, at most 2.5° | rocks a little when Henry starts and stops |

## Shoulder straps (`PackShoulderStraps`, `pack_strap_anchors.tscn`)

Anchors are Marker3D on BoneAttachment3D, given here for Henry's left (+X). The right side is
mirrored onto the `_r` bones. Each anchor's Y axis is the coat's outward normal there.

| Anchor | Bone | Rest position | Outward normal |
|---|---|---|---|
| UpperBack | clavicle_l | (0.15, 1.50, −0.16) | (0.1, 0.4, −1) |
| ShoulderBack | clavicle_l | (0.17, 1.525, −0.10) | (0.2, 0.9, −0.5) |
| Shoulder | clavicle_l | (0.18, 1.53, −0.02) | (0.3, 1, 0) |
| ShoulderFront | clavicle_l | (0.172, 1.505, 0.045) | (0.25, 0.8, 0.6) |
| ChestHigh | spine_03 | (0.15, 1.44, 0.085) | (0.2, 0.6, 1) |
| ChestLow | spine_03 | (0.15, 1.33, 0.108) | (0.3, 0, 1) |
| Armpit | spine_03 | (0.168, 1.26, 0.06) | (0.7, −0.1, 0.7) |
| UnderArm | spine_03 | (0.163, 1.205, −0.03) | (1, −0.1, −0.1) |

- Along the body the strap is a curve through the anchors, padded from UpperBack to ChestHigh.
- Free runs are **straight**: from the pack's top (pack space (±0.11, 0.36, −0.016), sewn below the
  top so the strap rises onto the shoulder) to UpperBack, and from UnderArm to the pack's bottom
  corner (±0.14, 0.05, −0.016). They have no chain and no slack, so they never swing.
- Off his back (set down) each strap is one limp verlet loop from top to bottom corner, on the floor.
- A band never flips: each normal is kept on the same side as the last.

## Canvas, pockets, top (`BackpackModel`, `backpack_canvas.gdshader`)

| Part | Value | Rule |
|---|---|---|
| Body `BODY` | 0.34 × 0.52 × 0.22, edges rounded 0.06 | — |
| Main items | shape shell, panel and back strips only | never the pockets |
| Side pockets | centre x ±0.205, half (0.04, 0.07, 0.065), rim at y 0.17 | each its own material |
| Pocket holding an item | cloth wraps the item box plus 4 mm lining; cloth that starts inside the item goes all the way out | the item never shows through |
| Empty pocket | outer cloth flat on the wall: 0.17 + 0.006 + 0.075 × 0.08 = 0.182 out | mouth closed, creased |
| Pocket item slot | 1 cm outboard of the pocket middle | clear of the body wall |
| Loops | sewn at the pocket's rim (y 0.168, z 0.11) on its cloth as it is now (`pocket_outer_x`); hang out and down 60° for 3.2 cm | follow full or empty pocket |
| Carabiners | pivot (inside top of the ring) 2.8 cm down the loop (`loop_hold_point`); ring plane along the wall | ring through the loop's lower end |
| Clipped item | double pendulum: carabiner in loop, item on the rod; each hanger keeps its direction in world space, so it lags when its parent turns or swings | swings fore-aft and sideways |
| Side-pocket flask | the thermos (`Thermos.glb`, 7.5 cm across, 24 cm tall) stands in the left pocket; its lid hinges on the -X side of the collar | — |
| Mug on the rod | the handle's upper bend (2.2 cm below the rim, 1.2 cm inside its outer edge) sits on the rod at the ring's bottom; the handle's hole (mug Z) runs along the rod (ring body X); the mug stands upright and hangs out from the wall | hole along the rod |
| Handle | node on the canvas top at (0, 0.514, 0.03), placed every frame | moves with the slumping top |
| Bedroll | across the top at (0, 0.52, 0.14), radius 0.062, presses in 8 mm | flat bottom: the pack stands anywhere |
| Zip | two sliders from the top centre; the panel folds only above them; the unzipped edge stands 1.5 cm proud | — |
| Look | grey canvas, leather base below 8.5 cm with stitches, maker's patch, creases, painterly breakup, banded light | — |

## Springs

Sway, panel swing and droop, fill, and the carabiner and clipped-item pendulums are stepped
explicitly. A hitch's long frame (seconds while Reality loads) blew them to NaN, and the pack then
drew lying on its side. Every spring step is capped at 0.05 s, and anything non-finite is reset.
`PendulumHang` keeps its state in world space and clamps it in its parent's space: a hanger held in
parent space turned rigidly with its parent, so the mug never swung on the carabiner.

## Rules the stand checks (`test_backpack_rig.gd`)

| Rule | Check | Limit |
|---|---|---|
| R1 | the canvas shows the pack's pockets: two loose cans, the flask in a side pocket, the mug clipped on | exact |
| R2 | 8 anchors a side, straps on both shoulders, the strap mesh drawn, top ends on the pack | 5 mm |
| R3 | each loop sewn on its pocket's live cloth and hanging down; each carabiner in its loop's lower end; the mug's handle on the rod with its hole along the rod, the mug outboard; the clipped item at most 2 cm below the bottom | 5 mm / 2 mm / 5 mm, 0.9 / 2 cm |
| R4 | pocket items out of the main cavity | 0 |
| R5 | the empty pocket's outer face on the wall | wall + 2 cm |
| R6 | handle on the top; bedroll resting on it | 5 mm / 0–15 mm in |
| R7 | walking and stopping: chest anchors ride the chest bone; pack sway within its cap | 2 mm / 2.5° |
| R8 | a 1 s hitch leaves every spring finite and the pack upright | finite / up.y > 0.95 |
| R9 | starts, stops, a sidestep and a turn: both carabiners and the clipped item swing fore-aft and sideways against their parents | ≥ 6° each way |

The inspector adds: item overlaps, main items poking past the canvas give, and pocket cloth
left inside its item (mirroring the shader's wrap).
