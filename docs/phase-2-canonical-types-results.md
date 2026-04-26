# Phase 2 Core Model Stack Results

## Summary

Implemented the earlier Phase 2 main core work for local FoundationModels-style primitives.

Planning update: the original split between Phase 2 main types, Phase 3 transcript/streaming,
Phase 4 OpenAI, and Phase 5 Anthropic has been superseded. New implementation should use the
updated `plans/phase-2-canonical-types-plan.md` and treat those areas as one coherent model-stack
merge. Do not use this results file as justification for adding interim protocols, placeholder
types, bridge sessions, or compatibility-only typealiases to preserve old phase boundaries.

Phase 2 status: partial. Phase 2 is not complete. This result covers the earlier main core work:
local core primitives, macro references, and the current provider/test/example call sites needed
to consume those primitives. Later slices also resolved `@Generable` defaulted-property parity,
migrated focused ALM core tests for main SwiftAgent primitives, and completed the Phase 2
prompt ownership slice. Transcript/session/provider replacement, unified generation options,
provider capabilities, and direct provider migration remain open workstreams in the merged Phase 2
plan.

SwiftAgent now owns ALM-derived local definitions for:

- `Availability`
- `GeneratedContent`
- `Generable`
- `GenerationSchema`
- `DynamicGenerationSchema`
- `GenerationGuide`
- `GenerationID`
- `ConvertibleFromGeneratedContent`
- `ConvertibleToGeneratedContent`
- `Instructions`
- `Tool`
- `SendableMetatype`

The slice also folded ALM's `@Generable` and `@Guide` macro implementations into `SwiftAgentMacros`, updated `@SessionSchema` tool wrapper output to use local `SwiftAgent.Tool`, and removed Apple `FoundationModels` imports from SwiftAgent, provider, test, example, and AgentRecorder source touched by the core type stack.

No provider SDK replacement, direct-provider migration, dependency removal, or `External/AnyLanguageModel` pruning was done.

Review cleanup removed stray generated artifacts `External/.DS_Store` and `./.DS_Store`. The
`.swiftpm/xcode/xcshareddata/xcschemes/SwiftAgentMacroTests.xcscheme` diff was inspected and
reverted as incidental Xcode metadata because the existing `TestAction` already referenced the
macro test plan and the Phase 2 slice does not require scheme metadata changes.

## Initial ALM Core Test Migration Slice

Completed the next Phase 2 implementation step from `docs/phase-2-completion-checklist.md`:
initial migration of relevant ALM core tests into SwiftAgent.

Implementation:

- Mechanically copied these ALM core tests into `Tests/SwiftAgentTests/Core/`:
  - `ConvertibleToGeneratedContentTests.swift`
  - `DynamicGenerationSchemaTests.swift`
  - `GenerationGuideTests.swift`
- Adapted imports from `AnyLanguageModel` to `SwiftAgent`.
- Removed the copied test-only `JSONSchema` import because the root `SwiftAgentTests` target does
  not depend on `JSONSchema` and this assertion only needed semantic JSON comparison. This does
  not change the dependency decision for production ALM JSON/schema code.
- Used `Prompt.formatted()` for SwiftAgent prompt rendering in the generated-content representation
  assertion.
- Replaced copied decimal force unwraps with `#require`.

Files changed:

- `Tests/SwiftAgentTests/Core/ConvertibleToGeneratedContentTests.swift`
- `Tests/SwiftAgentTests/Core/DynamicGenerationSchemaTests.swift`
- `Tests/SwiftAgentTests/Core/GenerationGuideTests.swift`
- `docs/phase-2-completion-checklist.md`
- `docs/phase-2-canonical-types-results.md`

Dependency decisions:

- No dependency additions.
- No dependency removals.
- `Package.swift` was not edited.
- `JSONSchema` remains deferred until `GenerationOptions`, `JSONValue`, direct provider request
  builders, or provider-neutral schema conversion move into SwiftAgent.
- `PartialJSONDecoder` remains deferred until structured streaming / partial snapshot work needs it.

Validation succeeded:

```bash
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -only-testing:SwiftAgentTests/ConvertibleToGeneratedContentTests -only-testing:SwiftAgentTests/DynamicGenerationSchemaTests -only-testing:SwiftAgentTests/GenerationGuideTests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme ExampleApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build -quiet
```

The same validation set was rerun during final review on April 25, 2026, with the same outcomes.

Attempted and blocked by local environment:

```bash
swiftformat --config ".swiftformat" Tests/SwiftAgentTests/Core/ConvertibleToGeneratedContentTests.swift Tests/SwiftAgentTests/Core/DynamicGenerationSchemaTests.swift Tests/SwiftAgentTests/Core/GenerationGuideTests.swift
which swiftformat || true
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" build -quiet
```

Result:

```text
zsh:1: command not found: swiftformat
swiftformat not found
No signing certificate "Mac Development" found: No "Mac Development" signing certificate matching team ID "7F6BJZY5B3" with a private key was found.
```

Follow-ups:

- Continue ALM core test migration/classification for generated content, broader generation schema
  behavior, prompt, instructions, transcript, generation options, and tool execution.
- Phase 2 remains partial because the checklist still has incomplete primary ownership and
  dependency-decision items.

Final review status:

- No review findings remain open for this implementation step.
- This initial ALM core test migration slice is ready to commit, including the three new
  `Tests/SwiftAgentTests/Core/` files and the Phase 2 tracking doc updates.
- Phase 2 remains partial according to `docs/phase-2-completion-checklist.md`.

## Defaulted-Property Parity Slice

Completed the next Phase 2 implementation step from `docs/phase-2-completion-checklist.md`:
`@Generable` defaulted-property parity.

Implementation:

- `GenerableMacro` now records stored-property initializer expressions while extracting guided
  properties.
- Generated memberwise initializers preserve those defaults, so callers can omit defaulted
  arguments just like Swift's native memberwise initializer.
- Generated `init(_ generatedContent:)` uses explicit stored-property defaults when fields are
  missing, while preserving explicit `null` as `nil` for optional fields.
- Property type syntax is trimmed before macro code generation so optional detection is stable.

Files changed:

- `Sources/SwiftAgentMacros/GenerableMacro.swift`
- `Tests/SwiftAgentTests/Protocols/GenerableMacroDefaultedPropertyTests.swift`
- `docs/phase-2-completion-checklist.md`
- `docs/phase-2-canonical-types-results.md`

Dependency decisions:

- No dependency additions.
- No dependency removals.
- `Package.swift` was not edited.
- `JSONSchema` remains deferred until `GenerationOptions`, `JSONValue`, direct provider request
  builders, or provider-neutral schema conversion move into SwiftAgent.
- `PartialJSONDecoder` remains deferred until structured streaming / partial snapshot work needs it.

Validation succeeded:

The same validation set was rerun during final review on April 25, 2026, with the same outcomes:

```bash
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -only-testing:SwiftAgentTests/GenerableMacroDefaultedPropertyTests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentMacroTests -testPlan SwiftAgentMacroTests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme ExampleApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build -quiet
```

Attempted and blocked by local environment:

```bash
swiftformat --config ".swiftformat" Sources/SwiftAgentMacros/GenerableMacro.swift Tests/SwiftAgentTests/Protocols/GenerableMacroDefaultedPropertyTests.swift
which swiftformat || true
```

Result:

```text
zsh:1: command not found: swiftformat
swiftformat not found
```

```bash
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" build -quiet
```

Result:

```text
No signing certificate "Mac Development" found: No "Mac Development" signing certificate matching team ID "7F6BJZY5B3" with a private key was found.
```

Failed during implementation and fixed:

```bash
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -only-testing:SwiftAgentTests/GenerableMacroDefaultedPropertyTests test -quiet
```

Result before the type-trimming fix:

```text
Cannot convert value of type 'GeneratedContent' to expected argument type 'String'
```

Transient validation issue from running two `xcodebuild` commands concurrently:

```text
unable to attach DB: error: accessing build database ".../XCBuildData/build.db": database is locked
```

Follow-ups:

- Broader ALM core tests still need migration/classification before Phase 2 can be complete.
- `LanguageModel`, `Availability`, `GenerationOptions`, `JSONValue`/`JSONSchema`, and
  `PartialJSONDecoder` checklist items remain unresolved or deferred pending later approved work.

## Prompt Main Ownership And Prompt/Instructions Test Slice

Completed the next Phase 2 implementation step from `docs/phase-2-completion-checklist.md`:
primary `Prompt` ownership plus another focused ALM core test migration slice.

Implementation:

- Kept SwiftAgent's existing `Prompt`/`PromptBuilder` as the main prompt implementation
  because it already preserves richer section/tag rendering used by SwiftAgent prompt/source tests.
- Added ALM-compatible `CustomStringConvertible` behavior so `Prompt.description` returns the
  formatted model input text.
- Added ALM-compatible newline prompt rendering for arrays by overriding `promptRepresentation`
  in SwiftAgent's existing `Array: ConvertibleToGeneratedContent` conformance. This avoids a
  second array protocol conformance while preserving generated-content array behavior.
- Mechanically copied ALM `PromptTests` and `InstructionsTests` into `Tests/SwiftAgentTests/Core/`
  and adapted imports from `AnyLanguageModel` to `SwiftAgent`.

Files changed:

- `Sources/SwiftAgent/Prompting/PromptBuilder.swift`
- `Sources/SwiftAgent/Core/ConvertibleToGeneratedContent.swift`
- `Tests/SwiftAgentTests/Core/PromptTests.swift`
- `Tests/SwiftAgentTests/Core/InstructionsTests.swift`
- `docs/phase-2-completion-checklist.md`
- `docs/phase-2-canonical-types-results.md`

Dependency decisions:

- No dependency additions.
- No dependency removals.
- `Package.swift` was not edited.
- This prompt slice did not need `JSONSchema`, `JSONValue`, or `PartialJSONDecoder`.
- For later `GenerationOptions` / `JSONValue` work, preserve the dependency-backed ALM path and
  use `JSONSchema` when the moved implementation naturally needs it.

Validation succeeded:

```bash
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -only-testing:SwiftAgentTests/PromptTests -only-testing:SwiftAgentTests/InstructionsTests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -only-testing:SwiftAgentTests/PromptBuilderTests -only-testing:SwiftAgentTests/PromptTests -only-testing:SwiftAgentTests/InstructionsTests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme ExampleApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build -quiet
```

Attempted and blocked by local environment:

```bash
which swiftformat || true
swiftformat --config ".swiftformat" Sources/SwiftAgent/Prompting/PromptBuilder.swift Sources/SwiftAgent/Core/ConvertibleToGeneratedContent.swift Tests/SwiftAgentTests/Core/PromptTests.swift Tests/SwiftAgentTests/Core/InstructionsTests.swift
```

Result:

```text
swiftformat not found
zsh:1: command not found: swiftformat
```

Failed during implementation and fixed:

```bash
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -only-testing:SwiftAgentTests/PromptTests -only-testing:SwiftAgentTests/InstructionsTests test -quiet
```

Result before moving array prompt rendering into the existing array conformance:

```text
Conflicting conformance of 'Array<Element>' to protocol 'PromptRepresentable'; there cannot be more than one conformance, even with different conditional bounds
```

Follow-ups:

- Continue with feature-shaped Phase 2 blockers: `Availability`, `LanguageModel`, and
  `GenerationOptions` / `JSONValue`.
- Add `JSONSchema` when editing `Package.swift` for `GenerationOptions` / `JSONValue` if the
  moved implementation naturally needs it, and record the validation evidence.
- Broader ALM core tests for generated content, schemas, transcript, generation options, and tool
  execution still need migration/classification.

Final review on April 25, 2026:

- Rechecked the uncommitted diff scope: only the prompt slice Swift files, prompt/instructions
  tests, and Phase 2 tracking docs are changed.
- Confirmed no uncommitted `Package.swift`, `Package.resolved`, `External/AnyLanguageModel`, or
  `.swiftpm/xcode/xcshareddata/xcschemes/*.xcscheme` changes.
- Confirmed no `.DS_Store` files are present.
- Confirmed MacPaw `OpenAI` and `SwiftAnthropic` dependencies/imports remain in place.
- Confirmed this slice did not start the now-merged transcript/session streaming or direct-provider
  replacement workstreams, dependency removal, or `External/AnyLanguageModel` pruning.

Validation rerun during final review:

```bash
which swiftformat || true
swiftformat --config ".swiftformat" Sources/SwiftAgent/Core/ConvertibleToGeneratedContent.swift Sources/SwiftAgent/Prompting/PromptBuilder.swift Tests/SwiftAgentTests/Core/InstructionsTests.swift Tests/SwiftAgentTests/Core/PromptTests.swift
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -only-testing:SwiftAgentTests/PromptBuilderTests -only-testing:SwiftAgentTests/PromptTests -only-testing:SwiftAgentTests/InstructionsTests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme ExampleApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" build -quiet
```

Results:

```text
swiftformat not found
zsh:1: command not found: swiftformat
Focused PromptBuilder/Prompt/Instructions tests passed.
SwiftAgentTests build passed.
Full SwiftAgentTests test plan passed.
ExampleApp iPhone 17 Pro simulator build passed.
AgentRecorder build passed with CODE_SIGNING_ALLOWED=NO.
Plain AgentRecorder build failed before compilation because no Mac Development signing certificate matching team ID "7F6BJZY5B3" with a private key was found.
```

Review status:

- No review findings remain open for this prompt ownership and prompt/instructions test slice.
- This implementation step is ready to commit.
- Phase 2 remains partial according to `docs/phase-2-completion-checklist.md`.

## Availability Main Ownership Slice

Completed the next feature-shaped Phase 2 implementation step from
`docs/phase-2-completion-checklist.md`: main `Availability` ownership.

Implementation:

- Added SwiftAgent's local `Availability<UnavailableReason>` primitive using the ALM source shape.
- Preserved the ALM semantics: `.available`, `.unavailable(reason)`, and conditional
  `Equatable`, `Hashable`, and `Sendable` conformances.
- Added focused SwiftAgent-native Swift Testing coverage for available/unavailable state,
  equality, hashing, and sendability across a task boundary.
- Marked the `Availability` checklist item done with evidence.

Files changed:

- `Sources/SwiftAgent/Core/Availability.swift`
- `Tests/SwiftAgentTests/Core/AvailabilityTests.swift`
- `docs/phase-2-completion-checklist.md`
- `docs/phase-2-canonical-types-results.md`

Dependency decisions:

- No dependency additions.
- No dependency removals.
- `Package.swift` was not edited.
- This slice did not need `JSONSchema`, `JSONValue`, `PartialJSONDecoder`, provider request
  builders, or structured streaming code.
- `LanguageModel` remains incomplete because the ALM protocol is coupled to the future main
  `LanguageModelSession` and unified `GenerationOptions` boundary.
- `GenerationOptions` / `JSONValue` remains incomplete. Add `JSONSchema` when editing
  `Package.swift` for that slice if moved ALM code naturally needs it, and record the validation
  evidence.

Validation succeeded:

```bash
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -only-testing:SwiftAgentTests/AvailabilityTests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme ExampleApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build -quiet
```

Attempted and blocked by local environment:

```bash
swiftformat --config ".swiftformat" Sources/SwiftAgent/Core/Availability.swift Tests/SwiftAgentTests/Core/AvailabilityTests.swift
which swiftformat || true
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" build -quiet
```

Results:

```text
zsh:1: command not found: swiftformat
swiftformat not found
No signing certificate "Mac Development" found: No "Mac Development" signing certificate matching team ID "7F6BJZY5B3" with a private key was found.
```

Follow-ups:

- Resolve main `LanguageModel` ownership, or explicitly amend/defer that Phase 2 item with
  approval if its implementation requires pulling later `LanguageModelSession` work into Phase 2.
- Resolve the `GenerationOptions` / `JSONValue` workstream, adding `JSONSchema` if the moved
  implementation naturally needs it.
- Continue ALM core test migration/classification for generated content, schemas, transcript,
  generation options, and tool execution.

Review status:

- No provider SDK replacement, dependency removal, `External/AnyLanguageModel` pruning, or
  transcript/session/direct-provider runtime behavior was done.
- Final review on April 25, 2026 rechecked the uncommitted scope: only `Availability` source/tests
  and Phase 2 tracking docs are changed.
- Confirmed no uncommitted `Package.swift`, `Package.resolved`, `External/AnyLanguageModel`, or
  `.swiftpm/xcode/xcshareddata/xcschemes/*.xcscheme` changes.
- Confirmed no `.DS_Store` files are present.
- The Availability primary ownership slice is ready to commit.
- Phase 2 remains partial according to `docs/phase-2-completion-checklist.md`.

## Source Movement

Copied ALM source mechanically before targeted edits:

```bash
mkdir -p Sources/SwiftAgent/Core
cp External/AnyLanguageModel/Sources/AnyLanguageModel/ConvertibleFromGeneratedContent.swift Sources/SwiftAgent/Core/
cp External/AnyLanguageModel/Sources/AnyLanguageModel/ConvertibleToGeneratedContent.swift Sources/SwiftAgent/Core/
cp External/AnyLanguageModel/Sources/AnyLanguageModel/DynamicGenerationSchema.swift Sources/SwiftAgent/Core/
cp External/AnyLanguageModel/Sources/AnyLanguageModel/Generable.swift Sources/SwiftAgent/Core/
cp External/AnyLanguageModel/Sources/AnyLanguageModel/GeneratedContent.swift Sources/SwiftAgent/Core/
cp External/AnyLanguageModel/Sources/AnyLanguageModel/GenerationGuide.swift Sources/SwiftAgent/Core/
cp External/AnyLanguageModel/Sources/AnyLanguageModel/GenerationID.swift Sources/SwiftAgent/Core/
cp External/AnyLanguageModel/Sources/AnyLanguageModel/GenerationSchema.swift Sources/SwiftAgent/Core/
cp External/AnyLanguageModel/Sources/AnyLanguageModel/Instructions.swift Sources/SwiftAgent/Core/
cp External/AnyLanguageModel/Sources/AnyLanguageModel/SendableMetatype.swift Sources/SwiftAgent/Core/
cp External/AnyLanguageModel/Sources/AnyLanguageModel/Tool.swift Sources/SwiftAgent/Core/
cp External/AnyLanguageModel/Sources/AnyLanguageModelMacros/GenerableMacro.swift Sources/SwiftAgentMacros/GenerableMacro.swift
cp External/AnyLanguageModel/Sources/AnyLanguageModelMacros/GuideMacro.swift Sources/SwiftAgentMacros/GuideMacro.swift
```

## Implementation Notes

- `@Generable` and `@Guide` now use `SwiftAgentMacros` instead of `AnyLanguageModelMacros`.
- `SwiftAgentMacroPlugin` now registers `GenerableMacro` and `GuideMacro`.
- `@SessionSchema` emits `SwiftAgent.Tool` constraints instead of `FoundationModels.Tool`.
- `SwiftAgentTool`, `DecodableTool`, `_SwiftAgentToolWrapper`, `ToolRun`, session initializers, tests, examples, and AgentRecorder scenarios use local `SwiftAgent.Tool`.
- SwiftAgent's prompt builder availability annotations were removed because the package already targets iOS/macOS 26 and ALM conversion protocols need unconditional `PromptRepresentable` access.
- Local `GenerationSchema` preserves SwiftAgent provider schema behavior by encoding resolved object roots with stable `title`, `required`, and `x-order` fields.
- Local `GeneratedContent(json:)` keeps partial structured-output parsing useful for streaming while still throwing on unrecoverable object/array JSON used as tool arguments.
- `RejectionReport` construction now passes the synthesized `error` member explicitly because the ALM macro-generated memberwise initializer does not preserve defaulted-parameter omission.
- Language model provider doc examples now import `SwiftAgent` instead of Apple `FoundationModels`.
- No `Package.swift` dependency changes were made.

## Files Changed

Added:

- `Sources/SwiftAgent/Core/ConvertibleFromGeneratedContent.swift`
- `Sources/SwiftAgent/Core/ConvertibleToGeneratedContent.swift`
- `Sources/SwiftAgent/Core/DynamicGenerationSchema.swift`
- `Sources/SwiftAgent/Core/Generable.swift`
- `Sources/SwiftAgent/Core/GeneratedContent.swift`
- `Sources/SwiftAgent/Core/GenerationGuide.swift`
- `Sources/SwiftAgent/Core/GenerationID.swift`
- `Sources/SwiftAgent/Core/GenerationSchema.swift`
- `Sources/SwiftAgent/Core/Instructions.swift`
- `Sources/SwiftAgent/Core/SendableMetatype.swift`
- `Sources/SwiftAgent/Core/Tool.swift`
- `Sources/SwiftAgentMacros/GenerableMacro.swift`
- `Sources/SwiftAgentMacros/GuideMacro.swift`
- `docs/phase-2-canonical-types-results.md`

Updated:

- `Sources/SwiftAgentMacros/SwiftAgentMacroPlugin.swift`
- `Sources/SwiftAgentMacros/SessionSchema/SessionSchemaMacro.swift`
- SwiftAgent core/model/protocol/provider files that previously imported Apple `FoundationModels`
- OpenAI, Anthropic, SimulatedSession, ExampleCode, Example App, AgentRecorder scenario, and test files that referenced Apple `FoundationModels` primitives for this core slice
- `docs/any-language-model-merge-plan.md`

## Dependency Decisions

- No dependency additions.
- No dependency removals.
- `JSONSchema` was not added to the root package. Existing SwiftAgent provider SDK schema conversion continues through current SDK dependency types.
- `PartialJSONDecoder` was not added. Partial structured-output behavior remains handled by local `GeneratedContent(json:)` for this slice.
- MacPaw `OpenAI`, `SwiftAnthropic`, `EventSource`, and the copied ALM package metadata remain in place.

## Validation

Succeeded:

```bash
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -only-testing:SwiftAgentTests/DecodableToolJSONSchemaTests -only-testing:SwiftAgentTests/TranscriptCodableTests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentMacroTests -testPlan SwiftAgentMacroTests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme ExampleApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build -quiet
```

Attempted and blocked by local environment:

```bash
git diff --name-only -z -- '*.swift' | xargs -0 swiftformat --config .swiftformat
git ls-files --others --exclude-standard -z -- '*.swift' | xargs -0 swiftformat --config .swiftformat
```

Result:

```text
xargs: swiftformat: No such file or directory
xargs: swiftformat: No such file or directory
```

Verification command:

```bash
which swiftformat || true
```

Result:

```text
swiftformat not found
```

Plain AgentRecorder build was attempted:

```bash
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" build -quiet
```

Result: failed before compilation completed because this machine does not have the configured Mac Development signing certificate:

```text
No signing certificate "Mac Development" found: No "Mac Development" signing certificate matching team ID "7F6BJZY5B3" with a private key was found.
```

The same target compiled with signing disabled using the command recorded above.

## Follow-ups

- Resolve ALM `GenerationOptions` as part of the merged Phase 2 work, adding `JSONSchema` if the
  moved implementation naturally needs it.
- Move or adapt more ALM core tests for `GeneratedContent`, `GenerationSchema`, `DynamicGenerationSchema`, and `GenerationGuide`.
- Keep transcript/session/provider replacement work in the remaining merged Phase 2 workstreams;
  this slice only updated provider paths enough to consume local core primitives.

## GenerationOptions, JSONValue, LanguageModel, Session Surface Slice

Completed the next merged Phase 2 implementation step: initial main SwiftAgent options/model/session surface.

Implementation:

- Added a public `SwiftAgent` library product so `import SwiftAgent` exposes the main core target directly.
- Added `JSONSchema` to the root package and SwiftAgent target, then exposed `SwiftAgent.JSONValue` as `JSONSchema.JSONValue`.
- Added main `GenerationOptions` with shared sampling, temperature, maximum response token, minimum snapshot interval fields, and typed model-specific custom options keyed by `LanguageModel`.
- Added the initial main `LanguageModel` protocol, `LanguageModelFeedback`, and `LanguageModelSession(model:tools:instructions:)`.
- The new main session owns SwiftAgent transcript state, token usage accumulation, instructions/prompt/response transcript entries, and transcript-derived streaming snapshots.
- Merged the first ALM transcript addition into SwiftAgent by adding instruction transcript entries with model-visible tool definitions.
- Updated existing OpenAI, Anthropic, resolver, and example transcript switches to account for instruction entries without changing old SDK adapter behavior.
- Added focused Swift Testing coverage for `JSONValue`, custom options, response transcript/token state, and transcript-derived streaming snapshots.

Files changed:

- `Package.swift`
- `Package.resolved`
- `SwiftAgent.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `Sources/SwiftAgent/Core/GenerationOptions.swift`
- `Sources/SwiftAgent/Core/JSONValue.swift`
- `Sources/SwiftAgent/LanguageModel/LanguageModel.swift`
- `Sources/SwiftAgent/LanguageModel/LanguageModelFeedback.swift`
- `Sources/SwiftAgent/LanguageModel/LanguageModelSession.swift`
- `Sources/SwiftAgent/LanguageModel/Locked.swift`
- `Sources/SwiftAgent/Models/Transcript.swift`
- `Sources/SwiftAgent/Helpers/TranscriptResolver.swift`
- `Sources/OpenAISession/OpenAIAdapter.swift`
- `Sources/AnthropicSession/Helpers/AnthropicMessageBuilder.swift`
- `Sources/ExampleCode/ReadmeCode.swift`
- `Tests/SwiftAgentTests/Core/GenerationOptionsTests.swift`
- `Tests/SwiftAgentTests/Core/JSONValueTests.swift`
- `docs/phase-2-completion-checklist.md`
- `docs/phase-2-canonical-types-results.md`

Dependency decisions:

- Added approved `JSONSchema` to the root package because this slice moved `JSONValue` and main `GenerationOptions` custom-option payloads into SwiftAgent.
- `JSONSchema` resolved to `1.3.1`.
- Did not add `PartialJSONDecoder`; structured streaming and partial snapshot decoding were not moved in this slice.
- Did not remove MacPaw `OpenAI`.
- Did not remove `SwiftAnthropic`.
- Did not remove dependencies from `External/AnyLanguageModel`.
- Did not add MLX, Llama, CoreML, or AsyncHTTPClient to the base SwiftAgent target.
- Did not prune or delete `External/AnyLanguageModel`.

Validation succeeded:

```bash
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -only-testing:SwiftAgentTests/GenerationOptionsTests -only-testing:SwiftAgentTests/LanguageModelSessionTests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -only-testing:SwiftAgentTests/GenerationOptionsTests -only-testing:SwiftAgentTests/LanguageModelSessionTests -only-testing:SwiftAgentTests/JSONValueTests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme ExampleApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build -quiet
```

Attempted and blocked by local environment:

```bash
swiftformat --config ".swiftformat" Sources/SwiftAgent/Core/GenerationOptions.swift Sources/SwiftAgent/Core/JSONValue.swift Sources/SwiftAgent/LanguageModel/LanguageModel.swift Sources/SwiftAgent/LanguageModel/LanguageModelFeedback.swift Sources/SwiftAgent/LanguageModel/LanguageModelSession.swift Sources/SwiftAgent/LanguageModel/Locked.swift Sources/SwiftAgent/Models/Transcript.swift Sources/SwiftAgent/Helpers/TranscriptResolver.swift Sources/OpenAISession/OpenAIAdapter.swift Sources/AnthropicSession/Helpers/AnthropicMessageBuilder.swift Sources/ExampleCode/ReadmeCode.swift Tests/SwiftAgentTests/Core/GenerationOptionsTests.swift Tests/SwiftAgentTests/Core/JSONValueTests.swift
which swiftformat || true
```

Result:

```text
zsh:1: command not found: swiftformat
swiftformat not found
```

Transient validation issue:

```bash
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme ExampleApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" build -quiet
```

Result: failed with Xcode build database locking because multiple `xcodebuild` commands were started concurrently. The commands were rerun sequentially and passed as recorded above.

Follow-ups:

- Migrate provider-specific OpenAI and Anthropic custom option types into the main `GenerationOptions` custom-options model.
- Make direct OpenAI and Anthropic language models conform to the main `LanguageModel` boundary after transcript-first provider events and replay parity are ready.
- Continue merging transcript additions, tool execution policy, replay/logging hooks, and AgentRecorder/example/docs migration.

Phase 2 status: partial. This slice is durable main surface work, but Phase 2 is not complete because direct provider parity, full transcript merge, tool execution policy, and documentation/example migration remain open.

## Direct Provider, Transport, Streaming Tool Policy Checkpoint

Completed the next merged Phase 2 checkpoint: direct OpenAI/Open Responses and Anthropic providers now run through the main SwiftAgent model/session/tool-policy/transport path for replay-backed text, tool, structured-streaming, and streamed tool-call scenarios.

Implementation:

- Mechanically copied ALM direct provider source files into SwiftAgent, then refactored them into SwiftAgent's main architecture.
- Added direct `OpenAILanguageModel`, `OpenResponsesLanguageModel`, and `AnthropicLanguageModel` conformances to `LanguageModel`.
- Added provider capability reporting for the direct providers.
- Added `LanguageModelCapabilities`, rich stream event/metadata primitives, and `PartialJSONDecoder`-backed partial structured generation.
- Added session-owned `ToolExecutionPolicy`, `ToolExecutionDelegate`, serial/parallel execution, missing-tool behavior, failure behavior, and retry policy.
- Refactored direct providers to use `SwiftAgent.HTTPClient` with `URLSessionHTTPClient` as the default transport.
- Added an optional `SwiftAgentAsyncHTTPClient` target/product implementing `SwiftAgent.HTTPClient` for server-oriented users without adding AsyncHTTPClient to the base SwiftAgent target.
- Added transcript image segments and preserved image prompt conversion for direct OpenAI/Open Responses and Anthropic request builders.
- Implemented transcript-first direct-provider streaming for text, OpenAI Responses streamed function-call arguments, Anthropic streamed tool input JSON deltas, Anthropic thinking/signature deltas, token usage, tool-call transcript entries, and tool-output transcript entries.
- Added replay tests for direct provider text, streaming text, non-streaming tools, streaming tools, capability reporting, image transcript round trips, partial structured generation, and tool retry policy.
- Updated the Phase 2 plan and checklist so `docs/provider-capability-streaming-reference.md` and `docs/streaming-provider-gaps-spec.md` are explicit Phase 2 acceptance sources for OpenAI and Anthropic.

Files changed:

- `Package.swift`
- `Package.resolved`
- `Sources/SwiftAgent/LanguageModel/AnthropicLanguageModel.swift`
- `Sources/SwiftAgent/LanguageModel/LanguageModel.swift`
- `Sources/SwiftAgent/LanguageModel/LanguageModelCapabilities.swift`
- `Sources/SwiftAgent/LanguageModel/LanguageModelSession.swift`
- `Sources/SwiftAgent/LanguageModel/LanguageModelStreamEvent.swift`
- `Sources/SwiftAgent/LanguageModel/OpenAILanguageModel.swift`
- `Sources/SwiftAgent/LanguageModel/OpenResponsesLanguageModel.swift`
- `Sources/SwiftAgent/LanguageModel/PartialStructuredGeneration.swift`
- `Sources/SwiftAgent/LanguageModel/ToolExecution.swift`
- `Sources/SwiftAgent/Networking/HTTPClient+ProviderDecoding.swift`
- `Sources/SwiftAgentAsyncHTTPClient/AsyncHTTPClientTransport.swift`
- `Sources/SwiftAgent/Models/Transcript.swift`
- `Sources/SwiftAgent/Models/Transcript+Resolved.swift`
- `Sources/SwiftAgent/Helpers/TranscriptResolver.swift`
- `Sources/SwiftAgent/LanguageModelProvider/LanguageModelProvider.swift`
- `Sources/OpenAISession/OpenAIAdapter.swift`
- `Sources/AnthropicSession/Helpers/AnthropicMessageBuilder.swift`
- `Tests/SwiftAgentTests/Core/DirectProviderReplayTests.swift`
- `Tests/SwiftAgentTests/Core/LanguageModelCapabilitiesTests.swift`
- `Tests/SwiftAgentTests/Core/ToolExecutionPolicyTests.swift`
- `docs/phase-2-completion-checklist.md`
- `plans/phase-2-canonical-types-plan.md`
- `docs/phase-2-canonical-types-results.md`

Dependency decisions:

- Added approved `PartialJSONDecoder` to the base SwiftAgent target because direct provider structured streaming now uses partial structured decoding.
- Added `async-http-client` only for the optional `SwiftAgentAsyncHTTPClient` target/product. It was not added to the base SwiftAgent target.
- Kept `SwiftAgent.HTTPClient` as the provider-facing transport and `URLSessionHTTPClient` as the default implementation.
- Did not keep ALM `HTTPSession`, copied `Transport.swift`, or copied URLSession provider helpers as the final provider transport.
- Did not remove MacPaw `OpenAI`.
- Did not remove `SwiftAnthropic`.
- Did not remove dependencies from `External/AnyLanguageModel`.
- Did not add MLX, Llama, CoreML, or AsyncHTTPClient to the base SwiftAgent target.
- Did not prune or delete `External/AnyLanguageModel`.

Validation succeeded:

```bash
swift build --target SwiftAgent
swift build --target SwiftAgentAsyncHTTPClient
swift test --filter LanguageModelCapabilitiesTests
swift test --filter ToolExecutionPolicyTests
swift test --filter DirectProviderReplayTests
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests build -quiet
```

Failed during implementation and fixed:

```bash
swift test --filter DirectProviderReplayTests
```

Result before fixing the Open Responses streaming loop:

```text
openResponsesProviderStreamsToolCallsThroughMainSessionPolicy failed because OpenResponsesLanguageModel still used the old content-only streaming loop.
```

Attempted and blocked by local environment:

```bash
swiftformat --config ".swiftformat" Sources/AnthropicSession/Helpers/AnthropicMessageBuilder.swift Sources/OpenAISession/OpenAIAdapter.swift Sources/SwiftAgent/Helpers/TranscriptResolver.swift Sources/SwiftAgent/LanguageModel/AnthropicLanguageModel.swift Sources/SwiftAgent/LanguageModel/LanguageModel.swift Sources/SwiftAgent/LanguageModel/LanguageModelCapabilities.swift Sources/SwiftAgent/LanguageModel/LanguageModelSession.swift Sources/SwiftAgent/LanguageModel/LanguageModelStreamEvent.swift Sources/SwiftAgent/LanguageModel/OpenAILanguageModel.swift Sources/SwiftAgent/LanguageModel/OpenResponsesLanguageModel.swift Sources/SwiftAgent/LanguageModel/PartialStructuredGeneration.swift Sources/SwiftAgent/LanguageModel/ToolExecution.swift Sources/SwiftAgent/LanguageModelProvider/LanguageModelProvider.swift Sources/SwiftAgent/Models/Transcript+Resolved.swift Sources/SwiftAgent/Models/Transcript.swift Sources/SwiftAgent/Networking/HTTPClient+ProviderDecoding.swift Sources/SwiftAgentAsyncHTTPClient/AsyncHTTPClientTransport.swift Tests/SwiftAgentTests/Core/DirectProviderReplayTests.swift Tests/SwiftAgentTests/Core/LanguageModelCapabilitiesTests.swift Tests/SwiftAgentTests/Core/ToolExecutionPolicyTests.swift
```

Result:

```text
zsh:1: command not found: swiftformat
```

Follow-ups:

- Phase 2 remains partial.
- Provider response metadata, warnings, rate-limit details, and normalized stream errors still need to be surfaced through response/snapshot/logging APIs.
- Old `OpenAISession`, `AnthropicSession`, and `LanguageModelProvider` paths still need to become thin conveniences over the main session or be deprecated after parity evidence.
- AgentRecorder, README, examples, and public docs still need migration to the main API after provider parity is complete.
- Dependency removal proposals for MacPaw `OpenAI` and `SwiftAnthropic` still require explicit approval after parity evidence.

## Provider Metadata, AgentRecorder, And README Example Checkpoint

Completed the next merged Phase 2 implementation step: provider responses and streams now surface
metadata through the main `LanguageModelSession`, and AgentRecorder scenarios use direct
SwiftAgent providers instead of the old provider-session modules.

Implementation:

- Added `responseMetadata` to `LanguageModelSession.Response`, `ResponseStream.Snapshot`, and the
  session state.
- Added metadata merging so streamed provider metadata can arrive separately from content deltas
  without replacing the latest content snapshot.
- Parsed and surfaced response IDs, provider names, provider model IDs, and token usage for direct
  Open Responses, OpenAI Chat/Responses, and Anthropic Messages responses.
- Updated replay tests to assert provider metadata and usage on non-streaming and streaming paths.
- Migrated AgentRecorder OpenAI and Anthropic scenarios to `import SwiftAgent`,
  `OpenAILanguageModel` / `OpenResponsesLanguageModel` / `AnthropicLanguageModel`, and
  `LanguageModelSession(model:tools:instructions:)`.
- Reworked AgentRecorder recording helpers to build direct-provider `SwiftAgent.HTTPClient`
  transports with recorder interceptors.
- Updated `Sources/ExampleCode/ReadmeCode.swift` to build against `import SwiftAgent`, direct
  providers, main `GenerationOptions`, response metadata, streaming snapshots, and
  `@SessionSchema` transcript resolution examples.
- Adapted README in place to the main `SwiftAgent` API while preserving existing sections,
  including Session Schema, Groundings, Streaming, Proxy Servers, Simulated Session, Logging, and
  Recording HTTP Fixtures.
- Removed old provider-session and `SwiftAnthropic` dependencies from the `ExampleCode` target.
- Kept README adaptation preserve-first after review feedback: the existing README sections were
  adapted in place rather than replaced wholesale.

Files changed:

- `Package.swift`
- `AgentRecorder/AgentRecorder/Scenarios/Anthropic/AnthropicConfiguration+Recording.swift`
- `AgentRecorder/AgentRecorder/Scenarios/Anthropic/AnthropicRecordingModel.swift`
- `AgentRecorder/AgentRecorder/Scenarios/Anthropic/AnthropicStreamingTextScenario.swift`
- `AgentRecorder/AgentRecorder/Scenarios/Anthropic/AnthropicStreamingThinkingScenario.swift`
- `AgentRecorder/AgentRecorder/Scenarios/Anthropic/AnthropicStreamingToolCallsNoArgsPingScenario.swift`
- `AgentRecorder/AgentRecorder/Scenarios/Anthropic/AnthropicStreamingToolCallsWeatherScenario.swift`
- `AgentRecorder/AgentRecorder/Scenarios/Anthropic/AnthropicStructuredOutputScenario.swift`
- `AgentRecorder/AgentRecorder/Scenarios/Anthropic/AnthropicTextScenario.swift`
- `AgentRecorder/AgentRecorder/Scenarios/OpenAI/OpenAIConfiguration+Recording.swift`
- `AgentRecorder/AgentRecorder/Scenarios/OpenAI/OpenAIRecordingModel.swift`
- `AgentRecorder/AgentRecorder/Scenarios/OpenAI/OpenAIStreamingStructuredOutputScenario.swift`
- `AgentRecorder/AgentRecorder/Scenarios/OpenAI/OpenAIStreamingTextScenario.swift`
- `AgentRecorder/AgentRecorder/Scenarios/OpenAI/OpenAIStreamingToolCallsMultipleScenario.swift`
- `AgentRecorder/AgentRecorder/Scenarios/OpenAI/OpenAIStreamingToolCallsWeatherScenario.swift`
- `AgentRecorder/AgentRecorder/Scenarios/OpenAI/OpenAIStructuredOutputScenario.swift`
- `AgentRecorder/AgentRecorder/Scenarios/OpenAI/OpenAITextScenario.swift`
- `AgentRecorder/AgentRecorder/Scenarios/OpenAI/OpenAIToolCallsWeatherScenario.swift`
- `README.md`
- `Sources/ExampleCode/ReadmeCode.swift`
- `Sources/SwiftAgent/LanguageModel/AnthropicLanguageModel.swift`
- `Sources/SwiftAgent/LanguageModel/LanguageModelSession.swift`
- `Sources/SwiftAgent/LanguageModel/LanguageModelStreamEvent.swift`
- `Sources/SwiftAgent/LanguageModel/OpenAILanguageModel.swift`
- `Sources/SwiftAgent/LanguageModel/OpenResponsesLanguageModel.swift`
- `Tests/SwiftAgentTests/Core/DirectProviderReplayTests.swift`
- `docs/phase-2-completion-checklist.md`
- `docs/phase-2-canonical-types-results.md`
- `plans/phase-2-canonical-types-plan.md`

Dependency decisions:

- No new dependency additions in this checkpoint.
- Continued using approved `PartialJSONDecoder` for direct provider structured streaming.
- Continued using `SwiftAgent.HTTPClient` as the provider-facing transport and `URLSessionHTTPClient`
  as the default implementation.
- Did not add AsyncHTTPClient to the base `SwiftAgent` target.
- Did not remove MacPaw `OpenAI`.
- Did not remove `SwiftAnthropic`.
- Did not remove dependencies from `External/AnyLanguageModel`.
- Did not prune or delete `External/AnyLanguageModel`.

Validation succeeded:

```bash
swift test --filter DirectProviderReplayTests
swift build --target ExampleCode
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build -quiet
```

Phase 2 status: still partial until required final validation is rerun and approval-gated
dependency/product cleanup is either approved or explicitly deferred.
