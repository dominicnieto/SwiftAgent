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

        /// Provider-specific fields to include in the response.
        public var include: [String]

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
            case include
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
            include: [String] = [],
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
            self.include = include
            self.metadata = metadata
            self.safetyIdentifier = safetyIdentifier
            self.truncation = truncation
            self.extraBody = extraBody
        }
    }

    /// Provider-defined tools for Responses-compatible endpoints.
    public enum ProviderTool {
        /// Creates a raw provider-defined Responses tool.
        public static func raw(
            name: String,
            tool: JSONValue,
            description: String? = nil
        ) -> ToolDefinition {
            ToolDefinition.providerDefined(
                name: name,
                providerMetadata: .object(["openresponses": tool]),
                description: description
            )
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

    public func respond(to request: ModelRequest) async throws -> ModelResponse {
        let messages = openResponsesMessages(from: request)
        let tools = request.tools.map(openResponsesToolDefinition)
        let body = try OpenResponsesAPI.createRequestBody(
            model: model,
            messages: messages,
            tools: tools.isEmpty ? nil : tools,
            structuredOutput: request.structuredOutput,
            toolChoice: request.toolChoice,
            options: request.generationOptions,
            stream: false
        )

        let httpResponse: HTTPClientDecodedResponse<OpenResponsesAPI.Response> = try await httpClient.sendResponse(
            path: "responses",
            method: .post,
            queryItems: nil,
            headers: nil,
            body: body,
            responseType: OpenResponsesAPI.Response.self
        )
        let response = httpResponse.body
        let metadata = ResponseMetadata
            .providerHTTPMetadata(
                requestID: httpResponse.requestID,
                headers: httpResponse.headers,
                providerName: "Open Responses"
            )
            .merging(response.responseMetadata(providerName: "Open Responses", defaultModelID: model))
            .merging(openResponsesOutputMetadata(output: response.output, responseID: response.id))
        let toolCalls = try modelToolCalls(
            from: extractToolCallsFromOutput(response.output),
            providerDefinedToolNames: providerDefinedToolNames(in: request)
        )
        let reasoning = reasoningEntries(from: response.output)
        let content = try openResponsesContent(from: response.output, outputText: response.outputText, structuredOutput: request.structuredOutput)
        return ModelResponse(
            content: content,
            toolCalls: toolCalls,
            reasoning: reasoning,
            finishReason: toolCalls.isEmpty ? .completed : .toolCalls,
            tokenUsage: response.usage?.tokenUsage,
            responseMetadata: metadata,
            rawProviderOutput: response.output.map(JSONValue.array)
        )
    }

    public func streamResponse(to request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let messages = openResponsesMessages(from: request)
                    let tools = request.tools.map(openResponsesToolDefinition)
                    let body = try OpenResponsesAPI.createRequestBody(
                        model: model,
                        messages: messages,
                        tools: tools.isEmpty ? nil : tools,
                        structuredOutput: request.structuredOutput,
                        toolChoice: request.toolChoice,
                        options: request.generationOptions,
                        stream: true
                    )
                    let eventStream = try await httpClient.decodedEventStreamResponse(
                        path: "responses",
                        body: body,
                        as: OpenResponsesStreamEvent.self
                    )
                    continuation.yield(.started(ResponseMetadata.providerHTTPMetadata(
                        requestID: eventStream.requestID,
                        headers: eventStream.headers,
                        providerName: "Open Responses",
                        modelID: model
                    )))

                    var accumulatedText = ""
                    var streamingToolCalls: [String: StreamingOpenResponsesToolCall] = [:]
                    let providerDefinedToolNames = providerDefinedToolNames(in: request)

                    for try await event in eventStream.events {
                        switch event {
                        case .outputTextDelta(let delta):
                            accumulatedText += delta
                            if request.structuredOutput != nil, let content = try? GeneratedContent(json: accumulatedText) {
                                continuation.yield(.structuredDelta(id: "open-responses-structured", delta: content))
                            } else {
                                continuation.yield(.textDelta(id: "open-responses-text", delta: delta))
                            }

                        case .outputItemAdded(let item):
                            switch item.type {
                            case "function_call":
                                if let name = item.name {
                                    streamingToolCalls[item.id] = StreamingOpenResponsesToolCall(
                                        id: item.id,
                                        callId: item.callID ?? item.id,
                                        name: name,
                                        arguments: item.arguments ?? "",
                                        kind: providerDefinedToolNames.contains(name) ? .providerDefined : .local
                                    )
                                    continuation.yield(.toolInputStarted(.init(
                                        id: item.id,
                                        callId: item.callID ?? item.id,
                                        toolName: name,
                                        kind: providerDefinedToolNames.contains(name) ? .providerDefined : .local,
                                        providerMetadata: openResponsesProviderMetadata(["item": item.rawItem])
                                    )))
                                    if let arguments = item.arguments, arguments.isEmpty == false {
                                        continuation.yield(.toolInputDelta(id: item.id, delta: arguments))
                                    }
                                }
                            case "reasoning":
                                continuation.yield(.reasoningStarted(id: item.id, metadata: nil))
                                for summary in item.summaryText {
                                    continuation.yield(.reasoningDelta(id: item.id, delta: summary))
                                }
                                continuation.yield(.reasoningCompleted(Transcript.Reasoning(
                                    id: item.id,
                                    summary: item.summaryText,
                                    encryptedReasoning: item.encryptedContent,
                                    status: .completed,
                                    providerMetadata: openResponsesProviderMetadata([
                                        "item_id": .string(item.id),
                                        "encrypted_content": item.encryptedContent.map(JSONValue.string) ?? .null,
                                    ])
                                )))
                            default:
                                break
                            }

                        case .functionCallArgumentsDelta(let itemID, let delta):
                            streamingToolCalls[itemID]?.arguments += delta
                            continuation.yield(.toolInputDelta(id: itemID, delta: delta))

                        case .functionCallArgumentsDone(let itemID, let arguments):
                            streamingToolCalls[itemID]?.arguments = arguments
                            continuation.yield(.toolInputCompleted(id: itemID))

                        case .completed(let response):
                            if let usage = response?.usage?.tokenUsage {
                                continuation.yield(.usage(usage))
                            }
                            if let metadata = response?.responseMetadata(
                                providerName: "Open Responses",
                                defaultModelID: model
                            ) {
                                continuation.yield(.metadata(metadata))
                            }

                        case .failed:
                            continuation.yield(.failed(.init(
                                code: "stream_failed",
                                message: "Open Responses stream failed"
                            )))
                            continuation.finish()
                            return

                        case .ignored:
                            break
                        }
                    }

                    let calls = try streamingToolCalls.values
                        .sorted { $0.id < $1.id }
                        .map { ModelToolCall(call: try $0.transcriptToolCall(), kind: $0.kind) }
                    if calls.isEmpty == false {
                        continuation.yield(.toolCallsCompleted(calls))
                    }
                    continuation.yield(.completed(.init(
                        finishReason: calls.isEmpty ? .completed : .toolCalls
                    )))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
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
    static func createRequestBody(
        model: String,
        messages: [OpenResponsesMessage],
        tools: [OpenResponsesTool]?,
        structuredOutput: StructuredOutputRequest?,
        toolChoice: ToolChoice?,
        options: GenerationOptions,
        stream: Bool
    ) throws -> JSONValue {
        var body = try createBaseRequestBody(
            model: model,
            messages: messages,
            tools: tools,
            options: options,
            stream: stream
        )

        if let structuredOutput {
            let schemaValue = try schemaValue(from: structuredOutput.format)
            body["text"] = .object([
                "format": .object([
                    "type": .string("json_schema"),
                    "name": .string("response_schema"),
                    "strict": .bool(true),
                    "schema": schemaValue,
                ])
            ])
        }
        if let toolChoice {
            body["tool_choice"] = openResponsesToolChoiceJSON(toolChoice)
        }

        return .object(body)
    }

    static func createRequestBody<Content: Generable>(
        model: String,
        messages: [OpenResponsesMessage],
        tools: [OpenResponsesTool]?,
        generating type: Content.Type,
        options: GenerationOptions,
        stream: Bool
    ) throws -> JSONValue {
        var body = try createBaseRequestBody(
            model: model,
            messages: messages,
            tools: tools,
            options: options,
            stream: stream
        )

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

        return .object(body)
    }

    private static func createBaseRequestBody(
        model: String,
        messages: [OpenResponsesMessage],
        tools: [OpenResponsesTool]?,
        options: GenerationOptions,
        stream: Bool
    ) throws -> [String: JSONValue] {
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
            if custom.include.isEmpty == false {
                body["include"] = .array(custom.include.map(JSONValue.string))
            }
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
        return body
    }

    private static func schemaValue(from format: ResponseFormat) throws -> JSONValue {
        switch format {
        case .text:
            return .object([:])
        case .jsonSchema(_, let schema, _), .generatedContent(_, let schema, _):
            return try schema.toJSONValueForOpenResponsesStrictMode()
        }
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

private func openResponsesToolChoiceJSON(_ choice: ToolChoice) -> JSONValue {
    switch choice {
    case .automatic:
        .string("auto")
    case .none:
        .string("none")
    case .required:
        .string("required")
    case .named(let name):
        .object(["type": .string("function"), "name": .string(name)])
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

private func openResponsesMessages(from request: ModelRequest) -> [OpenResponsesMessage] {
    var list: [OpenResponsesMessage] = []
    if let instructions = request.instructions {
        list.append(OpenResponsesMessage(role: .system, content: .text(instructions.description)))
    }

    for message in request.messages {
        switch message.role {
        case .system:
            list.append(OpenResponsesMessage(
                role: .system,
                content: .blocks(openResponsesConvertSegmentsToBlocks(message.segments))
            ))
        case .user:
            list.append(OpenResponsesMessage(
                role: .user,
                content: .blocks(openResponsesConvertSegmentsToBlocks(message.segments))
            ))
        case .assistant:
            let rawToolCallItems = openResponsesToolCallItems(from: message.providerMetadata)
            if rawToolCallItems.isEmpty == false {
                list.append(contentsOf: rawToolCallItems.map {
                    OpenResponsesMessage(role: .raw(rawContent: $0), content: .text(""))
                })
                continue
            }
            list.append(OpenResponsesMessage(
                role: .assistant,
                content: .blocks(openResponsesConvertSegmentsToBlocks(message.segments))
            ))
        case .tool:
            guard case let .string(callID)? = message.providerMetadata["call_id"] else {
                continue
            }
            list.append(OpenResponsesMessage(
                role: .tool(id: callID),
                content: .blocks(openResponsesConvertSegmentsToBlocks(message.segments))
            ))
        case let .providerDefined(kind):
            if kind == "reasoning",
               let reasoningItem = openResponsesReasoningItem(from: message.providerMetadata)
            {
                list.append(OpenResponsesMessage(role: .raw(rawContent: reasoningItem), content: .text("")))
            }
        }
    }

    return list
}

private func openResponsesToolCallItems(from metadata: [String: JSONValue]) -> [JSONValue] {
    guard case let .array(calls)? = metadata["tool_calls"] else { return [] }
    return calls.compactMap { value -> JSONValue? in
        guard case let .object(call) = value,
            let callID = call.jsonString(forKey: "call_id") ?? call.jsonString(forKey: "id"),
            let toolName = call.jsonString(forKey: "tool_name")
        else { return nil }
        return .object([
            "type": .string("function_call"),
            "call_id": .string(callID),
            "name": .string(toolName),
            "arguments": .string(call.jsonString(forKey: "arguments") ?? "{}"),
            "status": .string("completed"),
        ])
    }
}

private func openResponsesReasoningItem(from metadata: [String: JSONValue]) -> JSONValue? {
    guard case let .object(openAI)? = metadata["openai"],
        let itemID = openAI.jsonString(forKey: "item_id")
    else { return nil }

    var item: [String: JSONValue] = [
        "type": .string("reasoning"),
        "id": .string(itemID),
    ]
    if let encryptedContent = openAI["encrypted_content"], encryptedContent != .null {
        item["encrypted_content"] = encryptedContent
    }
    return .object(item)
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
    let type: String
    let name: String
    let description: String
    let parameters: JSONValue?
    let rawValue: JSONValue?

    init(name: String, description: String, parameters: JSONValue?) {
        type = "function"
        self.name = name
        self.description = description
        self.parameters = parameters
        rawValue = nil
    }

    init(rawValue: JSONValue) {
        type = ""
        name = ""
        description = ""
        parameters = nil
        self.rawValue = rawValue
    }

    var jsonValue: JSONValue {
        if let rawValue {
            return rawValue
        }
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

private func openResponsesToolDefinition(_ definition: ToolDefinition) -> OpenResponsesTool {
    if definition.kind == .providerDefined,
       let rawTool = providerDefinedToolJSON(from: definition.providerMetadata, providerKey: "openresponses")
    {
        return OpenResponsesTool(rawValue: rawTool)
    }
    let parameters = definition.schema.withResolvedRoot()
        .flatMap { try? JSONValue($0) }
        ?? (try? JSONValue(definition.schema))
    return OpenResponsesTool(
        name: definition.name,
        description: definition.description ?? "",
        parameters: parameters
    )
}

private func openResponsesContent(
    from output: [JSONValue]?,
    outputText: String?,
    structuredOutput: StructuredOutputRequest?
) throws -> GeneratedContent? {
    if structuredOutput != nil {
        if let jsonString = extractJSONFromOutput(output) ?? outputText {
            return try GeneratedContent(json: jsonString)
        }
        return nil
    }
    return GeneratedContent(outputText ?? extractTextFromOutput(output) ?? "")
}

private func reasoningEntries(from output: [JSONValue]?) -> [Transcript.Reasoning] {
    guard let output else { return [] }
    return output.compactMap { item in
        guard case let .object(object) = item,
            object.jsonString(forKey: "type") == "reasoning",
            let id = object.jsonString(forKey: "id")
        else { return nil }
        return Transcript.Reasoning(
            id: id,
            summary: openResponsesReasoningSummary(from: object["summary"]),
            encryptedReasoning: object.jsonString(forKey: "encrypted_content"),
            status: .completed,
            providerMetadata: openResponsesProviderMetadata([
                "item_id": .string(id),
                "encrypted_content": object["encrypted_content"] ?? .null,
            ])
        )
    }
}

private func openResponsesReasoningSummary(from value: JSONValue?) -> [String] {
    guard let value else { return [] }
    switch value {
    case .string(let text):
        return [text]
    case .array(let values):
        return values.compactMap { value in
            if case let .string(text) = value {
                return text
            }
            if case let .object(object) = value,
                case let .string(text)? = object["text"]
            {
                return text
            }
            return nil
        }
    default:
        return []
    }
}

private func modelToolCalls(
    from toolCalls: [OpenResponsesToolCall],
    providerDefinedToolNames: Set<String> = []
) throws -> [ModelToolCall] {
    try toolCalls.map { call in
        let arguments = try call.arguments.map(GeneratedContent.init(json:)) ?? GeneratedContent(properties: [:])
        let metadata = openResponsesProviderMetadata([
            "item_id": .string(call.id),
        ])
        return ModelToolCall(
            call: Transcript.ToolCall(
                id: call.id,
                callId: call.callId,
                toolName: call.name,
                arguments: arguments,
                status: .completed,
                providerMetadata: metadata
            ),
            kind: providerDefinedToolNames.contains(call.name) ? .providerDefined : .local,
            providerMetadata: metadata
        )
    }
}

private func providerDefinedToolNames(in request: ModelRequest) -> Set<String> {
    Set(request.tools.filter { $0.kind == .providerDefined }.map(\.name))
}

private func openResponsesProviderMetadata(_ value: [String: JSONValue]) -> [String: JSONValue] {
    ["openai": .object(value)]
}

private func openResponsesOutputMetadata(output: [JSONValue]?, responseID: String?) -> ResponseMetadata {
    var metadata: [String: JSONValue] = [:]
    if let responseID {
        metadata["response_id"] = .string(responseID)
    }
    if let output, output.isEmpty == false {
        metadata["output"] = .array(output)
    }
    return ResponseMetadata(providerMetadata: openResponsesProviderMetadata(metadata))
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

private struct StreamingOpenResponsesToolCall: Sendable {
    var id: String
    var callId: String
    var name: String
    var arguments: String
    var kind: ToolDefinitionKind = .local

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
    let rawItem: JSONValue

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

    init(from decoder: Decoder) throws {
        rawItem = try JSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        arguments = try container.decodeIfPresent(String.self, forKey: .arguments)
        callID = try container.decodeIfPresent(String.self, forKey: .callID)
        encryptedContent = try container.decodeIfPresent(String.self, forKey: .encryptedContent)
        summary = try container.decodeIfPresent(JSONValue.self, forKey: .summary)
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

private extension [String: JSONValue] {
    func jsonString(forKey key: String) -> String? {
        guard case .string(let value)? = self[key] else { return nil }
        return value
    }
}

private func providerDefinedToolJSON(from metadata: JSONValue?, providerKey: String) -> JSONValue? {
    guard let metadata else { return nil }
    guard case let .object(object) = metadata else { return metadata }
    return object[providerKey] ?? object["tool"] ?? metadata
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
