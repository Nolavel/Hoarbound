# Changelog

Short record of notable production changes. Newest first.

The previous long-form development diary is preserved unchanged in [`archive/CHANGELOG_LEGACY.md`](archive/CHANGELOG_LEGACY.md).

## Unreleased

### Changed

- Replaced the rejected Jenova experiment with the production GDExtension/godot-cpp path: portable core, real controller adapter, checksum-verified three-platform CI artifact and local installer.
- Added the Quick Access HUD, its 3D anchor rig and supporting UI shader material.
- Added owner-local cross-language capability contracts under `core/contracts/`; `SaveManager` is the first production consumer, with legacy save providers adapted at the boundary and no extra Port nodes required.
- Added paired English/Russian canonical architecture contracts; full-project ECS is rejected in favor of the Godot/component + domain-core model with selective ECS/DOD only where justified.
- Added canonical player-experience and Key West design doctrine documents and linked them from the PRD / agent workflow.
- Replaced the historical long-form changelog with this concise production log.

## Changelog rule

Record outcomes, not the development session. Prefer one short bullet per meaningful change. Put implementation evidence, experiment history, benchmark dumps and long rationale in the relevant issue, PR or canonical document instead of duplicating them here.
