# Phase 0 Inventory Plan

## Phase Goal

Record the current SwiftAgent and AnyLanguageModel surfaces before any no-bridge merge work. Phase 0 is documentation-only: inventory APIs, targets, providers, tests, fixtures, and duplicate concepts without copying source or choosing main implementations.

## Source Docs Read

- `docs/any-language-model-merge-plan.md`
- `docs/any-language-model-merge-spec.md`
- `docs/any-language-model-merge-decisions.md`
- `docs/merge-test-matrix.md`
- `docs/package-layout-spec.md`
- `docs/agent-recorder-merge-plan.md`
- `plans/README.md`

## Requirements

- Create `plans/phase-0-inventory-plan.md`.
- Create `docs/phase-0-inventory.md`.
- Inventory current SwiftAgent public API, targets, tests, providers, AgentRecorder, and FoundationModels/provider SDK usage.
- Inventory AnyLanguageModel package structure, targets, tests, providers, dependencies, and overlapping core types.
- Inventory all `import FoundationModels` usage.
- Inventory all OpenAI and Anthropic SDK usage.
- Inventory duplicate concepts between the repos that need Phase 2 main-type decisions, without deciding them.
- Identify current tests/fixtures that must be preserved, adapted, or replaced.
- Capture current SwiftAgent streaming behavior from existing tests/replay fixtures.
- Capture AnyLanguageModel provider coverage.
- Keep output concise and actionable with useful file/path references.

## Scope and Non-Goals

- Scope: read manifests, source layout, public declarations, imports, tests, AgentRecorder scenarios, replay fixture patterns, and merge docs.
- Non-goal: copy AnyLanguageModel source into SwiftAgent.
- Non-goal: modify implementation code.
- Non-goal: choose main Phase 2 types.
- Non-goal: update tests, fixtures, package products, dependencies, or provider implementations.

## Files and Areas Expected To Change

- Add `plans/phase-0-inventory-plan.md`.
- Add `docs/phase-0-inventory.md`.
- No implementation files should change.

## Implementation Steps

1. Read the merge docs and plan format guidance.
2. Inspect SwiftAgent `Package.swift`, `Sources`, `Tests`, `AgentRecorder`, and `Examples`.
3. Inspect AnyLanguageModel `Package.swift`, `Sources`, and `Tests`.
4. Count and locate FoundationModels, OpenAI, and SwiftAnthropic usage.
5. Compare overlapping concepts: sessions, provider boundary, transcript, streaming, tools, schema/content, options, prompt/instructions, transport/replay, macros.
6. Classify existing SwiftAgent and AnyLanguageModel tests/fixtures by preserve/adapt/replace.
7. Write findings to `docs/phase-0-inventory.md`.

## Test and Build Commands

No build or test commands are required for Phase 0 because it is documentation-only.

If implementation files are accidentally changed, revert those changes and run the relevant commands from `docs/merge-test-matrix.md` before continuing.

## Approval Gates

- Phase 0 may complete once both docs exist and no implementation files changed.
- Phase 2 main type choices require a separate plan and explicit approval before implementation.

## Rollback or Cleanup Notes

- Rollback is limited to deleting `plans/phase-0-inventory-plan.md` and/or `docs/phase-0-inventory.md`.
- Do not delete or modify source, tests, package metadata, or copied external content in Phase 0.

## Open Questions

- Which duplicate concepts should be proposed as main in Phase 2?
- Which AnyLanguageModel live provider tests should become replay tests first?
- How should AnyLanguageModel transport injection be adapted to preserve `HTTPReplayRecorder`?
