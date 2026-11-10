# ADR 0002: Capability contracts only at real seams

- **Status:** Accepted, recorded 2026-11-06. Mechanism in production since `SaveParticipantCapability`.
- **Owner:** Claude (Technical Director); the author approves changes to the principle.

## Context

Godot invites duck typing: `if node.has_method("x"): node.call("x")`. Spread through gameplay code, it hides
dependencies (no type says what an object must do), defers errors to the moment an interaction runs (a renamed method
is not caught by the parser), lets mandatory actions skip silently, and ties consumers to implementation method names.
Hoarbound also allows a hot path to move from GDScript to C# or C++/GDExtension (ADR 0003), and consumers must not
change when that happens. In the code there are 72 `has_method()` calls in 25 files outside `core/contracts/` (count on
`main` 0a2ca1f3). They are of different kinds (ARCHITECTURE §16, classes A–E).

## Decision

- Inside a subsystem, use typed direct calls through typed references. For facts, use typed signals. For requests that
  may be refused, use commands with a result.
- Where unrelated classes or another implementation language must satisfy one stable seam, use a capability adapter
  under `core/contracts/` (`CapabilityContract` stores the operation map on the owner; a consumer calls the
  capability-specific adapter). Reflection and string dispatch live there and in language adapters only.
- Existing dynamic calls are classified (ARCHITECTURE §16). Optional lifecycle hooks, tools and boundary mechanics stay.
  Discovery by method name and mandatory gameplay operations are debt, migrated when their system is next touched.
  `HandsTransaction` goes first because a partial commit can corrupt state.
- The principle is explicit ownership. `CapabilityContract` is one replaceable mechanism for it.

## Alternatives weighed

- **Duck typing everywhere.** Simple to write; costs are as above. Fine for optional hooks, wrong for mandatory
  operations between owners.
- **A common base class per role.** Typed and fast in GDScript, but it cannot span C# and C++ implementations, and it
  forces inheritance where composition is the rule.
- **One `Port` child node per interface.** Explicit, but it multiplies nodes and wiring for every component, most of
  which never need a seam.
- **A global service locator or event bus.** It hides who depends on whom, which is the problem being solved.

## Cost

- Adapter code at each real seam, and a descriptor to publish.
- `CapabilityContract` checks that methods exist, not their signatures, return types or behaviour. The guarantee comes
  from contract tests: success, refusal, state after a refusal (ARCHITECTURE §16, rule 4). Those tests run in the
  `checks` gate (`tools/ci/required_suites.txt`), not only in the report-only `suites` run.
- Discipline: a capability is not created for every class (ARCHITECTURE §13).

## Revisit when

- A simpler mechanism gives the same guarantees: consumers unchanged across implementation languages, mandatory
  dependencies failing at wiring, and the same contract tests passing.
- Or Godot gains typed interfaces usable from GDScript, C# and GDExtension alike.
