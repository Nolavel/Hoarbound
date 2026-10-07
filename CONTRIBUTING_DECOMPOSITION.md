# Work decomposition in Hoarbound

Use one hierarchy across planning and implementation:

**PRD -> Epic / Milestone -> User Story -> Task / PR -> checklist subtask**

| Level | Where it lives | Purpose |
|---|---|---|
| PRD | `PRD.md` | Product direction, current milestone and scope boundaries |
| Epic | GitHub Milestone, optionally an epic issue | A product-level outcome spanning multiple stories |
| User Story | Issue created from `user_story.md` | One player-facing value or outcome |
| Task | Child issue / PR created from `task.md` | One bounded implementation unit |
| Subtask | Checklist item inside a Task | Small verifiable step; not a separate issue by default |

## Rules

1. **An Epic needs a Definition of Done before work starts.** If the team cannot state what must be true when the milestone closes, the scope is not ready.

2. **One Story = one player value.** If a story says “I want X and Y” and those outcomes can be accepted independently, split them.

3. **Every implementation Task needs an explicit Out of scope / Do not section.** This is the primary guard against scope creep.

4. **A checklist item is not automatically an issue.** Keep small implementation steps inside the Task. Promote one only when it becomes independently owned, reviewable or blocked.

5. **Epic, Story and Task scopes must state what is excluded.** Explicit exclusions should not need to be renegotiated during every review.

6. **State priority relative to the current production slice.** For player-facing Stories, make clear whether the work is P0 / blocking First Exit A, P1 quality, or later scope.

7. **Keep coordination separate from the task contract.** Short cross-agent handoffs belong in issue #1 or the owning issue's comments. Do not turn task bodies into session logs.

8. **Prefer current state over implementation history.** Issue bodies should describe the active contract: current state, remaining work, constraints and acceptance. Historical reasoning belongs in comments, linked evidence or archived docs when it still matters.

## When to split work

Create a higher-level or sibling issue when:

- an issue grows into several independently acceptable outcomes;
- a Task cannot reasonably fit into one coherent PR without “and while we are here” work;
- a new player fantasy or system boundary appears rather than a variation of the current one;
- evidence or research becomes large enough that it obscures the implementation contract.

Do **not** split work just to create more tickets. The purpose of decomposition is ownership and clarity, not issue count.

## Writing standard for issues

A collaborator should be able to answer these questions quickly:

1. What problem or player outcome does this issue own?
2. What is already true in the current project?
3. What exactly remains to change or prove?
4. What must not change in this pass?
5. What observable evidence closes the issue?

Use technical detail where it changes implementation or acceptance. Remove repeated explanations, AI-session narration and speculative alternatives that are no longer live decisions.

## Related documents

- [`PRD.md`](PRD.md) — product contract
- [`docs/game_design/VERTICAL_SLICE.md`](docs/game_design/VERTICAL_SLICE.md) — current First Exit A scope
- [`docs/GDD.md`](docs/GDD.md) — code-grounded design / runtime snapshot
- [`AGENTS.md`](AGENTS.md) — branch and repository workflow
- [`.github/ISSUE_TEMPLATE/`](.github/ISSUE_TEMPLATE/) — issue templates