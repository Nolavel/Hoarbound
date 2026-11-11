# Architecture decision records

Decisions a collaborator will reasonably challenge. Each record keeps its context, the alternatives weighed, the cost
of the choice and the evidence that would reopen it. An accepted record is not rewritten: a new record supersedes it
and links back. The rules they serve live in [`../ARCHITECTURE.md`](../ARCHITECTURE.md) (RU:
[`../ARCHITECTURE_RU.md`](../ARCHITECTURE_RU.md)), §16–17.

| # | Decision | Status |
|---|---|---|
| [0001](0001-no-global-ecs.md) | No project-wide ECS; Godot-native composition with local data-oriented islands | Accepted |
| [0002](0002-capabilities-at-bounded-seams.md) | Capability contracts only at real seams; typed calls inside a subsystem | Accepted |
| [0003](0003-measured-engine-and-native-choices.md) | GodotPhysics3D, and native C++ only after profiling | Accepted |

New record: copy the headings of any record below, number it next, add it to this table and to §17.
