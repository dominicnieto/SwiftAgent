// By Dennis Müller

import Foundation
@testable import SimulatedSession
@testable import SwiftAgent
import Testing

@SessionSchema
private struct SessionSchema {}

@Suite("Simulation - Multi-turn - Exhaustion")
struct SimulationMultiTurnExhaustionTests {
  typealias Transcript = SwiftAgent.Transcript

  // MARK: - Properties

  private let session: SimulatedSession<SessionSchema>

  // MARK: - Initialization

  init() async {
    let configuration = SimulationConfiguration(
      defaultGenerations: [
        .textResponse("First turn"),
        .textResponse("Second turn"),
      ],
      generationDelay: .zero,
    )

    session = SimulatedSession(
      schema: SessionSchema(),
      instructions: "",
      configuration: configuration,
    )
  }

  @Test("Default generations are consumed across turns and eventually exhaust")
  func defaultGenerationsConsumeAcrossTurnsAndExhaust() async throws {
    let first = try await session.respond(to: "Prompt 1", using: .default)
    #expect(first.content == "First turn")

    let transcriptAfterFirst = await session.transcript
    #expect(transcriptAfterFirst.count == 2)
    validatePromptResponsePair(
      transcriptAfterFirst,
      prompt: "Prompt 1",
      response: "First turn",
      startingAt: 0,
    )

    let second = try await session.respond(to: "Prompt 2", using: .default)
    #expect(second.content == "Second turn")

    let transcriptAfterSecond = await session.transcript
    #expect(transcriptAfterSecond.count == 4)
    validatePromptResponsePair(
      transcriptAfterSecond,
      prompt: "Prompt 2",
      response: "Second turn",
      startingAt: 2,
    )

    do {
      _ = try await session.respond(to: "Prompt 3", using: .default)
      Issue.record("Expected generation to exhaust default generations and throw")
    } catch {
      guard let configurationError = error as? SimulationConfigurationError else {
        Issue.record("Expected SimulationConfigurationError but received \(error)")
        return
      }

      switch configurationError {
      case .missingGenerations:
        break
      }
    }
  }

  // MARK: - Private

  private func validatePromptResponsePair(
    _ transcript: Transcript,
    prompt: String,
    response: String,
    startingAt startIndex: Int,
  ) {
    guard transcript.indices.contains(startIndex) else {
      Issue.record("Transcript missing prompt entry at index \(startIndex)")
      return
    }
    guard transcript.indices.contains(startIndex + 1) else {
      Issue.record("Transcript missing response entry at index \(startIndex + 1)")
      return
    }
    guard case let .prompt(promptEntry) = transcript[startIndex] else {
      Issue.record("Expected transcript entry \(startIndex) to be .prompt")
      return
    }

    #expect(promptEntry.input == prompt)

    guard case let .response(responseEntry) = transcript[startIndex + 1] else {
      Issue.record("Expected transcript entry \(startIndex + 1) to be .response")
      return
    }

    #expect(responseEntry.segments.count == 1)

    guard case let .text(textSegment) = responseEntry.segments.first else {
      Issue.record("Expected response segment to be .text")
      return
    }

    #expect(textSegment.content == response)
  }
}
