---
name: hoarbound-animation
description: "Inspect, author, import, retarget, blend and validate Godot 4.8 animation for Henry and interactive props in Hoarbound. Use for keyframes, skeleton/IK, AnimationTree, AnimationPlayer, GLB/GLTF clips, blend shapes, facial morphs, action layers and procedural poses."
---

# Hoarbound animation — Claude Code skill

This is the **Godot-native** adaptation of the useful animation topics in the Three.js skill. Do not use Three.js APIs in the game. Read the canonical reference **`docs/technical/ANIMATION_PIPELINE.md`** before proposing changes or generating code.

## Operating sequence

1. **Sync and scope.** Follow `AGENTS.md` and `CLAUDE.md`. Work in `claudeflow`; merge current `main` into it first. Read issue #1 for handoffs. Identify the owner's exact request and check whether it is documentation, inspection, a test, or an authorized production change.
2. **Find the actual owner.** Inspect `scripts/actors/player/henry/Controllers/HenryUALAnimation.gd`, `scripts/actors/player/henry/Player.gd`, `scenes/actors/player/HenryUALVisual.tscn`, and the relevant interaction/prop code. For hands/IK read `docs/technical/HAND_GRIP.md`; for stove read `docs/technical/STOVE_RITUAL.md`; for retargeting read `docs/motion_matching/retarget_audit.md`.
3. **Choose the native mechanism.** Use `Animation` tracks + `AnimationPlayer` for isolated objects; existing `AnimationTree` state machine/oneshots/blends for Henry; existing `SkeletonModifier3D` order for final contact/IK; imported `MeshInstance3D` blend shapes only when real shapes exist. Do not add another animation graph, state mirror, or runtime dependency.
4. **Preserve causality.** `Player` / `MovementController` own physical body motion; game interactions own commits and cancellation; animation owns presentation. Retarget with verified source/rest transforms, not blindly copied bone rotations.
5. **Validate at three levels.** Inspect GLB channels/paths, run focused Godot tests, then capture the actual affected runtime scene with existing tools. Compare source and destination from multiple views. A passing CLI test is not visual acceptance.
6. **Report the boundary.** Name edited files, exact playback/IK owner, tests/captures run, what was not tested and any author approval needed. Update `CHANGELOG.md` for implementation work.

## Do not silently cross these boundaries

- Motion Matching is **off and frozen** pending the author's visual gates (`docs/motion_matching/acceptance_gates.md`). This skill is **not** permission to enable or rewrite it.
- No new Blender-to-Godot tooling or web viewer before checking `tools/blender/`, `tools/motion/`, `tools/runtime/` and `tools/ci/`.
- No new branch, CI workflow, rig replacement, arbitrary root motion, or duplicated hand solver.
- For a simple skill/documentation request, do not change runtime code or spend render CI.

## Entry points

- Reference with examples: `docs/technical/ANIMATION_PIPELINE.md`
- Henry tree + clip aliases: `scripts/actors/player/henry/Controllers/HenryUALAnimation.gd`
- Focused regression: `tests/systems/test_henry_animation.gd`
- Held-item pose contract: `docs/technical/HAND_GRIP.md`
- Motion Matching freeze: `docs/motion_matching/acceptance_gates.md`

**Task handoff:** GitHub issue #1. Claude should acknowledge the reference there when it first uses the skill for animation work.
