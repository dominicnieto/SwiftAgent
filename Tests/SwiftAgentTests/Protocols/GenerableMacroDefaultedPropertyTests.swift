// By Dennis Müller

@testable import SwiftAgent
import Testing

@Generable
private struct DefaultedNestedValue: Equatable {
  var value: String = "nested"
}

@Generable
private struct DefaultedGeneratedContentFixture: Equatable {
  var title: String
  var count: Int = 7
  var isEnabled: Bool = true
  var tags: [String] = ["swift", "agent"]
  var nickname: String? = "helper"
  var nested: DefaultedNestedValue = DefaultedNestedValue()
}

@Suite("@Generable defaulted properties")
struct GenerableMacroDefaultedPropertyTests {
  @Test("Generated memberwise initializer preserves stored property defaults")
  func memberwiseInitializerPreservesDefaults() throws {
    let fixture = DefaultedGeneratedContentFixture(title: "Forecast")

    #expect(fixture.title == "Forecast")
    #expect(fixture.count == 7)
    #expect(fixture.isEnabled)
    #expect(fixture.tags == ["swift", "agent"])
    #expect(fixture.nickname == "helper")
    #expect(fixture.nested == DefaultedNestedValue())

    let roundTrip = try DefaultedGeneratedContentFixture(fixture.generatedContent)
    #expect(roundTrip == fixture)
  }

  @Test("Missing generated content fields use stored property defaults")
  func missingGeneratedContentFieldsUseDefaults() throws {
    let content = GeneratedContent(properties: [
      "title": "Forecast"
    ])

    let fixture = try DefaultedGeneratedContentFixture(content)

    #expect(fixture.title == "Forecast")
    #expect(fixture.count == 7)
    #expect(fixture.isEnabled)
    #expect(fixture.tags == ["swift", "agent"])
    #expect(fixture.nickname == "helper")
    #expect(fixture.nested == DefaultedNestedValue())
  }

  @Test("Explicit null optional generated content still decodes as nil")
  func explicitNullOptionalGeneratedContentDecodesAsNil() throws {
    let content = GeneratedContent(properties: [
      "title": "Forecast",
      "nickname": GeneratedContent(kind: .null),
    ])

    let fixture = try DefaultedGeneratedContentFixture(content)

    #expect(fixture.nickname == nil)
  }
}
