# Phase Plans

This folder stores execution plans for each merge phase.

Before implementing a phase, create a dedicated phase plan/spec file here. The phase plan should translate the higher-level docs into concrete local steps for that phase only.

Recommended naming:

```text
plans/phase-0-inventory-plan.md
plans/phase-1-copy-any-language-model-plan.md
plans/phase-2-canonical-types-plan.md
```

Phase output docs that are not execution plans should live in `docs/`. For example, Phase 0 should create:

```text
docs/phase-0-inventory.md
```

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

Keep these files concise and update them as the phase progresses.
