---
name: hoarbound-workflow
description: "Hoarbound project workflow skill. Understands architecture, agent rules (Grok/Claude/Codex), structure, components, connections, recognizes Claude's work, maintains audits and updates. Use when working on Hoarbound repo, reviewing code, planning features, or doing commercial/scope audits."
type: workflow
lifecycle: active
---

# Hoarbound Workflow — Architecture, Rules & Audits

Use this skill whenever working with the Hoarbound repository (Godot 4.8 .NET, frozen Key West survival).

## Core Rules (always apply)

1. **Branch ownership**: Grok owns only `grok`. Never commit to `main` or other agents' branches (`claudeflow`, `codex`).
2. **Pre-task sync**: Before any substantial work, sync `main` into `grok` (merge, never rebase). Verify current `main` is ancestor.
3. **Propose only**: Grok proposes; does not auto-implement gameplay systems. Implementation belongs to Codex.
4. **Mandatory reading** before relevant work:
   - Gameplay/survival/UI/pacing → `docs/game_design/EXPERIENCE_PILLARS.md`
   - World/Key West/terrain → `docs/world/KEY_WEST_DESIGN_DOCTRINE.md` + Experience Pillars
   - Architecture/refactors/ECS → `docs/technical/ARCHITECTURE.md`
   - Visuals → `docs/art/ART_DIRECTION.md`
   - Future intent → `docs/FUTURE_INTENT.md` (direction, not authorization)

## Architecture Quick Reference

- Engine: Godot 4.8-dev6 .NET (mono), Godot.NET.Sdk 4.8.0-dev.6, net8.0
- Main scene: `res://scenes/world/key_west/key_west_reality.tscn`
- Terrain: `IslandTerrain` from heightmap (edit in Blender)
- Full ECS rejected; selective ECS/DOD only with justification
- Cross-system seams via capability contracts in `core/contracts/`
- Simulation state is authoritative; presentation derives from it

## Agent Roles

| Agent | Branch | Focus |
|-------|--------|-------|
| Author | any | Design, narrative, final say |
| Claude | `claudeflow` | Technical direction, architecture, CI, headless render |
| Codex | `codex` | Implementation, gameplay, rendering, tooling |
| Grok | `grok` | Commercial readiness, scope control, audits, risk |

## Workflow for Grok

1. Sync `main` → `grok` if needed.
2. Read relevant product docs.
3. Inspect current structure (scenes, scripts, docs).
4. Recognize recent work by other agents (especially Claude on architecture).
5. Propose changes via comments, issues, or docs — do not implement gameplay.
6. Keep this skill and audits updated in `docs/grok/`.
7. Record outcomes in CHANGELOG or dedicated audit notes.

## Maintaining This Skill

- Update `SKILL.md` and `references/` when architecture or rules change.
- Add entries to `CHANGELOG.md` for significant updates.
- After real sessions, enrich via postmortem if available.
- Prefer short, table-driven content over long prose.

## References

- See `references/architecture-notes.md` for deeper notes (create as needed).
- Canonical sources: `AGENTS.md`, `docs/technical/ARCHITECTURE.md`, product docs listed above.
