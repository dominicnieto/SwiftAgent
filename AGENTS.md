# AGENTS.md

**Native Swift SDK for building autonomous AI agents with Apple's FoundationModels design philosophy**

SwiftAgent simplifies AI agent development by providing a clean, intuitive API that handles all the complexity of agent loops, tool execution, and adapter communication. Inspired by Apple's FoundationModels framework, it brings the same elegant, declarative approach to cross-platform AI agent development.

---

## How to work in this repo

These are the defaults and conventions that keep changes consistent and easy to review.

### Expectations

- **After code changes:** build the app to make sure it still compiles.
- **After test changes:** run the relevant unit/UI tests (and the suite when appropriate).
- **Text & localization:** use the repo’s SwiftUI localization approach (String Catalog with plain `Text` / `LocalizedStringKey`).
- **Style bias:** readability beats cleverness; keep types and files small where possible.
- **Commits:** only commit when you’re explicitly asked to.

### Before you wrap up

- Always build the project for all supported platforms (and run tests if your changes touch them or could reasonably affect them).
- If you changed Swift files, always run: `swiftformat --config ".swiftformat" {files}`

---

## Project guidelines

### Documentation

- If you touch it, give it solid doc strings.
- For anything non-trivial, leave a comment explaining the "what" and “why”.

### Swift & file conventions

- Prefer descriptive, English-like names (skip abbreviations unless they’re truly standard).
- If a file is getting large or multi-purpose, feel free to split it into reusable components when that improves clarity.

### SwiftUI view organization

- In view types, declare properties as `var` (not `let`).
- Use `#Preview(traits: .tesseraDesigner)` for previews.
- For state-driven animation, prefer `.animation(.default, value: ...)` over scattered `withAnimation`.
  - Put `.animation` as high in the hierarchy as you can so containers/scroll views animate naturally.
- Prefer `$`-derived bindings (`$state`, `$binding`, `@Bindable` projections).
  - Avoid manual `Binding(get:set:)` unless it genuinely simplifies an adaptation (optional defaults, type bridging, etc.). If you do use it, leave a short note explaining why.
- Prefer `.onChange(of: value) { ... }` with no closure arguments; read `value` inside the closure.
- Push `@State` as deep as possible, but keep it as high as necessary. Don’t default to hoisting everything to the root.

### Layout, spacing, and styling

- Use `Layout.Spacing` and `Layout.Padding` tokens from `DesignSystem/Layout.swift`.
- Use the `HStack`/`VStack` custom initializers that accept spacing tokens.
- Use the `.padding(_:)` extension that takes `Layout.Padding`.
- For consistent visuals, reach for `Card`, `CollapsibleCard`, and `cardStyle` (material backgrounds + borders).

### Control views pattern

- `ControlView` is the standard wrapper for label/subtitle + content + trailing accessory.
- Use `Divider()` between grouped control rows; when needed, pad dividers so they align with card edges.

### Localization and text

- Use string literals in `Text` and `LocalizedStringKey` (String Catalog).
- Use `String(localized:)` outside SwiftUI or when a `LocalizedStringKey` initializer isn’t available.
- Use `.help(...)` for macOS tooltips when it adds value (it’s cross-platform, but only displays on macOS).

---

## Build & test commands

- Build SDK
  - `xcodebuild -quiet -workspace SwiftAgent.xcworkspace -scheme ExampleApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" build`
- Build Utility App
  - `xcodebuild -quiet -workspace SwiftAgent.xcworkspace -scheme UtilityApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" build`
- Build Tests
  - `xcodebuild -quiet -workspace SwiftAgent.xcworkspace -scheme UtilityApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" build`
- Run Tests
  - `xcodebuild -quiet -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests test`
- Prefer keeping `-quiet` on; if something fails and you need more logs, drop it temporarily.




























## General Instructions

- Whenever you make changes to the code, build the project to ensure everything still compiles
- Whenever you make changes to unit tests, run the testsuite to verify the changes.
- Always follow the best practices of naming things in Swift
- Always use clear names for types and variables, don't just use single letters or abbreviations. Clarity is key!
- In SwiftUI views, always place private properties on top of the non-private ones, and the non-private ones directly above the initializer
- Do not collapse declarations into single-line statements. Expand types, properties, closures, and functions across multiple lines for readability.

### **IMPORTANT**: Before you start

- Check if you should read a resource or guideline related to your task

### When you are done

- Build the project to check for compilation errors
- When you have added or modified Swift files, run `swiftformat --config ".swiftformat" {files}`.
  - For large refactors, run `swiftformat` on the touched subdirectories only.

## Symbol Inspection (`monocle` cli)
 
- Treat the `monocle` cli as your **default tool** for Swift symbol info. 
  Whenever you need the definition file, signature, parameters, or doc comment for any Swift symbol (type, class, struct, enum, method, property, etc.), call `monocle` rather than guessing or doing project-wide searches.
- List checked-out SwiftPM dependencies (so you can open and read external packages): `monocle packages --json`
- Resolve the symbol at a specific location: `monocle inspect --file <path> --line <line> --column <column> --json`
- Line and column values are **1-based**, not 0-based; the column must point inside the identifier
- Search workspace symbols by name when you only know the identifier: `monocle symbol --query "TypeOrMember" --limit 5 --json`.
  - `--limit` caps the number of results (default 5).
  - `--enrich` fetches signature, documentation, and the precise definition location for each match.
- Use `monocle` especially for symbols involved in errors/warnings or coming from external package dependencies.

## Available MCPs

- `sosumi` mcp - Access to Apple's documentation for all Swift and SwiftUI APIs, guidelines and best practices. Use this to complement or fix/enhance your potentially outdated knowledge of these APIs.
- `context7` - Access to documentation for a large amount of libraries and SDKs, including:
  - MacPaw: "OpenAI Swift" - Swift implementation of the OpenAI API (Responses API)
  - Swift Syntax: When working with Swift Macros, you can refer to this since its APIs constantly change which might cause problems for you
- You can use GitHub's `gh` cli to interact with the GitHub repository, but you need to call it with elevated permissions

## Development Commands

#### Build SDK

```
xcodebuild -quiet -workspace SwiftAgent.xcworkspace -scheme ExampleApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" build
```

#### Build Utility App

```
xcodebuild -quiet -workspace SwiftAgent.xcworkspace -scheme UtilityApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" build
```

#### Build Tests

```
xcodebuild -quiet -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests build
```

#### Run Tests

```
xcodebuild -quiet -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests test
```
