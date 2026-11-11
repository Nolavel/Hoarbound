# Changelog

## 2026-11-10
- Owner: on every message, read Discussion #296 before answering. Replies go to Issue #297, short, not a handoff.
- Recorded the compass CI misses on `57e3b3e0`: scene load is not a script compile, `ubuntu-latest` no longer has `dotnet-sdk-8.0`, an in-place `load_from_slot` is not Continue, and a push must not also dispatch a capture. The order is scene, import gate, headless test, then video.
- Owner confirmed, after Codex's review the same day: Grok writes issue #1 handoffs itself, at any time, without waiting for Codex to draft them.
- An explicit owner request to implement on `grok` overrides the propose-only default for that task only. The default itself stays.
- Initial creation of hoarbound-workflow skill.
- Captures branch ownership, mandatory reading, architecture guardrails, and agent roles from AGENTS.md.
- Designed to work in both Grok chat (via repo) and local Grok Build CLI.
- Added section on recognizing Claude's work (claudeflow ownership patterns, typical docs and contracts).
- Added practical notes for Godot 4.8-dev6 baseline (current project version, later snapshot context, .NET caveats, engine-native preferences).
