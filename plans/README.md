# Phase Plans

This folder stores execution plans for each merge phase.

Before implementing a phase, create a dedicated phase plan/spec file here. The phase plan should translate the higher-level docs into concrete local steps for that phase only.

Recommended naming:

```text
plans/phase-0-inventory-plan.md
plans/phase-1-copy-any-language-model-plan.md
plans/phase-2-canonical-types-plan.md
```

Each phase should also create a results doc in `docs/` that records what actually happened. Recommended naming:

```text
docs/phase-0-results.md
docs/phase-1-copy-results.md
docs/phase-2-canonical-types-results.md
```

Phase output docs that are not execution plans should live in `docs/`. Phase-specific specs, inventories, and results docs may be separate files when that keeps the record clearer.

Each phase plan should include:

- phase goal
- source docs read
- scope and non-goals
- files/areas expected to change
- implementation steps
- test/build commands
- approval gates
- rollback or cleanup notes
- open questions

Each phase plan must include dependency approval gates. If the phase may remove a dependency from either SwiftAgent's package or the copied AnyLanguageModel package, the plan must require explicit approval before removal and must summarize the dependency, current users, replacement path, affected targets/products, and test/build evidence.

Each phase results doc should include:

- commands run
- build/test results
- failures and skipped validation
- files/directories changed
- dependency decisions made or deferred
- follow-ups for later phases

Keep these files concise and update them as the phase progresses.
