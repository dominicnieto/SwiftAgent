import Foundation
import Testing

@testable import SwiftAgent

@Suite("ConvertibleToGeneratedContent")
struct ConvertibleToGeneratedContentTests {
    @Test func optionalNoneMapsToNullGeneratedContent() {
        let value: GeneratedContent? = nil
        #expect(value.generatedContent.kind == .null)
    }

    @Test func optionalSomeMapsToWrappedGeneratedContent() {
        let wrapped = GeneratedContent("hello")
        let value: GeneratedContent? = wrapped

        #expect(value.generatedContent == wrapped)
    }

    @Test func arrayMapsToArrayGeneratedContent() {
        let first = GeneratedContent("a")
        let second = GeneratedContent(2)
        let array = [first, second]

        #expect(array.generatedContent.kind == .array([first, second]))
    }

    @Test func defaultInstructionsAndPromptRepresentationsUseJSONString() throws {
        let content = GeneratedContent(properties: [
            "name": "AnyLanguageModel",
            "stars": 5,
        ])
        let expectedValue = try Self.jsonObject(from: content.jsonString)
        let instructionsValue = try Self.jsonObject(from: content.instructionsRepresentation.description)
        let promptValue = try Self.jsonObject(from: content.promptRepresentation.formatted())

        #expect(instructionsValue == expectedValue)
        #expect(promptValue == expectedValue)
    }

    private static func jsonObject(from string: String) throws -> NSObject {
        guard let object = try JSONSerialization.jsonObject(
            with: Data(string.utf8),
            options: [.fragmentsAllowed]
        ) as? NSObject else {
            throw JSONComparisonError.unsupportedTopLevelValue
        }
        return object
    }

    private enum JSONComparisonError: Error {
        case unsupportedTopLevelValue
    }
}
