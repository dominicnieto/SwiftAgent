import Foundation
import JSONSchema

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A language model that connects to APIs conforming to the
/// [Open Responses](https://www.openresponses.org) specification.
///
/// Open Responses defines a shared schema for multi-provider, interoperable LLM
/// interfaces based on the OpenAI Responses API. Use this model with any
/// provider that implements the Open Responses spec (e.g. OpenAI, OpenRouter,
/// or other compatible endpoints).
///
/// ```swift
/// let model = OpenResponsesLanguageModel(
///     baseURL: URL(string: "https://openrouter.ai/api/v1/")!,
///     apiKey: "your-api-key",
///     model: "openai/gpt-4o-mini"
/// )
/// ```
public struct OpenResponsesLanguageModel: EventStreamingLanguageModel, StreamingToolCallLanguageModel, StructuredOutputLanguageModel {
    /// Default OpenAI-compatible Responses API base URL.
    public static let defaultBaseURL = URL(string: "https://api.openai.com/v1/")!

    /// The reason the model is unavailable.
    /// This model is always available.
    public typealias UnavailableReason = Never

    /// Custom generation options for Open Responses–compatible APIs.
    ///
    /// Includes Open Responses–specific fields such as ``toolChoice`` (including
    /// ``ToolChoice/allowedTools(tools:mode:)``), ``allowedTools``, and
    /// reasoning/text options. Use ``extraBody`` for parameters not yet modeled.
    public struct CustomGenerationOptions: SwiftAgent.CustomGenerationOptions, Codable, Sendable {
        /// Controls which tool the model should use, if any.
        public var toolChoice: ToolChoice?

        /// The list of tools that are permitted for this request.
        /// When set, the model may only call tools in this list.
        public var allowedTools: [String]?

        /// Nucleus sampling parameter, between 0 and 1.
        /// The model considers only the tokens with the top cumulative probability.
        public var topP: Double?

        /// Penalizes new tokens based on whether they appear in the text so far.
        public var presencePenalty: Double?

        /// Penalizes new tokens based on their frequency in the text so far.
        public var frequencyPenalty: Double?

        /// Whether the model may call multiple tools in parallel.
        public var parallelToolCalls: Bool?

        /// The maximum number of tool calls the model may make while generating the response.
        public var maxToolCalls: Int?

        /// Reasoning effort for reasoning-capable models.
        public var reasoningEffort: ReasoningEffort?

        /// Configuration options for reasoning behavior.
        public var reasoning: ReasoningConfiguration?

        /// Controls the level of detail in generated text output.
        public var verbosity: Verbosity?

        /// The maximum number of tokens the model may generate for this response.
        public var maxOutputTokens: Int?

        /// Whether to store the response so it can be retrieved later.
        public var store: Bool?

        /// Set of key-value pairs attached to the request.
        /// Keys are strings with a maximum length of 64 characters;
        /// values are strings with a maximum length of 512 characters.
        public var metadata: [String: String]?

        /// A stable identifier used for safety monitoring and abuse detection.
        public var safetyIdentifier: String?

        /// Controls how the service truncates the input when it exceeds the model context window.
        public var truncation: Truncation?

        /// Additional parameters merged into the request body (applied last).
        public var extraBody: [String: JSONValue]?

        /// Controls which tool the model should use, if any.
        /// See [tool_choice](https://www.openresponses.org/reference#tool_choice) in the Open Responses reference.
        public enum ToolChoice: Hashable, Codable, Sendable {
            /// Restrict the model from calling any tools.
            case none
            /// Let the model choose the tools from among the provided set.
            case auto
            /// Require the model to call a tool.
            case required
            /// Require the model to call the named function.
            case function(name: String)
            /// Restrict tool calls to the given tools with the specified mode.
            case allowedTools(tools: [String], mode: AllowedToolsMode = .auto)

            private enum CodingKeys: String, CodingKey {
                case type
                case name
                case tools
                case mode
            }

            private enum ToolType: String {
                case function
                case allowedTools = "allowed_tools"
            }

            private static func decodeToolDescriptorArray(
                container: KeyedDecodingContainer<CodingKeys>,
                key: CodingKeys
            ) throws -> [String] {
                var arr = try container.nestedUnkeyedContainer(forKey: key)
                var names: [String] = []
                while !arr.isAtEnd {
                    do {
                        let nested = try arr.nestedContainer(keyedBy: ToolDescriptorCodingKeys.self)
                        let typeStr = try nested.decode(String.self, forKey: .type)
                        guard typeStr == "function" else {
                            throw DecodingError.dataCorruptedError(
                                forKey: key,
                                in: container,
                                debugDescription: "Unsupported tool descriptor type: \(typeStr)"
                            )
                        }
                        names.append(try nested.decode(String.self, forKey: .name))
                    } catch {
                        let name = try arr.decode(String.self)
                        names.append(name)
                    }
                }
                return names
            }

            private enum ToolDescriptorCodingKeys: String, CodingKey {
                case type
                case name
            }

            private struct ToolDescriptorEncodable: Encodable {
                let name: String
                func encode(to encoder: Encoder) throws {
                    var c = encoder.container(keyedBy: ToolDescriptorCodingKeys.self)
                    try c.encode(ToolType.function.rawValue, forKey: .type)
                    try c.encode(name, forKey: .name)
                }
            }

            public init(from decoder: Decoder) throws {
                if let singleValueContainer = try? decoder.singleValueContainer(),
                    let stringValue = try? singleValueContainer.decode(String.self)
                {
                    switch stringValue {
                    case "none": self = .none
                    case "auto": self = .auto
                    case "required": self = .required
                    default:
                        throw DecodingError.dataCorruptedError(
                            in: singleValueContainer,
                            debugDescription: "Invalid tool_choice string value: \(stringValue)"
                        )
                    }
                    return
                }
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let typeString = try container.decode(String.self, forKey: .type)
                switch ToolType(rawValue: typeString) {
                case .function?:
                    let name = try container.decode(String.self, forKey: .name)
                    self = .function(name: name)
                case .allowedTools?:
                    let tools = try Self.decodeToolDescriptorArray(container: container, key: .tools)
                    let mode = try container.decodeIfPresent(AllowedToolsMode.self, forKey: .mode) ?? .auto
                    self = .allowedTools(tools: tools, mode: mode)
                case nil:
                    throw DecodingError.dataCorruptedError(
                        forKey: .type,
                        in: container,
                        debugDescription: "Unsupported tool_choice type: \(typeString)"
                    )
                }
            }

            public func encode(to encoder: Encoder) throws {
                switch self {
                case .none:
                    var container = encoder.singleValueContainer()
                    try container.encode("none")
                case .auto:
                    var container = encoder.singleValueContainer()
                    try container.encode("auto")
                case .required:
                    var container = encoder.singleValueContainer()
                    try container.encode("required")
                case .function(let name):
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    try container.encode(ToolType.function.rawValue, forKey: .type)
                    try container.encode(name, forKey: .name)
                case .allowedTools(let tools, let mode):
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    try container.encode(ToolType.allowedTools.rawValue, forKey: .type)
                    try container.encode(
                        tools.map { ToolDescriptorEncodable(name: $0) },
                        forKey: .tools
                    )
                    if mode != .auto {
                        try container.encode(mode, forKey: .mode)
                    }
                }
            }

            /// How to select a tool from the allowed set.
            /// See [AllowedToolChoice](https://www.openresponses.org/reference#allowedtoolchoice) in the Open Responses reference.
            public enum AllowedToolsMode: String, Hashable, Codable, Sendable {
                /// Restrict the model from calling any tools.
                case none
                /// Let the model choose the tools from among the provided set.
                case auto
                /// Require the model to call a tool.
                case required
            }
        }

        /// Reasoning effort level for models that support extended reasoning.
        /// See [ReasoningEffortEnum](https://www.openresponses.org/reference#reasoningeffortenum) in the Open Responses reference.
        public enum ReasoningEffort: String, Hashable, Codable, Sendable {
            /// Restrict the model from performing any reasoning before emitting a final answer.
            case none
            /// Use a lower reasoning effort for faster responses.
            case low
            /// Use a balanced reasoning effort.
            case medium
            /// Use a higher reasoning effort to improve answer quality.
            case high
            /// Use the maximum reasoning effort available.
            case xhigh
        }

        /// Configuration options for reasoning behavior.
        /// See [ReasoningParam](https://www.openresponses.org/reference#reasoningparam) in the Open Responses reference.
        public struct ReasoningConfiguration: Hashable, Codable, Sendable {
            /// The level of reasoning effort the model should apply.
            /// Higher effort may increase latency and cost.
            public var effort: ReasoningEffort?
            /// Controls whether the response includes a reasoning summary
            /// (e.g. `concise`, `detailed`, or `auto`).
            public var summary: String?

            /// Creates a reasoning configuration.
            ///
            /// - Parameters:
            ///   - effort: The level of reasoning effort the model should apply.
            ///   - summary: Optional reasoning summary preference for the model.
            public init(effort: ReasoningEffort? = nil, summary: String? = nil) {
                self.effort = effort
                self.summary = summary
            }
        }

        /// Controls the level of detail in generated text output.
        /// See [VerbosityEnum](https://www.openresponses.org/reference#verbosityenum) in the Open Responses reference.
        public enum Verbosity: String, Hashable, Codable, Sendable {
            /// Instruct the model to emit less verbose final responses.
            case low
            /// Use the model's default verbosity setting.
            case medium
            /// Instruct the model to emit more verbose final responses.
            case high
        }

        /// Controls how the service truncates the input when it exceeds the model context window.
        /// See [TruncationEnum](https://www.openresponses.org/reference#truncationenum) in the Open Responses reference.
        public enum Truncation: String, Hashable, Codable, Sendable {
            /// Let the service decide how to truncate.
            case auto
            /// Disable service truncation.
            /// Context over the model's context limit will result in a 400 error.
            case disabled
        }

        enum CodingKeys: String, CodingKey {
            case toolChoice = "tool_choice"
            case allowedTools = "allowed_tools"
            case topP = "top_p"
            case presencePenalty = "presence_penalty"
            case frequencyPenalty = "frequency_penalty"
            case parallelToolCalls = "parallel_tool_calls"
            case maxToolCalls = "max_tool_calls"
            case reasoningEffort = "reasoning_effort"
            case reasoning
            case verbosity
            case maxOutputTokens = "max_output_tokens"
            case store
            case metadata
            case safetyIdentifier = "safety_identifier"
            case truncation
            case extraBody = "extra_body"
        }

        /// Creates custom generation options with the given Open Responses–specific parameters.
        ///
        /// - Parameters:
        ///   - toolChoice: Controls which tool the model should use, if any.
        ///   - allowedTools: The list of tools that are permitted for this request.
        ///   - topP: Nucleus sampling parameter, between 0 and 1.
        ///   - presencePenalty: Penalizes new tokens based on whether they appear in the text so far.
        ///   - frequencyPenalty: Penalizes new tokens based on their frequency in the text so far.
        ///   - parallelToolCalls: Whether the model may call multiple tools in parallel.
        ///   - maxToolCalls: The maximum number of tool calls the model may make while generating the response.
        ///   - reasoningEffort: Reasoning effort for reasoning-capable models.
        ///   - reasoning: Configuration options for reasoning behavior.
        ///   - verbosity: Controls the level of detail in generated text output.
        ///   - maxOutputTokens: The maximum number of tokens the model may generate for this response.
        ///   - store: Whether to store the response so it can be retrieved later.
        ///   - metadata: Key-value pairs (keys max 64 chars, values max 512 chars).
        ///   - safetyIdentifier: A stable identifier used for safety monitoring and abuse detection.
        ///   - truncation: Controls how the service truncates input when it exceeds the context window.
        ///   - extraBody: Additional parameters merged into the request body.
        public init(
            toolChoice: ToolChoice? = nil,
            allowedTools: [String]? = nil,
            topP: Double? = nil,
            presencePenalty: Double? = nil,
            frequencyPenalty: Double? = nil,
            parallelToolCalls: Bool? = nil,
            maxToolCalls: Int? = nil,
            reasoningEffort: ReasoningEffort? = nil,
            reasoning: ReasoningConfiguration? = nil,
            verbosity: Verbosity? = nil,
            maxOutputTokens: Int? = nil,
            store: Bool? = nil,
            metadata: [String: String]? = nil,
            safetyIdentifier: String? = nil,
            truncation: Truncation? = nil,
            extraBody: [String: JSONValue]? = nil
        ) {
            self.toolChoice = toolChoice
            self.allowedTools = allowedTools
            self.topP = topP
            self.presencePenalty = presencePenalty
            self.frequencyPenalty = frequencyPenalty
            self.parallelToolCalls = parallelToolCalls
            self.maxToolCalls = maxToolCalls
            self.reasoningEffort = reasoningEffort
            self.reasoning = reasoning
            self.verbosity = verbosity
            self.maxOutputTokens = maxOutputTokens
            self.store = store
            self.metadata = metadata
            self.safetyIdentifier = safetyIdentifier
            self.truncation = truncation
            self.extraBody = extraBody
        }
    }

    /// Base URL for the API endpoint.
    public let baseURL: URL

    /// Model identifier to use for generation.
    public let model: String

    private let httpClient: any HTTPClient

    /// Normalized capabilities for Open Responses-compatible APIs.
    public var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities(
            model: ModelCapabilities(
                supportsTextGeneration: true,
                supportsImageInput: true,
                supportsReasoning: true
            ),
            provider: [
                .textStreaming,
                .structuredOutputs,
                .toolCalling,
                .toolCallStreaming,
                .parallelToolCalls,
                .imageInput,
                .reasoningSummaries,
                .encryptedReasoningContinuity,
                .tokenUsage,
                .streamingTokenUsage,
                .responseContinuation,
            ]
        )
    }

    /// Creates an Open Responses language model.
    ///
    /// - Parameters:
    ///   - baseURL: Base URL for the API (e.g. `https://api.openai.com/v1/` or `https://openrouter.ai/api/v1/`). Must end with `/`.
    ///   - apiKey: API key or closure that returns it.
    ///   - model: Model identifier (e.g. `gpt-4o-mini` or provider-specific id).
    ///   - httpClient: Optional SwiftAgent HTTP client used for network requests.
    public init(
        baseURL: URL = defaultBaseURL,
        apiKey tokenProvider: @escaping @autoclosure @Sendable () -> String,
        model: String,
        httpClient: (any HTTPClient)? = nil,
    ) {
        var baseURL = baseURL
        if !baseURL.path.hasSuffix("/") {
            baseURL = baseURL.appendingPathComponent("")
        }
        self.baseURL = baseURL
        self.model = model
        self.httpClient = httpClient ?? Self.makeDefaultHTTPClient(baseURL: baseURL, tokenProvider: tokenProvider)
    }

    public func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        let tools: [OpenResponsesTool]? =
            session.tools.isEmpty ? nil : session.tools.map { convertToolToOpenResponsesFormat($0) }
        return try await respondWithOpenResponses(
            messages: session.transcript.toOpenResponsesMessages(),
            tools: tools,
            generating: type,
            options: options,
            session: session
        )
    }

    public func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        let tools: [OpenResponsesTool]? =
            session.tools.isEmpty ? nil : session.tools.map { convertToolToOpenResponsesFormat($0) }
        let stream: AsyncThrowingStream<LanguageModelSession.ResponseStream<Content>.Snapshot, any Error> = .init {
            continuation in
            let task = Task { @Sendable in
                do {
                    var messages = session.transcript.toOpenResponsesMessages()

                    while true {
                        let params = try OpenResponsesAPI.createRequestBody(
                            model: model,
                            messages: messages,
                            tools: tools,
                            generating: type,
                            options: options,
                            stream: true
                        )
                        let events = httpClient.decodedEventStream(
                            path: "responses",
                            body: params,
                            as: OpenResponsesStreamEvent.self
                        )
                        var accumulatedText = ""
                        var streamingToolCalls: [String: StreamingOpenResponsesToolCall] = [:]
                        for try await event in events {
                            switch event {
                            case .outputTextDelta(let delta):
                                accumulatedText += delta
                                var raw: GeneratedContent
                                let content: Content.PartiallyGenerated?
                                if type == String.self {
                                    raw = GeneratedContent(accumulatedText)
                                    content = (accumulatedText as! Content).asPartiallyGenerated()
                                } else {
                                    if let partial = partialStructuredGeneration(from: accumulatedText, as: type) {
                                        raw = partial.rawContent
                                        content = partial.content
                                    } else {
                                        raw = GeneratedContent(accumulatedText)
                                        content = nil
                                    }
                                }
                                if let content {
                                    continuation.yield(.init(content: content, rawContent: raw))
                                }
                            case .outputItemAdded(let item):
                                switch item.type {
                                case "function_call":
                                    if let name = item.name {
                                        streamingToolCalls[item.id] = StreamingOpenResponsesToolCall(
                                            id: item.id,
                                            callId: item.callID ?? item.id,
                                            name: name,
                                            arguments: item.arguments ?? ""
                                        )
                                    }
                                case "reasoning":
                                    let reasoning = Transcript.Reasoning(
                                        id: item.id,
                                        summary: item.summaryText,
                                        encryptedReasoning: item.encryptedContent,
                                        status: .inProgress
                                    )
                                    continuation.yield(.init(transcriptEntries: [.reasoning(reasoning)]))
                                default:
                                    break
                                }
                            case .functionCallArgumentsDelta(let itemID, let delta):
                                streamingToolCalls[itemID]?.arguments += delta
                            case .functionCallArgumentsDone(let itemID, let arguments):
                                streamingToolCalls[itemID]?.arguments = arguments
                            case .completed(let response):
                                if let usage = response?.usage?.tokenUsage {
                                    continuation.yield(.init(tokenUsage: usage))
                                }
                                if let metadata = response?.responseMetadata(
                                    providerName: "Open Responses",
                                    defaultModelID: model
                                ) {
                                    continuation.yield(.init(responseMetadata: metadata))
                                }
                            case .failed:
                                continuation.finish(throwing: OpenResponsesLanguageModelError.streamFailed)
                                return
                            case .ignored:
                                break
                            }
                        }

                        let calls = try streamingToolCalls.values
                            .sorted { $0.id < $1.id }
                            .map { try $0.transcriptToolCall() }

                        guard !calls.isEmpty else {
                            continuation.finish()
                            return
                        }

                        switch try await session.executeToolCalls(calls, recordTranscript: false) {
                        case .stop(let calls):
                            continuation.yield(.init(transcriptEntries: [.toolCalls(.init(calls: calls))]))
                            continuation.finish()
                            return

                        case .outputs(let results):
                            continuation.yield(.init(transcriptEntries: [.toolCalls(.init(calls: calls))]))
                            continuation.yield(.init(transcriptEntries: results.map { .toolOutput($0.output) }))

                            for call in calls {
                                messages.append(OpenResponsesMessage(
                                    role: .raw(rawContent: .object([
                                        "type": .string("function_call"),
                                        "id": .string(call.id),
                                        "call_id": .string(call.callId),
                                        "name": .string(call.toolName),
                                        "arguments": .string(call.arguments.jsonString),
                                    ])),
                                    content: .text("")
                                ))
                            }

                            for result in results {
                                messages.append(OpenResponsesMessage(
                                    role: .tool(id: result.call.callId),
                                    content: .text(openResponsesConvertSegmentsToToolContentString(result.output.segments))
                                ))
                            }
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return LanguageModelSession.ResponseStream(stream: stream)
    }

    public func streamEvents<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> AsyncThrowingStream<LanguageModelStreamEvent, any Error> where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable {
        let tools: [OpenResponsesTool]? =
            session.tools.isEmpty ? nil : session.tools.map { convertToolToOpenResponsesFormat($0) }

        return AsyncThrowingStream { continuation in
            let task = Task { @Sendable in
                do {
                    var messages = session.transcript.toOpenResponsesMessages()

                    while true {
                        let params = try OpenResponsesAPI.createRequestBody(
                            model: model,
                            messages: messages,
                            tools: tools,
                            generating: type,
                            options: options,
                            stream: true
                        )
                        let eventStream = try await httpClient.decodedEventStreamResponse(
                            path: "responses",
                            body: params,
                            as: OpenResponsesStreamEvent.self
                        )
                        continuation.yield(LanguageModelStreamEvent.responseMetadata(ResponseMetadata.providerHTTPMetadata(
                            requestID: eventStream.requestID,
                            headers: eventStream.headers,
                            providerName: "Open Responses",
                            modelID: model
                        )))
                        var streamingToolCalls: [String: StreamingOpenResponsesToolCall] = [:]

                        for try await event in eventStream.events {
                            switch event {
                            case .outputTextDelta(let delta):
                                continuation.yield(.textDelta(id: "open-responses-text", delta: delta))

                            case .outputItemAdded(let item):
                                switch item.type {
                                case "function_call":
                                    if let name = item.name {
                                        streamingToolCalls[item.id] = StreamingOpenResponsesToolCall(
                                            id: item.id,
                                            callId: item.callID ?? item.id,
                                            name: name,
                                            arguments: item.arguments ?? ""
                                        )
                                        continuation.yield(.toolInputStart(
                                            id: item.id,
                                            callId: item.callID ?? item.id,
                                            toolName: name
                                        ))
                                        if let arguments = item.arguments, arguments.isEmpty == false {
                                            continuation.yield(.toolInputDelta(id: item.id, delta: arguments))
                                        }
                                    }
                                case "reasoning":
                                    continuation.yield(.reasoningStart(id: item.id))
                                    for summary in item.summaryText {
                                        continuation.yield(.reasoningDelta(id: item.id, delta: summary))
                                    }
                                    if let encryptedContent = item.encryptedContent {
                                        continuation.yield(.reasoningEnd(id: item.id, encryptedReasoning: encryptedContent))
                                    }
                                default:
                                    break
                                }

                            case .functionCallArgumentsDelta(let itemID, let delta):
                                streamingToolCalls[itemID]?.arguments += delta
                                continuation.yield(.toolInputDelta(id: itemID, delta: delta))

                            case .functionCallArgumentsDone(let itemID, let arguments):
                                streamingToolCalls[itemID]?.arguments = arguments
                                continuation.yield(.toolInputEnd(
                                    id: itemID,
                                    arguments: arguments.isEmpty ? GeneratedContent(properties: [:]) : try GeneratedContent(json: arguments)
                                ))

                            case .completed(let response):
                                if let usage = response?.usage?.tokenUsage {
                                    continuation.yield(.usage(usage))
                                }
                                if let metadata = response?.responseMetadata(
                                    providerName: "Open Responses",
                                    defaultModelID: model
                                ) {
                                    continuation.yield(.responseMetadata(metadata))
                                }

                            case .failed:
                                continuation.yield(.failed(.init(code: "stream_failed", message: "Open Responses stream failed")))
                                continuation.finish()
                                return

                            case .ignored:
                                break
                            }
                        }

                        let calls = try streamingToolCalls.values
                            .sorted { $0.id < $1.id }
                            .map { try $0.transcriptToolCall() }

                        guard calls.isEmpty == false else {
                            continuation.yield(.finished(.completed))
                            continuation.finish()
                            return
                        }

                        switch try await session.executeToolCalls(calls, recordTranscript: false) {
                        case .stop:
                            continuation.yield(.finished(.toolCalls))
                            continuation.finish()
                            return

                        case .outputs(let results):
                            for result in results {
                                continuation.yield(.toolResult(result.output))
                            }

                            for call in calls {
                                messages.append(OpenResponsesMessage(
                                    role: .raw(rawContent: .object([
                                        "type": .string("function_call"),
                                        "id": .string(call.id),
                                        "call_id": .string(call.callId),
                                        "name": .string(call.toolName),
                                        "arguments": .string(call.arguments.jsonString),
                                    ])),
                                    content: .text("")
                                ))
                            }

                            for result in results {
                                messages.append(OpenResponsesMessage(
                                    role: .tool(id: result.call.callId),
                                    content: .text(openResponsesConvertSegmentsToToolContentString(result.output.segments))
                                ))
                            }
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Sends a non-streaming request to the Open Responses API and returns the parsed response.
    private func respondWithOpenResponses<Content>(
        messages: [OpenResponsesMessage],
        tools: [OpenResponsesTool]?,
        generating type: Content.Type,
        options: GenerationOptions,
        session: LanguageModelSession
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        var entries: [Transcript.Entry] = []
        var text = ""
        var lastOutput: [JSONValue]?
        var lastMetadata: ResponseMetadata?
        var lastTokenUsage: TokenUsage?
        var messages = messages
        while true {
            let params = try OpenResponsesAPI.createRequestBody(
                model: model,
                messages: messages,
                tools: tools,
                generating: type,
                options: options,
                stream: false
            )
            let httpResponse: HTTPClientDecodedResponse<OpenResponsesAPI.Response> = try await httpClient.sendResponse(
                path: "responses",
                method: .post,
                queryItems: nil,
                headers: nil,
                body: params,
                responseType: OpenResponsesAPI.Response.self
            )
            let resp = httpResponse.body

            lastMetadata = ResponseMetadata
                .providerHTTPMetadata(
                    requestID: httpResponse.requestID,
                    headers: httpResponse.headers,
                    providerName: "Open Responses"
                )
                .merging(resp.responseMetadata(providerName: "Open Responses", defaultModelID: model))
            lastTokenUsage = resp.usage?.tokenUsage
            let toolCalls = extractToolCallsFromOutput(resp.output)
            lastOutput = resp.output
            if !toolCalls.isEmpty {
                if let output = resp.output {
                    for item in output {
                        messages.append(OpenResponsesMessage(role: .raw(rawContent: item), content: .text("")))
                    }
                }
                let resolution = try await resolveToolCalls(toolCalls, session: session)
                switch resolution {
                case .stop(let calls):
                    if !calls.isEmpty {
                        entries.append(.toolCalls(Transcript.ToolCalls(calls)))
                    }
                    let empty = try emptyResponseContent(for: type)
                    return LanguageModelSession.Response(
                        content: empty.content,
                        rawContent: empty.rawContent,
                        transcriptEntries: entries,
                        tokenUsage: lastTokenUsage,
                        responseMetadata: lastMetadata
                    )
                case .invocations(let invocations):
                    if !invocations.isEmpty {
                        entries.append(.toolCalls(Transcript.ToolCalls(invocations.map { $0.call })))
                        for inv in invocations {
                            entries.append(.toolOutput(inv.output))
                            messages.append(
                                OpenResponsesMessage(
                                    role: .tool(id: inv.call.callId),
                                    content: .text(openResponsesConvertSegmentsToToolContentString(inv.output.segments))
                                )
                            )
                        }
                        continue
                    }
                }
            }

            text = resp.outputText ?? extractTextFromOutput(resp.output) ?? ""
            break
        }

        if type == String.self {
            return LanguageModelSession.Response(
                content: text as! Content,
                rawContent: GeneratedContent(text),
                transcriptEntries: entries,
                tokenUsage: lastTokenUsage,
                responseMetadata: lastMetadata
            )
        }
        if let jsonString = extractJSONFromOutput(lastOutput) {
            let generatedContent = try GeneratedContent(json: jsonString)
            let content = try type.init(generatedContent)
            return LanguageModelSession.Response(
                content: content,
                rawContent: generatedContent,
                transcriptEntries: entries,
                tokenUsage: lastTokenUsage,
                responseMetadata: lastMetadata
            )
        }
        throw OpenResponsesLanguageModelError.noResponseGenerated
    }

    /// Produces empty content and raw content for the given type (used when tool execution stops the response).
    private func emptyResponseContent<Content: Generable>(for type: Content.Type) throws -> (
        content: Content, rawContent: GeneratedContent
    ) {
        if type == String.self {
            return ("" as! Content, GeneratedContent(""))
        }
        let raw = GeneratedContent(properties: [:])
        return (try type.init(raw), raw)
    }
}

// MARK: - API Request / Response

private enum OpenResponsesAPI {
    static func createRequestBody<Content: Generable>(
        model: String,
        messages: [OpenResponsesMessage],
        tools: [OpenResponsesTool]?,
        generating type: Content.Type,
        options: GenerationOptions,
        stream: Bool
    ) throws -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(model),
            "stream": .bool(stream),
        ]
        var input: [JSONValue] = []
        for msg in messages {
            switch msg.role {
            case .user:
                let contentBlocks: [JSONValue]
                switch msg.content {
                case .text(let t):
                    contentBlocks = [.object(["type": .string("input_text"), "text": .string(t)])]
                case .blocks(let blocks):
                    contentBlocks = blocks.map { b in
                        switch b {
                        case .text(let t): return .object(["type": .string("input_text"), "text": .string(t)])
                        case .imageURL(let url):
                            return .object(["type": .string("input_image"), "image_url": .string(url)])
                        }
                    }
                }
                input.append(
                    .object([
                        "type": .string("message"),
                        "role": .string("user"),
                        "content": .array(contentBlocks),
                    ])
                )
            case .tool(let id):
                var contentBlocks: [JSONValue]
                switch msg.content {
                case .text(let t):
                    contentBlocks = [.object(["type": .string("input_text"), "text": .string(t)])]
                case .blocks(let blocks):
                    contentBlocks = blocks.map { b in
                        switch b {
                        case .text(let t): return .object(["type": .string("input_text"), "text": .string(t)])
                        case .imageURL(let url):
                            return .object(["type": .string("input_image"), "image_url": .string(url)])
                        }
                    }
                }
                let outputString: String
                if contentBlocks.count > 1 {
                    let data = try JSONEncoder().encode(JSONValue.array(contentBlocks))
                    outputString = String(data: data, encoding: .utf8) ?? "[]"
                } else if let first = contentBlocks.first {
                    let data = try JSONEncoder().encode(first)
                    outputString = String(data: data, encoding: .utf8) ?? "{}"
                } else {
                    outputString = "{}"
                }
                input.append(
                    .object([
                        "type": .string("function_call_output"),
                        "call_id": .string(id),
                        "output": .string(outputString),
                    ])
                )
            case .raw(rawContent: let raw):
                input.append(raw)
            case .system:
                switch msg.content {
                case .text(let t):
                    body["instructions"] = .string(t)
                case .blocks(let blocks):
                    let t = blocks.compactMap { if case .text(let s) = $0 { return s } else { return nil } }.joined(
                        separator: "\n"
                    )
                    if !t.isEmpty { body["instructions"] = .string(t) }
                }
            case .assistant:
                break
            }
        }
        body["input"] = .array(input)

        if let tools {
            body["tools"] = .array(tools.map { $0.jsonValue })
        }

        if type != String.self {
            let schemaValue = try type.generationSchema.toJSONValueForOpenResponsesStrictMode()
            body["text"] = .object([
                "format": .object([
                    "type": .string("json_schema"),
                    "name": .string("response_schema"),
                    "strict": .bool(true),
                    "schema": schemaValue,
                ])
            ])
        }

        if let temp = options.temperature { body["temperature"] = .double(temp) }
        if let max = options.maximumResponseTokens { body["max_output_tokens"] = .int(max) }

        if let custom = options[custom: OpenResponsesLanguageModel.self] {
            if let v = custom.toolChoice {
                body["tool_choice"] = openResponsesToolChoiceJSON(v)
            }
            if let v = custom.allowedTools { body["allowed_tools"] = .array(v.map { .string($0) }) }
            if let v = custom.topP { body["top_p"] = .double(v) }
            if let v = custom.presencePenalty { body["presence_penalty"] = .double(v) }
            if let v = custom.frequencyPenalty { body["frequency_penalty"] = .double(v) }
            if let v = custom.parallelToolCalls { body["parallel_tool_calls"] = .bool(v) }
            if let v = custom.maxToolCalls { body["max_tool_calls"] = .int(v) }
            do {
                let effort = custom.reasoning?.effort ?? custom.reasoningEffort
                let summary = custom.reasoning?.summary
                var obj: [String: JSONValue] = [:]
                if let e = effort { obj["effort"] = .string(e.rawValue) }
                if let s = summary { obj["summary"] = .string(s) }
                if !obj.isEmpty { body["reasoning"] = .object(obj) }
            }
            if let v = custom.verbosity { body["verbosity"] = .string(v.rawValue) }
            if let v = custom.maxOutputTokens { body["max_output_tokens"] = .int(v) }
            if let v = custom.store { body["store"] = .bool(v) }
            if let m = custom.metadata, !m.isEmpty {
                body["metadata"] = .object(
                    Dictionary(uniqueKeysWithValues: m.map { ($0.key, JSONValue.string($0.value)) })
                )
            }
            if let v = custom.safetyIdentifier { body["safety_identifier"] = .string(v) }
            if let v = custom.truncation { body["truncation"] = .string(v.rawValue) }
            if let extra = custom.extraBody {
                for (k, v) in extra { body[k] = v }
            }
        }
        return .object(body)
    }

    struct Response: Decodable, Sendable {
        let id: String
        let model: String?
        let output: [JSONValue]?
        let outputText: String?
        let error: OpenResponsesError?
        let usage: OpenResponsesUsage?

        private enum CodingKeys: String, CodingKey {
            case id
            case model
            case output
            case outputText = "output_text"
            case error
            case usage
        }

        func responseMetadata(providerName: String, defaultModelID: String) -> ResponseMetadata {
            ResponseMetadata(
                id: id,
                providerName: providerName,
                modelID: model ?? defaultModelID
            )
        }
    }

    struct OpenResponsesError: Decodable, Sendable {
        let message: String?
        let type: String?
        let code: String?
    }
}

private func openResponsesToolChoiceJSON(_ choice: OpenResponsesLanguageModel.CustomGenerationOptions.ToolChoice)
    -> JSONValue
{
    switch choice {
    case .none: return .string("none")
    case .auto: return .string("auto")
    case .required: return .string("required")
    case .function(name: let name):
        return .object(["type": .string("function"), "name": .string(name)])
    case .allowedTools(tools: let tools, mode: let mode):
        return .object([
            "type": .string("allowed_tools"),
            "tools": .array(tools.map { .object(["type": .string("function"), "name": .string($0)]) }),
            "mode": .string(mode.rawValue),
        ])
    }
}

// MARK: - Transcript → Open Responses

private struct OpenResponsesMessage: Sendable {
    enum Role: Sendable {
        case system
        case user
        case assistant
        case tool(id: String)
        case raw(rawContent: JSONValue)
    }
    enum Content: Sendable {
        case text(String)
        case blocks([OpenResponsesBlock])
    }
    let role: Role
    let content: Content
}

private enum OpenResponsesBlock: Sendable {
    case text(String)
    case imageURL(String)
}

extension Transcript {
    fileprivate func toOpenResponsesMessages() -> [OpenResponsesMessage] {
        var list: [OpenResponsesMessage] = []
        for item in self {
            switch item {
            case .instructions(let inst):
                list.append(
                    OpenResponsesMessage(
                        role: .system,
                        content: .blocks(openResponsesConvertSegmentsToBlocks(inst.segments))
                    )
                )
            case .prompt(let prompt):
                list.append(
                    OpenResponsesMessage(
                        role: .user,
                        content: .blocks(openResponsesConvertSegmentsToBlocks(prompt.segments))
                    )
                )
            case .response(let response):
                list.append(
                    OpenResponsesMessage(
                        role: .assistant,
                        content: .blocks(openResponsesConvertSegmentsToBlocks(response.segments))
                    )
                )
            case .toolCalls(let toolCalls):
                let rawCalls: [JSONValue] = toolCalls.map { call in
                    let argsStr =
                        (try? JSONEncoder().encode(call.arguments)).flatMap { String(data: $0, encoding: .utf8) }
                        ?? "{}"
                    return .object([
                        "id": .string(call.id),
                        "type": .string("function_call"),
                        "call_id": .string(call.callId),
                        "name": .string(call.toolName),
                        "arguments": .string(argsStr),
                    ])
                }
                list.append(
                    OpenResponsesMessage(
                        role: .raw(
                            rawContent: .object([
                                "type": .string("message"),
                                "role": .string("assistant"),
                                "content": .array(rawCalls),
                            ])
                        ),
                        content: .text("")
                    )
                )
            case .toolOutput(let out):
                list.append(
                    OpenResponsesMessage(
                        role: .tool(id: out.callId),
                        content: .text(openResponsesConvertSegmentsToToolContentString(out.segments))
                    )
                )
            case .reasoning:
                break
            }
        }
        return list
    }
}

private func openResponsesConvertSegmentsToBlocks(_ segments: [Transcript.Segment]) -> [OpenResponsesBlock] {
    segments.map { seg in
        switch seg {
        case .text(let t): return .text(t.content)
        case .structure(let s):
            switch s.content.kind {
            case .string(let t): return .text(t)
            default: return .text(s.content.jsonString)
            }
        case .image(let image):
            switch image.source {
            case .url(let url):
                return .imageURL(url.absoluteString)
            case .data(let data, let mimeType):
                return .imageURL("data:\(mimeType);base64,\(data.base64EncodedString())")
            }
        }
    }
}

private func openResponsesConvertSegmentsToToolContentString(_ segments: [Transcript.Segment]) -> String {
    segments.compactMap { seg in
        switch seg {
        case .text(let t): return t.content
        case .structure(let s):
            switch s.content.kind {
            case .string(let t): return t
            default: return s.content.jsonString
            }
        case .image:
            return nil
        }
    }.joined(separator: "\n")
}

// MARK: - Tools

private struct OpenResponsesTool: Sendable {
    let type: String = "function"
    let name: String
    let description: String
    let parameters: JSONValue?

    var jsonValue: JSONValue {
        var obj: [String: JSONValue] = [
            "type": .string(type),
            "name": .string(name),
            "description": .string(description),
        ]
        if let p = parameters { obj["parameters"] = p }
        return .object(obj)
    }
}

private func convertToolToOpenResponsesFormat(_ tool: any Tool) -> OpenResponsesTool {
    let parameters: JSONValue?
    if let resolved = tool.parameters.withResolvedRoot() {
        parameters = try? JSONValue(resolved)
    } else {
        parameters = try? JSONValue(tool.parameters)
    }
    return OpenResponsesTool(
        name: tool.name,
        description: tool.description,
        parameters: parameters
    )
}

// MARK: - Tool call extraction and resolution

private struct OpenResponsesToolCall: Sendable {
    let id: String
    let callId: String
    let name: String
    let arguments: String?
}

private func parseOpenResponsesToolCall(from obj: [String: JSONValue]) -> OpenResponsesToolCall? {
    let idOpt = obj["id"].flatMap {
        if case .string(let s) = $0 { return s } else { return nil }
    }
    let callIdOpt = (obj["call_id"] ?? obj["id"]).flatMap {
        if case .string(let s) = $0 { return s } else { return nil }
    }
    let nameOpt = obj["name"].flatMap {
        if case .string(let s) = $0 { return s } else { return nil }
    }
    guard let callId = callIdOpt, !callId.isEmpty,
        let name = nameOpt, !name.isEmpty
    else { return nil }
    let id = idOpt ?? callId
    let args: String?
    if let a = obj["arguments"] {
        switch a {
        case .string(let s): args = s
        case .object(let o):
            args = (try? JSONEncoder().encode(JSONValue.object(o))).flatMap {
                String(data: $0, encoding: .utf8)
            }
        default: args = nil
        }
    } else {
        args = nil
    }
    return OpenResponsesToolCall(id: id, callId: callId, name: name, arguments: args)
}

private func collectOpenResponsesToolCalls(from value: JSONValue, into result: inout [OpenResponsesToolCall]) {
    switch value {
    case .object(let obj):
        let typeStr: String? = obj["type"].flatMap {
            if case .string(let s) = $0 { return s } else { return nil }
        }
        if let typeStr {
            if typeStr == "function_call" || typeStr == "tool_call" || typeStr == "tool_use" {
                if let call = parseOpenResponsesToolCall(from: obj) {
                    result.append(call)
                }
            }
            if typeStr == "message",
                let content = obj["content"]
            {
                switch content {
                case .array(let arr):
                    for item in arr { collectOpenResponsesToolCalls(from: item, into: &result) }
                default:
                    collectOpenResponsesToolCalls(from: content, into: &result)
                }
            }
        }
        for (key, v) in obj {
            if key == "content", let typeStr, typeStr == "message" {
                continue
            }
            collectOpenResponsesToolCalls(from: v, into: &result)
        }
    case .array(let arr):
        for item in arr { collectOpenResponsesToolCalls(from: item, into: &result) }
    default:
        break
    }
}

private func extractToolCallsFromOutput(_ output: [JSONValue]?) -> [OpenResponsesToolCall] {
    guard let output else { return [] }
    var result: [OpenResponsesToolCall] = []
    for item in output {
        collectOpenResponsesToolCalls(from: item, into: &result)
    }
    return result
}

private func extractTextFromOutput(_ output: [JSONValue]?) -> String? {
    guard let output else { return nil }
    var parts: [String] = []
    for item in output {
        guard case .object(let obj) = item,
            obj["type"].flatMap({ if case .string(let t) = $0 { return t } else { return nil } }) == "message",
            case .array(let content)? = obj["content"]
        else { continue }
        for block in content {
            guard case .object(let b) = block,
                b["type"].flatMap({ if case .string(let t) = $0 { return t } else { return nil } }) == "output_text",
                case .string(let text)? = b["text"]
            else { continue }
            parts.append(text)
        }
    }
    return parts.isEmpty ? nil : parts.joined()
}

private func extractJSONFromOutput(_ output: [JSONValue]?) -> String? {
    guard let output else { return nil }
    for item in output {
        guard case .object(let obj) = item,
            obj["type"].flatMap({ if case .string(let t) = $0 { return t } else { return nil } }) == "message",
            case .array(let content)? = obj["content"]
        else { continue }
        for block in content {
            guard case .object(let b) = block,
                b["type"].flatMap({ if case .string(let t) = $0 { return t } else { return nil } }) == "output_text",
                case .string(let s)? = b["text"]
            else { continue }
            return s
        }
    }
    return nil
}

private struct OpenResponsesToolInvocationResult: Sendable {
    let call: Transcript.ToolCall
    let output: Transcript.ToolOutput
}

private enum OpenResponsesToolResolutionOutcome: Sendable {
    case stop(calls: [Transcript.ToolCall])
    case invocations([OpenResponsesToolInvocationResult])
}

private struct StreamingOpenResponsesToolCall: Sendable {
    var id: String
    var callId: String
    var name: String
    var arguments: String

    func transcriptToolCall() throws -> Transcript.ToolCall {
        try Transcript.ToolCall(
            id: id,
            callId: callId,
            toolName: name,
            arguments: arguments.isEmpty ? GeneratedContent(properties: [:]) : GeneratedContent(json: arguments),
            status: .completed
        )
    }
}

private func resolveToolCalls(
    _ toolCalls: [OpenResponsesToolCall],
    session: LanguageModelSession
) async throws -> OpenResponsesToolResolutionOutcome {
    if toolCalls.isEmpty { return .invocations([]) }
    var transcriptCalls: [Transcript.ToolCall] = []
    for c in toolCalls {
        let args = (c.arguments.flatMap { try? GeneratedContent(json: $0) } ?? GeneratedContent(properties: [:]))
        transcriptCalls.append(Transcript.ToolCall(
            id: c.id,
            callId: c.callId,
            toolName: c.name,
            arguments: args,
            status: .completed
        ))
    }
    guard !transcriptCalls.isEmpty else { return .invocations([]) }

    switch try await session.executeToolCalls(transcriptCalls, recordTranscript: false) {
    case .stop(let calls):
        return .stop(calls: calls)
    case .outputs(let results):
        return .invocations(results.map { OpenResponsesToolInvocationResult(call: $0.call, output: $0.output) })
    }
}

// MARK: - Streaming events

private enum OpenResponsesStreamEvent: Decodable, Sendable {
    case outputTextDelta(String)
    case outputItemAdded(OpenResponsesOutputItem)
    case functionCallArgumentsDelta(itemID: String, delta: String)
    case functionCallArgumentsDone(itemID: String, arguments: String)
    case completed(OpenResponsesCompleted?)
    case failed
    case ignored

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decodeIfPresent(String.self, forKey: .type)
        switch type {
        case "response.output_text.delta":
            self = .outputTextDelta(try c.decode(String.self, forKey: .delta))
        case "response.output_item.added", "response.output_item.done":
            self = .outputItemAdded(try c.decode(OpenResponsesOutputItem.self, forKey: .item))
        case "response.function_call_arguments.delta":
            self = .functionCallArgumentsDelta(
                itemID: try c.decode(String.self, forKey: .itemID),
                delta: try c.decode(String.self, forKey: .delta)
            )
        case "response.function_call_arguments.done":
            self = .functionCallArgumentsDone(
                itemID: try c.decode(String.self, forKey: .itemID),
                arguments: try c.decode(String.self, forKey: .arguments)
            )
        case "response.completed":
            self = .completed(try? c.decode(OpenResponsesCompleted.self, forKey: .response))
        case "response.failed":
            self = .failed
        default:
            self = .ignored
        }
    }
    private enum CodingKeys: String, CodingKey {
        case type
        case delta
        case item
        case itemID = "item_id"
        case arguments
        case response
    }
}

private struct OpenResponsesOutputItem: Decodable, Sendable {
    let id: String
    let type: String
    let name: String?
    let arguments: String?
    let callID: String?
    let encryptedContent: String?
    let summary: JSONValue?

    var summaryText: [String] {
        guard let summary else { return [] }
        switch summary {
        case .array(let values):
            return values.compactMap { value in
                if case .string(let text) = value {
                    return text
                }
                if case .object(let object) = value, case .string(let text)? = object["text"] {
                    return text
                }
                return nil
            }
        case .string(let text):
            return [text]
        default:
            return []
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case name
        case arguments
        case callID = "call_id"
        case encryptedContent = "encrypted_content"
        case summary
    }
}

private struct OpenResponsesCompleted: Decodable, Sendable {
    let id: String?
    let model: String?
    let usage: OpenResponsesUsage?

    func responseMetadata(providerName: String, defaultModelID: String) -> ResponseMetadata {
        ResponseMetadata(
            id: id,
            providerName: providerName,
            modelID: model ?? defaultModelID
        )
    }
}

private struct OpenResponsesUsage: Decodable, Sendable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let outputTokensDetails: OutputTokensDetails?

    struct OutputTokensDetails: Decodable, Sendable {
        let reasoningTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case reasoningTokens = "reasoning_tokens"
        }
    }

    var tokenUsage: TokenUsage {
        TokenUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            reasoningTokens: outputTokensDetails?.reasoningTokens
        )
    }

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case outputTokensDetails = "output_tokens_details"
    }
}

// MARK: - Errors

/// Errors produced by ``OpenResponsesLanguageModel``.
enum OpenResponsesLanguageModelError: LocalizedError, Sendable {
    /// The API returned no parseable text or structured output.
    case noResponseGenerated
    /// The stream reported a failure event.
    case streamFailed

    var errorDescription: String? {
        switch self {
        case .noResponseGenerated: return "No response was generated by the model"
        case .streamFailed: return "The stream reported a failure event"
        }
    }
}

private extension OpenResponsesLanguageModel {
    static func makeDefaultHTTPClient(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () -> String
    ) -> any HTTPClient {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let configuration = HTTPClientConfiguration(
            baseURL: baseURL,
            jsonEncoder: encoder,
            interceptors: .init(
                prepareRequest: { request in
                    request.setValue("Bearer \(tokenProvider())", forHTTPHeaderField: "Authorization")
                }
            )
        )
        return URLSessionHTTPClient(configuration: configuration)
    }
}

// MARK: - Schema for structured output

private extension GenerationSchema {
    func toJSONValueForOpenResponsesStrictMode() throws -> JSONValue {
        let resolved = withResolvedRoot() ?? self
        let encoder = JSONEncoder()
        encoder.userInfo[GenerationSchema.omitAdditionalPropertiesKey] = false
        let data = try encoder.encode(resolved)
        let jsonSchema = try JSONDecoder().decode(JSONSchema.self, from: data)
        var value = try JSONValue(jsonSchema)
        if case .object(var obj) = value {
            obj["additionalProperties"] = .bool(false)
            if case .object(let props)? = obj["properties"], !props.isEmpty {
                obj["required"] = .array(Array(props.keys).sorted().map { .string($0) })
            }
            value = .object(obj)
        }
        return value
    }
}
