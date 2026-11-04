# Animation authoring and integration — Hoarbound

Canonical workflow for **Godot animation work** in Hoarbound. It adapts the useful concepts from [CloudAI-X/threejs-skills / threejs-animation](https://github.com/CloudAI-X/threejs-skills/blob/main/skills/threejs-animation/SKILL.md) to this project's existing Godot runtime. This is an original Godot-specific guide, **not** a Three.js runtime dependency or a direct copy of the upstream examples.

Use with the project Claude Code skill `/.claude/skills/hoarbound-animation` (file: `.claude/skills/hoarbound-animation/SKILL.md`). The skill is the procedure; this document is the technical reference.

## 1. Current production contract (read before touching animation)

- Engine baseline: **Godot 4.8 dev6 .NET**. Verify the installed editor's actual API before using a newly introduced method.
- **Body authority:** `Player` and `MovementController` own motion and collision. `CharacterBody3D.move_and_slide()` produces actual movement; animated root displacement must not secretly become gameplay movement.
- **Animation authority:** `scripts/actors/player/henry/Controllers/HenryUALAnimation.gd` builds the runtime `AnimationTree` in code, reads `Player` state, and handles locomotion, crouch, carry, work poses, actions, upper-body actions, head look and playback parameters. It does **not** own its own process loop; `Player.gd` calls its update methods after body motion.
- **Visual scene:** `scenes/actors/player/HenryUALVisual.tscn` loads Henry's model/UAL animations. Do not replace the rig, clone another full animation controller, or add a competing `AnimationTree` because a sample skill uses a separate mixer.
- **Animation resources:** `assets/animation/ual/` contains the UAL animation assets; clip aliases, library mounting and actual tree structure live in `HenryUALAnimation.gd`. Check the file for currently available names, not a list copied into an issue.
- **Contact/IK:** `StoveHandReach`, `DoorHandIK`, `HandGrip`, `FootPoseProbe`, `SnowFootModifier` and related skeleton modifiers already shape parts of the final pose. Read `docs/technical/HAND_GRIP.md` and the owning component before modifying hands or adding more modifiers.
- **Action state:** stove, inventory, held items and interaction controllers own transaction state. Animation is presentation; it does not decide what inventory item was spent.
- **Motion Matching is not a replacement baseline.** `MotionMatchingLocomotion` is disabled by default and frozen pending author visual acceptance. Read `docs/motion_matching/acceptance_gates.md` and `docs/motion_matching/integration_plan.md`. Never enable it, change the database, or route production locomotion through it on the strength of this skill.
- Follow `AGENTS.md`, `CLAUDE.md`, `docs/technical/ARCHITECTURE.md`, and the existing production tests/capture scripts. The current GitHub code is authoritative for implementation details.

## 2. Translate animation concepts, not Three.js classes

| Upstream concept | Godot production mechanism | Project use |
| --- | --- | --- |
| Clip + keyframe tracks | `Animation` tracks in an `AnimationLibrary` | Authored poses, timing and non-character objects |
| Per-object mixer | `AnimationPlayer` / `AnimationMixer` evaluation | Imported GLB clips; `AnimationTree` drives the character |
| Action playback and crossfade | `AnimationTree` state machine, `AnimationNodeOneShot`, `AnimationNodeBlend2`, BlendSpace, transition `xfade_time` | Existing Henry graph, not a second mixer |
| Skinned mesh and bones | `Skeleton3D`, bone tracks, `SkeletonModifier3D` | Rigged Henry, contact IK, look direction |
| Morph target weights | `MeshInstance3D` blend shapes and blend-shape animation tracks | Face/expressions only when actual imported shapes exist |
| Animation from glTF | Godot GLB/GLTF scene import, `AnimationPlayer` / libraries | `Tripo → Blender headless → GLB → Godot` |
| Procedural motion above a clip | Bone modifiers / project-owned bounded procedural offsets after animation evaluation | Head, hand placement and contact, not body teleportation |
| Animation weights | Existing blend parameters and state transitions | Crouch, carry, hold pose, action layers |

Never paste `THREE.AnimationMixer`, `AnimationAction`, `SkeletonUtils`, `requestAnimationFrame`, or `morphTargetInfluences` into GDScript. Similar terminology does not imply identical update order, import semantics or runtime ownership.

## 3. Author keyframes and import clips

For **non-character props** an `AnimationPlayer` is often enough. This example adds a position track to a `Node3D` called `Prop`, relative to the player's animation root. Use in an isolated test scene; it is **not** a template for replacing Henry's animation graph.

```gdscript
func add_prop_motion(player: AnimationPlayer) -> void:
    var clip: Animation = Animation.new()
    clip.length = 0.6
    clip.loop_mode = Animation.LOOP_NONE
    var track: int = clip.add_track(Animation.TYPE_POSITION_3D)
    clip.track_set_path(track, NodePath("Prop"))
    clip.position_track_insert_key(track, 0.0, Vector3.ZERO)
    clip.position_track_insert_key(track, 0.6, Vector3(0.0, 0.1, 0.0))
    var library: AnimationLibrary = AnimationLibrary.new()
    library.add_animation(&"lift", clip)
    player.add_animation_library(&"prop", library)
    player.play(&"prop/lift")
```

Set `AnimationPlayer.root_node` so `Prop` resolves correctly in the actual hierarchy. For a clip that animates rotation, use `TYPE_ROTATION_3D` with unit quaternions, not arbitrary Euler components. For scale, use `TYPE_SCALE_3D`; for other properties use a typed `TYPE_VALUE` track and valid target NodePath/property. Confirm exact paths after import, especially if Blender renames mesh or armature nodes.

When producing an animation asset through Blender/headless scripts:

1. Record units (metres), orientation, source skeleton, rest pose and expected bone names before export. Do not apply a blind 90-degree fix to the rig.
2. Export actual clips/actions, armature, skin weights and any intended blend shapes in GLB. Treat source motion and source rest pose as two separate inputs to retargeting.
3. Import into Godot and inspect the resulting scene, `Skeleton3D`, `AnimationPlayer`, `AnimationLibrary` names, paths, clip durations and looping.
4. Check one clip *without* procedural layers before combining it with Henry's production graph. Verify shoulder/elbow/knee planes, clavicle roll, foot/toe alignment and body facing from multiple angles.
5. Reuse existing library-mounting and action alias mechanisms in `HenryUALAnimation.gd`. Never duplicate its data path with a second persistent controller.

For external mocap/retargeting, use `docs/motion_matching/retarget_audit.md` and `tools/motion/` for the source family/rest-pose audit; acceptance for new motion remains **visual**, not just a successful import or FK metric.

## 4. Skeletal animation and update order

A skeleton's **rest** is not its **current pose**. Retargeting must map source and destination reference transforms correctly; copying local joint quaternions between unrelated rigs is not generally valid. Do not rename, reparent or rebuild Henry's skeleton merely to accommodate a source pack.

Production sequence to preserve:

```text
input + game state → MovementController → move_and_slide()
                  → HenryUALAnimation state and blend parameters
                  → animation evaluation (AnimationTree / imported clips)
                  → existing Skeleton3D modifiers in known order
                  → final skinned mesh + attached item presentation
```

In particular:

- Directly writing a bone pose **before** animation evaluation is generally overwritten by the graph. For persistent head/hand/foot adjustment use the existing `SkeletonModifier3D` pipeline and its documented order, not ad hoc per-frame writes in arbitrary nodes.
- A modifier must work from the evaluated pose, respect IK limits and have a stable fade/weight. After contact, ease back to the animated pose; no snap or accumulated offset.
- Do not add a second procedural hand solver when `HandGrip` or `StoveHandReach` already owns that interaction. Compare the desired grip and contact semantics first.
- Transforms are explicit: bone-local, skeleton/model and world space are not interchangeable. The stove and held items have their own local frames.
- Play authored motion in place unless the owner explicitly redesigns movement ownership. Root displacement in a clip is not an instruction to teleport `CharacterBody3D`.

## 5. State-machine blending and one-shots

Use `HenryUALAnimation.gd` as the source of exact state names, valid action aliases and parameter paths. Representative existing operations:

```gdscript
animation_tree.set("parameters/base/Grounded/loco/blend_position", speed_ratio)
animation_tree.set("parameters/hold_pose/blend_amount", hold_weight)
animation_tree.set("parameters/actions/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
```

These lines show **parameter shapes**, not standalone runnable code. In the owning component, `speed_ratio` and `hold_weight` must come from its computed state, and the one-shot must first be configured with an available action.

- For base locomotion and pose changes, prefer the existing state machine and its transition rules. Do not reset the state every frame.
- Use the existing full-body and upper-body action pathways; choose a layer only after checking which bones must continue to follow locomotion or a carried item.
- Crossfade a transition **between** compatible poses and verify foot contact and silhouette. An arbitrary fade can interpolate through the body, slide feet or mask a missing retarget.
- A loop, a one-shot and a held pose are different contracts. Make their exit/cancel semantics explicit; do not leave `OneShot` active with a stale request.
- Avoid stacking procedural smoothing in several layers. If an action already owns ease-in/out, another smooth interpolation can add lag or distort the gesture.

For stove work, the real action flow is in `docs/technical/STOVE_RITUAL.md`. An item transfer commits at an explicit authored timeline point from the **interaction owner**, not from an unstable IK distance threshold or a rendered frame. Visual hand reaching follows the authoritative action.

## 6. Morph targets / blend shapes

A Three.js morph influence becomes a **Godot blend shape** on the imported mesh. It only works if the actual GLB contains compatible shape keys. There is no guaranteed face rig or expression library in Hoarbound today.

Example of a **local preview**, not new production face-state ownership:

```gdscript
func preview_shape(face: MeshInstance3D, shape_name: StringName, weight: float) -> bool:
    if face.mesh == null:
        return false
    for index: int in range(face.mesh.get_blend_shape_count()):
        if face.mesh.get_blend_shape_name(index) == shape_name:
            face.set_blend_shape_value(index, clampf(weight, 0.0, 1.0))
            return true
    return false
```

Use a blend-shape animation track for authored expressions and existing `AnimationPlayer` / `AnimationTree` for their timing. Confirm import retained blend shapes and that weights animate on the **correct mesh instance**, not a shared source mesh assumption. Decide whether facial expression comes from the clip, game state or an overlay before blending; do not let two systems write the same shape in different callbacks.

## 7. GLB QA and non-runtime previews

A browser/Three.js preview can help check geometry and clip contents but is **optional**. It cannot prove Godot skinning, shader appearance, bone-modifier order or TPS framing. Do not add Three.js as a game dependency and do not build a second preview or CI harness without a specific approved need.

For each changed GLB or animation, check:

- Geometry: triangles, scale, forward/up axis, normals, materials, UV, bounds.
- Rig: one intended skeleton, consistent bone IDs/names, bind/rest pose, skinning and weights.
- Animation: clip names, durations, loops, valid tracks and targets, no lost channels, no pose jump at boundaries.
- Facial shapes (if any): shape names/count, weight behavior, mesh compatibility.
- Runtime: Godot import log; skinning and contact pose in the **real Henry visual**, not just a GLB viewer.
- Provenance: licenses for donor animations, 3D models and authored assets. A generated model alone is not proof of usable rights.

Use `tools/blender/`, `tools/motion/` and existing project tools first. Keep headless Blender checks separate from the actual Godot runtime acceptance.

## 8. Common failures and corresponding checks

| Symptom | First check |
| --- | --- |
| Clip plays but no node moves | `AnimationPlayer.root_node`, track NodePaths, library/clip names |
| Imported character rotates or lies down | source/destination axes, bind pose, reference pose; not a guessed rotation |
| Run/stand snaps or slides | clip locomotion intent, transition exit conditions, movement ownership, foot contacts |
| IK hand misses an item | skeleton/world frame mismatch, target and solver order, hand/grip ownership |
| Wrist twists a jacket sleeve | joint limits and forearm roll distribution; see `HAND_GRIP.md` |
| Morph expression does nothing | missing GLB shape keys, mesh instance, shape name or wrong track target |
| Procedural pose is ignored | wrong evaluation order; clip or a later modifier overwrote the pose |
| One-shot endlessly repeats | active/request state and restart conditions |
| Model looks right in web preview, wrong in Godot | importer, modifier stack, materials, renderer, actual scene/camera |
| New retarget motion looks anatomically wrong | isolate clip, compare source vs Henry, inspect shoulder/knee planes; do **not** hide it with smoothing |

## 9. Validation and change boundary

1. Before changing anything, inspect `Player.gd`, `HenryUALAnimation.gd`, the target interaction and the affected scenes. Identify **one owner** for action state, pose blending and prop ownership.
2. For a code edit, run the focused test first: `godot --headless --path . --script tests/systems/test_henry_animation.gd` (use the project's configured Godot binary). Also run the relevant interaction test, e.g. `tests/systems/test_stove_ritual.gd`, when the gesture changes.
3. Reuse `tools/runtime/capture_henry_locomotion.gd`, `tools/runtime/capture_stove.gd`, `tools/runtime/capture_searchlight_grip.gd`, and the existing capture harness if the change warrants a render. The exact command should be taken from those scripts and `tools/ci/`, not invented here.
4. Compare **before/after** and view the output from front, side, rear and relevant close-ups. Green headless CI or one static PNG does not establish visually correct animation.
5. Record what changed, test/capture evidence, remaining risks and any required **author** approval. Update the relevant source of truth and `CHANGELOG.md`. Keep agent experiments isolated and out of production unless explicitly approved.

### Scope of this document

This guide defines **how** to inspect, author, blend and validate animation; it does not approve a new facial rig, a Three.js viewer, a KIMODO service, Motion Matching unfreeze, or a replacement player animation architecture. Those require a separate owner decision/task.
