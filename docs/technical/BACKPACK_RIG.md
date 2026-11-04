# Backpack rig — knowledge map (#260)

The one place that says where every part of Henry's backpack is, why it is there, and which check
keeps it there. **Change a value here and in code together, run the stand, and only then render.**

Stand: `godot --headless --fixed-fps 30 --script tests/systems/test_backpack_rig.gd` (seconds, no render);
its `## ci-args:` line makes `tools/ci/run_tests.sh` pass the same flag.
Without `--fixed-fps 30` headless frames are not 1/30 s, and the swing rules read nonsense.
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
| Side pockets | centre x ±0.205, half (0.04, 0.07, 0.065), mesh y 0.03–0.17 (`POCKET_CENTRE_Y` ± half); rim `POCKET_RIM_Y` 0.17; the right one is open at the bottom too | each its own material |
| Sleeves | `SLEEVE_SLOTS`: the left pocket whole (`side_left`), the right pocket's front (`side_right_front`, z > 0.11) and back (`side_right_back`) halves; one item each; equipment pockets `pack_side_left`, `pack_side_right_front`, `pack_side_right_back` | one shader holds two items per pocket |
| Divider | dark cloth (`SleeveDivider`) at z 0.11 from the body to the outer cloth, pocket bottom to rim, rebuilt each frame on the cloth as it is | splits the right pocket |
| Tools in sleeves | axe front, hammer back; hung by the head: the head's underside (`head_bottom` meta: axe 0.30, hammer 0.291) 2 mm above the rim, handle through the open bottom, blade/face forward (tool X to pack +Z); x from the unslumped wall (a full pack's) plus lining plus the handle's half, then pushed out of the wall and of the other tool by any overlap; handles hang ~20 cm below the pack | heads clear the pack and each other |
| Sleeve cloth | each sleeve shrink-wraps its item's section as an upright ellipse (`handle_half` meta, axe 1.5 × 1.05 cm, hammer 1.38 × 0.98 cm; thermos a circle) round its axis (with the handle's bow); same hem flare/drag and push-in as the thermos | hugs to 0.5 mm, never inside |
| Pocket floor | `POCKET_FLOOR_Y` = mesh bottom + 4 mm lining = 0.034; what a pocket holds stands on it | derived from the mesh, never a slot constant |
| Pocket holding a boxy item | cloth wraps the item box plus 4 mm lining; cloth that starts inside the item goes all the way out | the item never shows through |
| Pocket holding a round item | the item's visual carries meta `round_radius` (thermos 0.0375); the cloth shrink-wraps the upright cylinder through the item's origin: nearest point on radius + lining (Blender Shrinkwrap, nearest surface point + offset); under the item's bottom it is a disc; the wall seam stays on the wall; normals turn to the cylinder's | hugs to 0.5 mm, never inside |
| Pushing an item in | a new side-pocket item starts with its bottom 5 cm above the rim and is pushed down: 0.6 m/s in the air, 0.28 m/s while its foot is in the hem (top 3.5 cm), 0.5 m/s inside, easing over the last 2.5 cm | ~0.4 s |
| Hem while it goes in | the entering foot flares the hem (top 2 cm) 9 mm past the item; friction drags the cloth down 0.03 m per m/s over the top 8 cm; cloth more than 0 to 3.5 cm under the item's bottom is still the empty pouch (funnel); both springs (4.5 Hz, damping 0.28) let go once it sits | stretches first, then hugs |
| Cloth rule | `BackpackModel.pocket_cloth_point` is the shader's twin, used by the loops, the inspector and the stand; change both together | — |
| Empty pocket | inner layer sewn on the body's rounded side (`body_side_x`: the box rounded 0.06, caved in as the shell slumps); outer layer 3 mm + 3% of its depth over it (≤ 5.4 mm); rim droops 12 mm | follows the body's curve, no gap |
| Pocket seam | the wall side of any pocket (empty, round or boxy item) lies on `body_side_x`, not on a flat x = 0.17 | on the body |
| Pocket item slot | 1 cm outboard of the pocket middle | clear of the body wall |
| Loops | sewn at the middle of the pocket (y `POCKET_CENTRE_Y` 0.10, z 0.11) on its cloth as it is now (`pocket_outer_x`, clear of the hem); hang out and down 60° for 3.2 cm | follow full or empty pocket |
| Carabiners | pivot (inside top of the ring) 2.8 cm down the loop (`loop_hold_point`); ring plane along the wall | ring through the loop's lower end |
| Clipped item | double pendulum: carabiner in loop (1.9 Hz, damping 0.18, stop 55°), item on the rod (1.8 Hz, damping 0.65, stop 60°; the pack is its real stop); each hanger keeps its direction in world space, so it lags when its parent turns or swings | swings fore-aft and sideways |
| Side-pocket flask | the olive-drab thermos (`Thermos.glb`, 7.5 cm across, 24 cm tall, no printed mark) stands in the left pocket; its lid hinges on the -X side of the collar | — |
| Frying pan on the left rod | `pack_carabiner_left` → carabiner 0. The pan hangs by its oval eye (`PAN_EYE` (0.25, 0.045, 0) in its model, 5 mm sag), handle up, the rod through the eye along the carabiner's X. It is a hinge like the mug | eye on the rod, pan never in the pack |
| Mug on the rod | the handle's upper bend (2.2 cm below the rim, 1.2 cm inside its outer edge) sits on the rod at the ring's bottom; the hole (mug Z) runs along the rod; hung on a pin it turns about the hole until its centre of mass (area-weighted shell centroid of its mesh) is straight under the rod, so it hangs tilted, rim outward | centre of mass plumb under the rod |
| Arm off the strap | `ArmStrapClearance` (worn only) treats the sleeve as a capsule round the upper arm, its radius the median distance of the jacket's upper-arm vertices from the bone. Strap points from the last drawn frames that the capsule meets (beyond the shoulder joint's first 30%) turn the arm at the shoulder by asin(overlap / lever), applied at once and easing back at 1.5 rad/s, capped at 25° | the sleeve never swallows the strap under the arm |
| Clipped item contact | `PendulumHang` leans what hangs off the pack instead of through it: signed distance to the body (box rounded 0.06), each pocket's cloth as placed this frame, and the tool handles as vertical capsules from their bottom to the rim; contact points one per 2 cm cell, each the vertex nearest its cell's mean (vertex clustering: no corner gaps, ≤ 1.45 cm from any vertex on the mug); a 6 mm margin (a 1.4 cm handle dips ~5 mm between points); a hanger counts every other point of what hangs from it; inelastic, with friction (half the swing's rate kept per touching frame) | never inside the pack or the tools |
| Mug hinge | the mug only turns about the rod (`hinge_axis`). Outside the obstacle last frame (within the margin counts): it stops where its own swing meets it (conservative advancement, bisection along the frame's swing) and goes no deeper than it was or half the 1.5 mm slop; deeper than the slop, it backs out the way it came, at most 0.02 rad a frame (a grazing contact needs degrees per mm, so it never jumps). Started inside (the pack moved into it): Newton steps on the deepest point's depth (position-based contact) find a clear turn, bisection backs it off to the least one, within its 90° limit; wedged, the least-deep turn tried. Only points within 6 cm of the obstacle join after the first pass | hole along the rod always; no frame-to-frame chatter in the held, tipped pack |
| Carabiner contact | it counts what hangs on it and leans out along the side's normal (`contact_out`) when that load touches; its own ring has no contact | steady, no chatter |
| Handle | node on the canvas top at (0, 0.514, 0.03), placed every frame | moves with the slumping top |
| Bedroll | across the top at (0, 0.52, 0.14), radius 0.062, presses in 8 mm | flat bottom: the pack stands anywhere |
| Zip | two sliders from the top centre; the panel folds only above them; the unzipped edge stands 1.5 cm proud | — |
| Look | grey canvas, leather base below 8.5 cm with stitches, maker's patch, creases, painterly breakup, banded light | — |

## Springs

Sway, panel swing and droop, fill, and the carabiner and clipped-item pendulums are stepped
explicitly. A hitch's long frame (seconds while Reality loads) blew them to NaN, and the pack then
drew lying on its side. Every spring step is capped at 0.05 s, and anything non-finite is reset.
The pocket hem's flare and drag springs are stepped the same way.
`PendulumHang` keeps its state in world space and clamps it in its parent's space: a hanger held in
parent space turned rigidly with its parent, so the mug never swung on the carabiner.

## Rules the stand checks (`test_backpack_rig.gd`)

| Rule | Check | Limit |
|---|---|---|
| R1 | the canvas shows the pack's pockets: two loose cans, the flask in a side pocket, the mug clipped on | exact |
| R2 | 8 anchors a side, straps on both shoulders, the strap mesh drawn, top ends on the pack | 5 mm |
| R3 | each loop sewn on its pocket's live cloth and hanging down; each carabiner in its loop's lower end; the mug's handle on the rod with its hole along the rod; its centre of mass plumb under the rod (or leaning out off the pack); the mug never inside the pack; whatever hangs clear of the ground | 5 mm / 2 mm / 5 mm, 0.9 / 3 mm / 0.5 mm / 0.3 m |
| R4 | pocket items out of the main cavity (every vertex inside the rigid cavity box) | 0 |
| R5 | the empty pocket's outer face on the wall | wall + 2 cm |
| R6 | handle on the top; bedroll resting on it | 5 mm / 0–15 mm in |
| R7 | walking and stopping: chest anchors ride the chest bone; pack sway within its cap | 2 mm / 2.5° |
| R8 | a 1 s hitch leaves every spring finite and the pack upright | finite / up.y > 0.95 |
| R12 | the empty pocket's seam on the body; its outer layer no further off the body than the fold | 1 mm / fold + 0.5 mm |
| R13 | the axe and hammer: each head 0–3 mm above the rim and seated; each sleeve hugs its handle and is never inside it; both clear the pack (unslumped wall) and each other; the divider spans the body to the outer cloth | 3 mm / 0.5 mm / 0 / 0.5 mm / 0 / 6 mm |
| R14 | the mug knocks on the tools while Henry moves, and not once in the last half second at rest | > 0 / 0 |
| R15 | an item in hand is not drawn in its pack pocket; drawing another pack pocket puts it back in its own place (pack pockets never trade, coat pockets still do) | hammer hidden, then back; sleeve and side pocket keep their items |
| R10 | the thermos stands on the pocket floor; the pocket cloth hugs its cylinder (radius + lining) and is never inside it | 1 mm / 0.5 mm / 0 |
| R11 | taken out and stowed again: it starts above the rim with the pocket empty; the hem opens ≥ 5 mm past it before it seats; friction drags the hem; cloth under its bottom stays the empty pouch; nothing pokes through on any frame; then the hem closes and R10 holds | 2 mm / 5 mm / 2 mm / 0.5 mm / 0 / 0.5 mm |
| R9 | starts, stops, a sidestep and an eased 90° turn: both carabiners swing fore-aft and sideways, the mug swings on its rod; none reaches its stop; each swings under 3° in the last half second (it may rest against the pack or a tool); the mug is never deeper than the contact margin in the pack or the tools on any frame | ≥ 6° / stop − 1° / 3° / 6 mm |

The inspector adds: item overlaps, main items poking past the canvas give, and pocket cloth
left inside its item (mirroring the shader's wrap).

## Quick Access while the pack is worn (`PlayerHubComponent`, `QuickAccessUI`)

| Part | Value | Rule |
|---|---|---|
| Which pockets | every worn pocket whose `EquipmentSlotDefinition.quick_access` is true; the pack's compartments (`pack_main`, `pack_main_2`) are false, Hub only | outside the pack: side pocket, both sleeves, carabiner, lid |
| Cards | the four body cards (coat L/R, lid, thigh; keys 1-4) plus one per outside-pack pocket (`PACK_ORDER`), built from the coat card; shown only while that pocket exists, so they go when the pack comes off | wheel reaches all |
| Anchors | `BackpackModel.get_quick_anchor(pocket_id)`: markers on the side pocket and the sleeves' rim, the right carabiner itself | follow the pack |
| Spread | the outside-pack cards stand in one column (PACK_ORDER, a card plus two gaps apart) outside the body cards on the pack's side, else the other side, else between HANDS and them | never overlap |
| Cross | they take the diagonals round HANDS: side pocket upper left, front sleeve upper right, back sleeve lower right, carabiner lower left | never overlap |

## Mug knock (`PendulumHang.knocked`, `data/audio/backpack/mug_knock.tres`)

| Part | Value | Rule |
|---|---|---|
| When | contact starts with the swing's rate into the obstacle (taken before the frame's spring step) above 0.6 rad/s, or 2.5 times that while it already rests on it | not every touching frame |
| Sound | a random one of the owner's three recordings (`assets/audio/sfx/items/mug/`) through `SoundSystem` at the mug, -14 dB to 0 dB by strike rate up to 4 rad/s, cooldown 0.09 s | random, no repeat |

## Backpack load banner (`BackpackLoadBanner`)

The world-owned `GameplayUI/BackpackLoadBanner` renders the existing
`BG_frame.gdshader` in a transparent 2D SubViewport on a camera-facing Sprite3D.
Its 3D anchor is the deformed canvas handle (`BackpackModel.get_load_anchor()`),
not a Control node under Henry. The bar displays `InventoryComponent.get_total_weight()`
relative to `max_carry_weight`; this is *carried load* (pack, pockets, Kenny and hands),
not the pack's geometric volume fill. `weight_changed` and equipment slot changes
trigger a 4.2-second reveal; continuous presentation follows the
moving handle with damping. The banner yields to Quick Access, the Hub and
very tight TPS camera compositions. The 2D fill shader receives a separate
fraction parameter so the gradient background's `reveal` remains an entrance effect.
