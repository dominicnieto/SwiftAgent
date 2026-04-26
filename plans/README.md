# Phase Plans

This folder stores execution plans for each merge phase.

Before implementing a phase, create a dedicated phase plan/spec file here. The phase plan should translate the higher-level docs into concrete local steps for that phase only.

Recommended naming:

```text
plans/phase-0-inventory-plan.md
plans/phase-1-copy-any-language-model-plan.md
plans/phase-2-canonical-types-plan.md
plans/phase-3-additional-providers-plan.md
plans/phase-4-cleanup-api-polish-plan.md
```

Each phase should also create a results doc in `docs/` that records what actually happened. Recommended naming:

```text
docs/phase-0-results.md
docs/phase-1-copy-results.md
docs/phase-2-core-model-stack-merge-results.md
```

The original split between Phase 2 main types, Phase 3 transcript/streaming, Phase 4 OpenAI,
and Phase 5 Anthropic is superseded. Those areas are one model-stack architecture and should be
planned together in `phase-2-canonical-types-plan.md`.

Phase 3 starts from `phase-3-additional-providers-plan.md`, which is intentionally a skeleton
for the planning agent to expand provider-by-provider.

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

## Feature Boundary Rule

Plan and implement whole durable features, not artificial type slices.

If an AnyLanguageModel type depends on another architectural type, move or design the connected
pieces together. Do not create interim protocols, placeholder types, bridge sessions, adapter
shims, or compatibility-only typealiases just to satisfy a phase boundary. Compatibility wrappers
are acceptable only when they are thin conveniences over the main implementation and have a
documented permanence or removal decision.
