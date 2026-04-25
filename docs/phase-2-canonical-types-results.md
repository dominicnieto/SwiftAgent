# Phase 2 Canonical Types Results

## Summary

Implemented the first Phase 2 vertical slice for local FoundationModels-style primitives.

Phase 2 status: partial. Phase 2 is not complete. This result covers the first vertical slice:
local core primitives, macro references, and the current provider/test/example call sites needed
to consume those primitives. Later slices also resolved `@Generable` defaulted-property parity,
migrated focused ALM core tests for canonical SwiftAgent primitives, and completed the Phase 2
prompt ownership slice. Transcript/session/provider replacement, unified generation options,
provider capabilities, and direct provider migration remain deferred to later approved slices.

SwiftAgent now owns ALM-derived local definitions for:

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
  builders, or provider-neutral schema conversion move into SwiftAgent with explicit approval.
- `PartialJSONDecoder` remains deferred until structured streaming / partial snapshot work needs it
  with explicit approval.

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
- Phase 2 remains partial because the checklist still has incomplete canonical ownership and
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
  builders, or provider-neutral schema conversion move into SwiftAgent with explicit approval.
- `PartialJSONDecoder` remains deferred until structured streaming / partial snapshot work needs it
  with explicit approval.

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

## Prompt Canonical Ownership And Prompt/Instructions Test Slice

Completed the next Phase 2 implementation step from `docs/phase-2-completion-checklist.md`:
canonical `Prompt` ownership plus another focused ALM core test migration slice.

Implementation:

- Kept SwiftAgent's existing `Prompt`/`PromptBuilder` as the canonical prompt implementation
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
  request explicit approval before adding `JSONSchema` to the root package.

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
- Ask for explicit `JSONSchema` approval before editing `Package.swift` for the
  `GenerationOptions` / `JSONValue` slice.
- Broader ALM core tests for generated content, schemas, transcript, generation options, and tool
  execution still need migration/classification.

Final review on April 25, 2026:

- Rechecked the uncommitted diff scope: only the prompt slice Swift files, prompt/instructions
  tests, and Phase 2 tracking docs are changed.
- Confirmed no uncommitted `Package.swift`, `Package.resolved`, `External/AnyLanguageModel`, or
  `.swiftpm/xcode/xcshareddata/xcschemes/*.xcscheme` changes.
- Confirmed no `.DS_Store` files are present.
- Confirmed MacPaw `OpenAI` and `SwiftAnthropic` dependencies/imports remain in place.
- Confirmed this slice did not start Phase 3 transcript/session streaming redesign, Phase 4/5
  provider replacement, dependency removal, or `External/AnyLanguageModel` pruning.

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

- Decide in a later approved slice how much of ALM `GenerationOptions` should move into SwiftAgent without adding `JSONSchema` or other dependencies prematurely.
- Move or adapt more ALM core tests for `GeneratedContent`, `GenerationSchema`, `DynamicGenerationSchema`, and `GenerationGuide`.
- Keep transcript/session/provider replacement work for later phases; this slice only updated provider paths enough to consume local core primitives.
