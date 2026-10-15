# Godot AI integration

The project vendors the complete Godot AI 4.2.3 distribution from
`hi-godot/godot-ai`, source commit `f58314d9473d11efef94dd68b523e1b52643d736`.
The original archive SHA-256 and source metadata are recorded in
`godot_ai_vendor_receipt.json`. All 313 installed files match the supplied
release inventory byte for byte; the upstream MIT license is included.

## Conflict decision

The local migration-only entry point and stashed 3.2.1 plugin independently
added `plugin.cfg`, `plugin.gd`, `plugin.gd.uid` and `utils/port_resolver.gd`.
Installing individual sides would leave incompatible plugin/lifecycle code.
The resolution installs the complete 4.2.3 archive and removes superseded
v3-only files and embedded migration release archives. Migration support that
belongs to the full 4.2.3 distribution is retained.

`project.godot` enables the addon and its `_mcp_game_helper` autoload. The
upstream export plugin strips the helper from exported packs. Headless editor
imports keep the MCP server disabled. Reopen the interactive editor after
switching to this revision so it loads the new plugin code.

## Integration boundary

The nightly stove, door and pickup fixes from PR #137 and Key West First Exit
from PR #140 are preserved through a merge of `origin/main` into `codex`.
The Key West profile remains selected through the existing
`HFN_WORLD=key_west_test` launch contract; the default world is unchanged. (That profile and the
legacy island were removed on 2026-10-15; the main scene is `key_west_reality.tscn`.)
The generated UID companions for the ten new Key West scripts are included.

The vendored `handlers/texture_handler.gd` contains an upstream blank line at
EOF. Diff whitespace validation ignores only `blank-at-eof` to preserve the
verified upstream bytes.

## Validation on Godot 4.8 dev6 .NET

- .NET build: zero warnings and errors.
- Second editor import: clean; headless MCP startup is disabled.
- Project GDScript compilation: 217 scripts clean.
- Addon GDScript compilation: all 155 scripts clean.
- Input map overlaps, tracked ASCII paths and UID companions: clean.
- TestScene Vulkan capture: 1920 x 1080 non-black frame, no script errors.
  Existing debug-label and terrain-less TestScene warnings remain.
- Passing suites: Key West First Exit, world profiles, streaming, stove visual,
  stove warmer, stove world time, shelter scene, shelter recovery, interaction,
  pickup ledger (10 total).
- Inherited failing fixtures: `test_stove_act.gd` and `test_shelter_focus.gd`.
  Both fixtures and `heat_source_feed.gd` are identical to `origin/main`.
  The fixtures still assume random lighter misses; the act fixture also drives
  external presentation through the old action-system-only path. The act fixture
  reaches a null lighter after its preceding failures and requires termination.
  The complete test suite is therefore not certified green by this integration.
  Production stove behavior is retained from the author-approved nightly fixes.
