# Phase 1 Copy AnyLanguageModel Plan

## Phase Goal

Mechanically copy the full `/Users/dominicnieto/Desktop/AnyLanguageModel` repository into SwiftAgent as first-class repo content while preserving its layout and dependency graph. This phase is copy-only and must not perform semantic convergence, provider integration, dependency migration into SwiftAgent, or canonical type selection.

## Source Docs Read

- `docs/any-language-model-merge-plan.md`
- `docs/package-layout-spec.md`
- `docs/phase-0-inventory.md`
- `plans/README.md`
- `docs/dependency-migration-plan.md`

## Scope

- Create `External/AnyLanguageModel/`.
- Create `docs/phase-1-copy-results.md`.
- Copy the AnyLanguageModel repo mechanically into that directory.
- Preserve ALM's package layout: `Package.swift`, `Package.resolved`, `Sources/`, `Tests/`, README/docs, scripts, fixtures, CI metadata, and appropriate dotfiles.
- Exclude source-control internals and build artifacts.
- Build the copied ALM package in place.
- Record the exact copy/build commands, results, and any failures in `docs/phase-1-copy-results.md`.

## Non-Goals

- Do not edit copied source files by hand during the initial move.
- Do not prune, relocate, rename, or merge ALM files or modules.
- Do not replace `FoundationModels` imports.
- Do not integrate ALM providers into SwiftAgent targets.
- Do not add ALM dependencies to SwiftAgent's root `Package.swift`.
- Do not remove dependencies from SwiftAgent or the copied ALM package.
- Do not start Phase 2 or choose canonical implementations.

## Files And Areas Expected To Change

- Add `plans/phase-1-copy-any-language-model-plan.md`.
- Add `docs/phase-1-copy-results.md`.
- Add `External/AnyLanguageModel/` containing the mechanically copied ALM repo.
- No changes expected to SwiftAgent `Package.swift`, `Sources/`, `Tests/`, `AgentRecorder/`, or examples during Phase 1.

## Implementation Steps

1. Confirm approval to proceed after this plan is reviewed.
2. Create the destination directory:

   ```bash
   mkdir -p External
   ```

3. Copy ALM mechanically:

   ```bash
   rsync -a --exclude .git --exclude .build --exclude .DS_Store /Users/dominicnieto/Desktop/AnyLanguageModel/ External/AnyLanguageModel/
   ```

4. Verify the copied top-level layout exists without rewriting copied files:

   ```bash
   find External/AnyLanguageModel -maxdepth 2 -print | sort | sed -n '1,160p'
   ```

5. Confirm excluded artifacts were not copied:

   ```bash
   find External/AnyLanguageModel \( -name .git -o -name .build -o -name .DS_Store \) -print
   ```

6. Build the copied package in place:

   ```bash
   swift build --package-path External/AnyLanguageModel
   ```

7. Create/update `docs/phase-1-copy-results.md` with the exact commands run, command results, failures, skipped validation, changed files/directories, dependency decisions made or deferred, and follow-ups.
8. If the copied package build fails because of environment, dependency resolution, platform availability, or toolchain issues, record the exact command and failure in `docs/phase-1-copy-results.md`. Do not refactor copied code to fix it in this phase.

## Test And Build Commands

Required Phase 1 validation:

```bash
swift build --package-path External/AnyLanguageModel
```

SwiftAgent root builds/tests are not required for the mechanical copy unless the copy unexpectedly changes root package behavior. If SwiftAgent root files are edited unexpectedly, stop and reassess before continuing.

## Dependency Approval Gates

- Phase 1 makes no dependency changes to SwiftAgent's root `Package.swift`.
- Phase 1 keeps ALM's dependency graph inside `External/AnyLanguageModel/Package.swift`.
- Phase 1 does not remove dependencies from either package.
- If the copied ALM build reveals dependency issues, document them only.
- Any later dependency removal must happen in a separate approved phase and must summarize the dependency, current users, replacement path, affected targets/products, and test/build evidence.

## Rollback Or Cleanup Notes

- If the copy is incorrect before any semantic edits occur, remove only `External/AnyLanguageModel/` and rerun the mechanical copy command.
- Do not clean up, normalize, or modify copied files during Phase 1 unless the user explicitly approves a narrow correction to the copy process itself.
- If build artifacts appear under `External/AnyLanguageModel/.build` after validation, remove that generated build directory before Phase 1 completion so `External/AnyLanguageModel/` remains the copied repo content rather than copied or generated build output.

## Approval Gates

- This plan file must exist before implementation.
- `docs/phase-1-copy-results.md` must be created before Phase 1 is considered complete.
- Pause after creating this plan and wait for user approval before running the copy commands.
- Pause again before any non-mechanical change, including dependency edits, file relocation, module renaming, or SwiftAgent integration.

## Decisions From Plan Review

- Keep ALM's `Package.resolved` in the mechanical Phase 1 copy. It is useful evidence of the source repo's last resolved dependency graph. Reconsider whether SwiftAgent should keep, delete, or regenerate it only in a later dependency reconciliation phase.
- Record only the default copied package build result. If the default build fails, record the exact command, exact failure, likely category, whether it blocks the mechanical copy, and any clear trait or optional-provider clue from the failure. Do not investigate or run a full trait-specific build matrix in Phase 1.
