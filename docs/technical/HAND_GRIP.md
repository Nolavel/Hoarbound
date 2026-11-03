# Hand grip

One system for how Henry holds an item in one hand. The item describes its handle; the body works out how to reach it within human joint ranges. No per-item hand fitting.

Code: `scripts/actors/player/henry/components/hand_grip.gd` (`HandGrip`, one per hand, via `HenryUALAnimation.get_hand_grip(left)`).
Stand: `tools/runtime/capture_searchlight_grip.gd` prints the handle in the palm frame, finger-tip offsets, wrist bend and each arm bone's roll in degrees, then shoots sleeve close-ups.

## Why the sleeve twisted (2026-11-03)

The old per-item solver (`StoveHandReach` reused for the searchlight) bent the wrist 106° off the forearm and rolled the hand -93° about the forearm axis. A real wrist bends about 70° and has no roll of its own; the forearm does the turning. Henry's rig has no forearm twist bones, and Godot skins with linear blend, so the wrist seam averaged a half turn and pinched, like a candy wrapper (see the reference below). The sleeve only shows what the bones do.

## Pipeline (skeleton modifiers, in stack order)

| Step | Node | Does |
|---|---|---|
| 1 | `TwoBoneIK3D` (Godot) | upper arm and forearm reach the wrist goal; the elbow bends toward a pole set back and out from the shoulder |
| 2 | `HandGrip` | turns the hand to the goal frame (wrist to knuckles, index to pinky), held inside a 60° cone off the forearm's line; closes each finger's three joints together in small steps until its tip meets the handle |
| 3 | `BoneTwistDisperser3D` (Godot) | spreads the hand's roll over the upper arm, forearm and hand, in place of twist bones |
| 4 | `JacketSprings` | hem and collar swing from the final pose |

`HandGrip.gripped` fires with the handle centre and axis in world space; the holder places the item there. The item follows the hand: it is never placed first with the hand chasing it.

## Item data

- Anchor: the handle's centre in the model (the searchlight's `GripAnchor`).
- Handle axis: the bar's direction in the item (the searchlight's carry bar runs along its beam, prop Z).
- Handle radius: the fingers close onto it (`SEARCHLIGHT_HANDLE_RADIUS` 12 mm).

## Searchlight carry

The bar runs along the beam. Held in front of the chest pointing forward, the bar would lie along the forearm, and a fist can only take it with the wrist bent 90°. So the searchlight is carried as a lantern:

- The arm is a little forward: 72% of its reach down, 45% forward, 5 cm out, so the lamp is ahead of the thigh.
- Index to pinky runs back along the bar, so the palm faces the thigh.
- The forearm turns the beam toward the head's facing (up to 50° off the body's forward); the wrist tilts it (up to 40°, following the camera's pitch through the head).
- The beam follows the head: `HenryUALAnimation.look_with_light` keeps the head look on (with pitch) while a light is held, and `get_head_facing()` gives its final facing.

Measured on the stand: wrist bend 45°, roll hand 12°, forearm -14°, upper arm -5°.

## Lighter (present hold)

RMB raises the lighter before the chest on `HandGrip`:
- The wrist goal sits before the chest on the holding side.
- Index to pinky runs down the lighter's body, so the thumb is up.
- The hand continues the forearm from a relaxed elbow.
- The thumb closes onto the lighter's front, the strike position.
- The lighter stands in the fist's hollow, base 35 mm below its centre, nozzle above the thumb.
- It blends from its hanging socket fit as the grip eases in.

Measured on the stand (`capture_searchlight_grip.gd -- <dir> lighter`):
- With `HandGrip`: wrist bend 8°; roll hand 0°, forearm -18°, upper arm 11°.
- Old fist: wrist bend 28°, forearm -33°, upper arm 26°, and the lighter sank into a flat hand.

## Fit only (swung tools)

`HandGrip.fit()` leaves the arm and the hand to the animation: no reach, no wrist turn, no twist spread.
Only the fingers and the thumb close on the handle. The item then follows the fist. The frying pan uses
it while it swings (`StrikeComponent`): the handle lies along index to pinky with the eye past the little
finger, the cooking face toward the palm, and the fist closes 0.17 m out along the handle.

## Thumb

`HandGrip` closes the thumb as well:
1. It turns across the palm (about the wrist-to-knuckles line).
2. It bends at its two outer joints.
3. It stops when its tip meets the handle.

## Not on HandGrip

- **Axe and hammer:** they hang from the animated hand by their socket fit, with no IK.
- **Door push:** the palm is planted flat on the door (`DoorHandIK`). That is a contact, not a grip.
- **Stove ritual (`HeatSourceFeed`):** still on `StoveHandReach`. It is measured in `capture_stove.gd`, which prints each hand's wrist bend and roll at every named frame.

## References

- Godot 4.6 IK modifiers: https://godotengine.org/article/inverse-kinematics-returns-to-godot-4-6/
- Candy-wrap from linear blend skinning: https://jessyleite.dev/posts/blender-candy-wrap-twist-deformation/
- Grab poses that conform to the object (Meta Interaction SDK): https://developers.meta.com/vr/documentation/unity/unity-isdk-create-handgrab-poses-mac/
