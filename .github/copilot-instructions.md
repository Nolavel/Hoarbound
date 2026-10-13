Hoarbound — GitHub Copilot working contract

You are the GitHub Copilot engineering agent for the "Nolavel/Hoarbound" repository.

Before doing any implementation work, read and obey:

- "AGENTS.md"
- "CLAUDE.md" where relevant
- "docs/technical/ARCHITECTURE.md"
- "PRD.md"
- the issue or task currently being investigated

Repository architecture and author decisions take precedence over convenience.

Branch discipline

"main" is the production/integration branch.

Your only persistent working branch is:

"copilot"

Do not intentionally create task-specific, experiment-specific, fix-specific, shader-specific, research-specific, or temporary agent branches.

Do not push implementation changes directly to "main".

The normal flow is:

"main -> copilot -> research/implementation/testing -> report -> author decision -> integration"

Preferred operating mode:

- work from the persistent draft PR whose head branch is "copilot" and base branch is "main";
- when invoked in that PR, continue working on its existing "copilot" branch;
- keep unrelated experiments isolated but commit them to the same "copilot" branch.

If the current session is not operating on the persistent "copilot" branch, do not begin implementation merely to satisfy the task.

Do not create another branch as a workaround.

Instead, report that the session is not attached to the persistent Copilot branch and ask the repository owner to invoke you from the "copilot -> main" draft PR.

A GitHub platform-created temporary branch does not override this repository rule.

Research and experiment policy

Treat R&D ideas as hypotheses, not accepted production features.

For each idea:

1. inspect the current repository first;
2. find existing code, tools, CI, tests and experiments that already address the problem;
3. define the concrete problem the idea is supposed to solve;
4. determine whether the repository actually has that problem;
5. create the smallest isolated experiment capable of proving or disproving the idea;
6. use existing test/capture infrastructure wherever possible;
7. test failure cases, not only the happy path;
8. classify the result as "KEEP", "REJECT", "DEFER", or "NEEDS MORE EVIDENCE";
9. do not integrate the experiment into the production path without an explicit owner decision.

Experiments must be:

- isolated from production behavior;
- clearly identifiable as experimental;
- easy to remove;
- unable to silently replace an existing production system;
- validated before being proposed for production.

Do not create a second implementation of an existing subsystem merely because it is easier than understanding the current one.

External repositories and plugins

External repositories, plugins, papers and implementations are references and sources of proven techniques.

They are not automatically dependencies.

Prefer this sequence:

"inspect external solution -> understand useful mechanism -> inspect license -> reproduce the smallest useful behavior locally -> test against Hoarbound"

Do not import an entire plugin or framework when Hoarbound only needs one small technique.

Do not copy third-party source code without preserving all applicable license and attribution requirements.

If reproducing an idea locally is cleaner and legally appropriate, prefer the local implementation.

Before adding any dependency, explain:

- what concrete problem it solves;
- why existing Hoarbound code cannot reasonably solve it;
- maintenance cost;
- runtime/build cost;
- license implications;
- how removal would work.

Architecture constraints

Follow "docs/technical/ARCHITECTURE.md".

In particular:

- preserve one authoritative owner per state;
- do not create duplicate managers or parallel gameplay architectures;
- cross-language subsystem seams use contracts under "core/contracts/";
- do not spread new "has_method()" / string-based "call()" protocols through gameplay code;
- GDScript, C# and C++/Jenova implementations remain private behind stable public capability contracts where such a boundary is actually required;
- do not create capabilities for every class;
- simulation state remains authoritative over presentation;
- scene lifetime is not persistent world-state ownership.

Jenova/C++ is not a reason to rewrite working GDScript.

Native code should normally replace a measured hot path behind an existing stable contract.

CI and testing

Before adding CI infrastructure, inspect:

- ".github/workflows/"
- "tools/ci/"
- "tools/runtime/"
- existing tests and capture harnesses

Extend existing infrastructure rather than creating a second pipeline.

Prefer the cheapest useful validation first:

"static/import check -> focused test -> runtime test -> capture/render test"

Do not spend heavy CI runs on a series of tiny speculative commits when one prepared experiment can answer the question.

A green GitHub Action does not prove visual correctness.

Render output must be inspected when the task is visual.

Scope control

Do not expand a task merely because adjacent cleanup is possible.

Do not turn a small useful tool into a general Hoarbound framework.

Do not rewrite stable production systems during an R&D investigation unless the task explicitly requires it.

If an experiment disproves the idea, that is a successful research result. Do not force an implementation merely to produce code.

Required final report

Every research or implementation task must end with a concise engineering report containing:

Task

What was investigated.

Existing state

What already existed in Hoarbound before the experiment.

Hypothesis

What the experiment attempted to prove.

Changes

Exact files and systems changed.

Validation

Exact tests, commands, CI runs, captures or measurements used.

Result

One of:

- "KEEP"
- "REJECT"
- "DEFER"
- "NEEDS MORE EVIDENCE"

Explain why.

Production impact

Whether any production path changed. Normally R&D should say "none".

Risks / unresolved questions

Only concrete remaining risks.

Commits

Exact commit SHA(s).

Recommendation

The smallest next step. Do not merge or modify "main"; the repository owner decides integration.

Never claim a test passed unless it actually ran and its output was inspected.
