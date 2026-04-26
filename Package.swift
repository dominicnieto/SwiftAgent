// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "SwiftAgent",
  platforms: [
    .iOS(.v26),
    .macOS(.v26),
  ],
  products: [
    .library(name: "SwiftAgent", targets: ["SwiftAgent"]),
    .library(name: "SimulatedSession", targets: ["SimulatedSession"]),
    .library(name: "ExampleCode", targets: ["ExampleCode"]),
  ],
  traits: [
    .trait(name: "AsyncHTTPClient", description: "Enable the AsyncHTTPClient-backed SwiftAgent HTTP transport."),
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"603.0.0"),
    .package(url: "https://github.com/mattt/EventSource", from: "1.2.0"),
    .package(url: "https://github.com/mattt/JSONSchema", from: "1.3.0"),
    .package(url: "https://github.com/mattt/PartialJSONDecoder", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-macro-testing", from: "0.6.4"),
    .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.24.0"),
  ],
  targets: [
    .macro(
      name: "SwiftAgentMacros",
      dependencies: [
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
      ],
    ),
    .target(
      name: "SwiftAgent",
      dependencies: [
        "SwiftAgentMacros",
        "EventSource",
        .product(name: "JSONSchema", package: "JSONSchema"),
        .product(name: "PartialJSONDecoder", package: "PartialJSONDecoder"),
        .product(
          name: "AsyncHTTPClient",
          package: "async-http-client",
          condition: .when(traits: ["AsyncHTTPClient"]),
        ),
      ],
      swiftSettings: [
        .define("SWIFTAGENT_ASYNC_HTTP_CLIENT", .when(traits: ["AsyncHTTPClient"])),
      ],
    ),
    .target(
      name: "SimulatedSession",
      dependencies: [
        "SwiftAgent",
      ],
    ),
    .target(
      name: "ExampleCode",
      dependencies: [
        "SwiftAgent",
      ],
    ),
    .testTarget(
      name: "SwiftAgentTests",
      dependencies: [
        "SwiftAgent",
        "SimulatedSession",
      ],
    ),
    .testTarget(
      name: "SwiftAgentMacroTests",
      dependencies: [
        "SwiftAgentMacros",
        .product(name: "MacroTesting", package: "swift-macro-testing"),
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
      ],
    ),
  ],
  swiftLanguageModes: [.v6],
)
