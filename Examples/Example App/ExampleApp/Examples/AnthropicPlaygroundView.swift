// By Dennis Müller

import SwiftAgent
import SwiftUI
import UIKit

struct AnthropicPlaygroundView: View {
  @State private var userInput = """
  Choose a random city and request a weather report. Then use the calculator to
  multiply the temperature by 5 and finally answer with a short story (1-2 paragraphs) involving the tool call
  outputs in some funny way.
  """
  @State private var transcript: Transcript.Resolved<SessionSchema> = .init()
  @State private var streamingTranscript: Transcript.Resolved<SessionSchema> = .init()
  @State private var sessionSchema = SessionSchema()
  @State private var executionMode: PlaygroundExecutionMode = .agentSession
  @State private var directSession: LanguageModelSession?
  @State private var agentSession: AgentSession?

  @State private var viewState: ViewState = .idle
  @State private var messageTask: Task<Void, Never>?
  @State private var error: (any Error)?

  // MARK: - Body

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading) {
          content
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .defaultScrollAnchor(.bottom)
      .onAppear(perform: setupSessions)
      .onChange(of: executionMode) {
        resetConversation()
      }
      .safeAreaBar(edge: .bottom) {
        if let error {
          Text(error.localizedDescription)
            .font(.callout)
            .foregroundStyle(.red)
            .transition(.opacity.combined(with: .scale))
        }
      }
      .safeAreaBar(edge: .bottom) {
        GlassEffectContainer {
          HStack(alignment: .bottom) {
            TextField("Message", text: $userInput, axis: .vertical)
              .padding(.horizontal)
              .padding(.vertical, 10)
              .frame(maxWidth: .infinity, alignment: .leading)
              .frame(minHeight: 45)
              .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 45 / 2))
            Button {
              messageTask?.cancel()
              messageTask = Task {
                await sendMessage()
              }
            } label: {
              if viewState == .loading {
                ProgressView()
                  .frame(width: 45, height: 45)
                  .transition(.opacity.combined(with: .scale))
              } else {
                Image(systemName: "arrow.up")
                  .frame(width: 45, height: 45)
                  .transition(.opacity.combined(with: .scale))
              }
            }
            .glassEffect(.regular.interactive())
          }
        }
        .padding()
      }
      .animation(.default, value: streamingTranscript)
      .animation(.default, value: viewState)
      .navigationTitle("Anthropic Playground")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          modeMenu
        }
      }
    }
  }

  @ViewBuilder
  private var modeMenu: some View {
    Menu {
      ForEach(PlaygroundExecutionMode.allCases) { mode in
        Button {
          executionMode = mode
        } label: {
          if executionMode == mode {
            Label(mode.title, systemImage: "checkmark")
          } else {
            Text(mode.title)
          }
        }
      }
    } label: {
      Label(executionMode.title, systemImage: "switch.2")
    }
    .help("Execution mode")
  }

  @ViewBuilder
  private var content: some View {
    let visibleTranscript = streamingTranscript.isEmpty ? transcript : streamingTranscript
    ForEach(visibleTranscript) { entry in
      switch entry {
      case let .prompt(prompt):
        PromptEntryView(prompt: prompt)
      case let .reasoning(reasoning):
        ReasoningEntryView(reasoning: reasoning)
      case let .toolRun(toolRun):
        ToolRunEntryView(toolRun: toolRun)
      case let .response(response):
        ResponseEntryView(response: response)
      }
    }
  }

  private func setupSessions() {
    directSession = LanguageModelSession(
      model: makeModel(),
      tools: [sessionSchema.calculator, sessionSchema.weather],
      instructions: instructions,
    )
    agentSession = AgentSession(
      model: makeModel(),
      schema: sessionSchema,
      instructions: instructions,
    )
  }

  private func resetConversation() {
    messageTask?.cancel()
    transcript = .init()
    streamingTranscript = .init()
    error = nil
    viewState = .idle
    setupSessions()
  }

  private func makeModel() -> AnthropicLanguageModel {
    AnthropicLanguageModel(
      apiKey: Secret.Anthropic.apiKey,
      model: "claude-sonnet-4-5-20250929",
    )
  }

  private var instructions: String {
    """
    You are a helpful assistant with access to several tools.
    Use the available tools when appropriate to help answer questions.
    Be concise but informative in your responses.
    """
  }

  // MARK: - Actions

  private func sendMessage() async {
    guard userInput.isEmpty == false else { return }

    let userInput = userInput
    self.userInput = ""
    viewState = .loading

    do {
      var options = GenerationOptions(
        maximumResponseTokens: 10_000,
        minimumStreamingSnapshotInterval: .milliseconds(150),
      )
      options[custom: AnthropicLanguageModel.self] = .init(
        thinking: .init(budgetTokens: 1_024),
      )

      switch executionMode {
      case .languageModelSession:
        try await streamDirectSession(input: userInput, options: options)
      case .agentSession:
        try await streamAgentSession(input: userInput, options: options)
      }

      viewState = .idle
    } catch {
      print("Error", error.localizedDescription)
      viewState = .error
      self.error = error
    }
  }

  private func streamDirectSession(input: String, options: GenerationOptions) async throws {
    guard let directSession else { return }

    let stream = try directSession.streamResponse(
      to: input,
      schema: sessionSchema,
      groundingWith: [.currentDate(Date())],
      options: options,
    ) { input, sources in
      PromptTag("context") {
        for source in sources {
          switch source {
          case let .currentDate(date):
            PromptTag("current-date") { date }
          }
        }
      }

      PromptTag("input") {
        input
      }
    }

    let resolver = sessionSchema.transcriptResolver()
    for try await snapshot in stream {
      streamingTranscript = try resolver.resolve(snapshot.transcript)
    }

    transcript = streamingTranscript
    streamingTranscript = .init()
  }

  private func streamAgentSession(input: String, options: GenerationOptions) async throws {
    guard let agentSession else { return }

    let stream = try agentSession.stream(
      to: input,
      schema: sessionSchema,
      groundingWith: [.currentDate(Date())],
      options: options,
    ) { input, sources in
      PromptTag("context") {
        for source in sources {
          switch source {
          case let .currentDate(date):
            PromptTag("current-date") { date }
          }
        }
      }

      PromptTag("input") {
        input
      }
    }

    let resolver = sessionSchema.transcriptResolver()
    for try await event in stream {
      switch event {
      case let .completed(result):
        streamingTranscript = try resolver.resolve(result.transcript)
      default:
        streamingTranscript = try resolver.resolve(agentSession.transcript)
      }
    }

    transcript = streamingTranscript
    streamingTranscript = .init()
  }
}

// MARK: - Entry Views

private struct PromptEntryView: View {
  var prompt: Transcript.Resolved<SessionSchema>.Prompt

  var body: some View {
    Text(prompt.input)
  }
}

private struct ReasoningEntryView: View {
  var reasoning: Transcript.Resolved<SessionSchema>.Reasoning

  var body: some View {
    Text(reasoning.summary.joined(separator: ", "))
      .foregroundStyle(.secondary)
  }
}

private struct ToolRunEntryView: View {
  var toolRun: SessionSchema.DecodedToolRun

  var body: some View {
    switch toolRun {
    case let .calculator(calculatorRun):
      CalculatorToolRunView(calculatorRun: calculatorRun)
    case let .weather(weatherRun):
      WeatherToolRunView(weatherRun: weatherRun)
    case let .unknown(toolCall):
      GroupBox("Unknown Tool") {
        Text(toolCall.toolName)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}

private struct ResponseEntryView: View {
  var response: Transcript.Resolved<SessionSchema>.Response

  var body: some View {
    if let text = response.text {
      HorizontalGeometryReader { width in
        UILabelView(
          string: text,
          preferredMaxLayoutWidth: width,
        )
      }
    }
  }
}

// MARK: - Helpers

private enum ViewState: Hashable {
  case idle
  case loading
  case error
}


#Preview {
  AnthropicPlaygroundView()
    .preferredColorScheme(.dark)
}
