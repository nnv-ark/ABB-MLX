import Foundation
import Hummingbird
import ABBMLXCore

/// OpenAI-compatible HTTP server for ABB-MLX. Binds to 127.0.0.1 by default.
public actor ABBMLXServer {
    public struct Config: Sendable {
        public var host: String
        public var port: Int
        public init(host: String = "127.0.0.1", port: Int = 8080) {
            self.host = host; self.port = port
        }
    }

    private let engine = MLXEngine()
    private let embedEngine = EmbeddingEngine()
    private var task: Task<Void, Error>?
    public private(set) var isRunning = false

    public init() {}

    public func start(config: Config = .init()) async throws {
        guard !isRunning else { return }
        let router = Router()
        registerRoutes(on: router)
        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname(config.host, port: config.port),
                serverName: "ABB-MLX"
            )
        )
        let runTask = Task { try await app.runService() }
        task = runTask
        isRunning = true
    }

    public func stop() async {
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func registerRoutes(on router: Router<BasicRequestContext>) {
        let engine = self.engine
        let embedEngine = self.embedEngine

        router.get("/health") { _, _ -> Response in
            Self.jsonResponse(["status": "ok", "service": "ABB-MLX"])
        }

        router.get("/v1/models") { _, _ -> Response in
            let installed = ModelRegistry.scan()
                .filter { !ModelRegistry.isVisionModel($0.id) }
            let now = Int(Date().timeIntervalSince1970)
            let resp = ModelsResponse(
                object: "list",
                data: installed.map {
                    ModelInfo(id: $0.id, object: "model",
                              created: now, owned_by: "mlx-community")
                }
            )
            return Self.jsonResponse(resp)
        }

        router.post("/v1/chat/completions") { req, ctx -> Response in
            let body = try await req.decode(as: ChatRequest.self, context: ctx)
            if body.stream == true {
                return Self.streamChat(body: body, engine: engine)
            } else {
                let resp = try await Self.syncChat(body: body, engine: engine)
                return Self.jsonResponse(resp)
            }
        }

        router.post("/v1/embeddings") { req, ctx -> Response in
            let body = try await req.decode(as: EmbeddingRequest.self, context: ctx)
            let texts = body.input.asArray
            let vectors = try await embedEngine.embed(modelId: body.model, texts: texts)
            let items = vectors.enumerated().map {
                EmbeddingItem(object: "embedding", index: $0.offset, embedding: $0.element)
            }
            let resp = EmbeddingResponse(
                object: "list", model: body.model, data: items, usage: nil
            )
            return Self.jsonResponse(resp)
        }
    }

    private static func jsonResponse<T: Encodable>(_ value: T) -> Response {
        let data = (try? JSONEncoder().encode(value)) ?? Data()
        var buf = ByteBuffer()
        buf.writeBytes(data)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: buf)
        )
    }

    // MARK: - Helpers

    private static func parameters(from body: ChatRequest) -> MLXEngine.GenerationParameters {
        MLXEngine.GenerationParameters(
            temperature: body.temperature ?? 0.7,
            topP: body.top_p ?? 1.0,
            maxTokens: body.max_tokens ?? 1024,
            seed: body.seed
        )
    }

    private static func payload(_ tc: MLXEngine.ToolCallData, index: Int) -> ToolCallPayload {
        ToolCallPayload(
            id: "call_" + String(UUID().uuidString.prefix(8)),
            index: index,
            function: FunctionCall(name: tc.name, arguments: tc.argumentsJSON)
        )
    }

    // MARK: - Chat (sync)

    private static func syncChat(body: ChatRequest, engine: MLXEngine) async throws -> ChatResponse {
        var full = ""
        var toolCalls: [ToolCallPayload] = []
        var usage: ChatUsage?
        var reason = "stop"

        let stream = await engine.generateEvents(
            modelId: body.model, messages: body.messages, tools: body.tools,
            parameters: parameters(from: body), stop: body.stop ?? []
        )
        for try await event in stream {
            switch event {
            case .text(let t): full += t
            case .toolCall(let tc): toolCalls.append(payload(tc, index: toolCalls.count))
            case .finished(let u, let r):
                reason = r
                if let u {
                    usage = ChatUsage(prompt_tokens: u.promptTokens,
                                      completion_tokens: u.completionTokens,
                                      total_tokens: u.promptTokens + u.completionTokens)
                }
            }
        }

        let id = "chatcmpl-" + UUID().uuidString
        let now = Int(Date().timeIntervalSince1970)
        let message = ChatChoiceMessage(
            role: .assistant,
            content: toolCalls.isEmpty ? full : (full.isEmpty ? nil : full),
            tool_calls: toolCalls.isEmpty ? nil : toolCalls
        )
        let choice = ChatChoice(index: 0, message: message, delta: nil, finish_reason: reason)
        return ChatResponse(id: id, object: "chat.completion", created: now,
                            model: body.model, choices: [choice], usage: usage)
    }

    // MARK: - Chat (streaming SSE)

    private static func streamChat(body: ChatRequest, engine: MLXEngine) -> Response {
        let id = "chatcmpl-" + UUID().uuidString
        let now = Int(Date().timeIntervalSince1970)
        let model = body.model
        let params = parameters(from: body)
        let includeUsage = body.stream_options?.include_usage ?? false

        let responseBody = ResponseBody { (writer: inout any ResponseBodyWriter) in
            let encoder = JSONEncoder()
            // Encodes one SSE frame without touching `writer` (so it isn't captured).
            func frame(_ value: ChatResponse) throws -> ByteBuffer {
                var buf = ByteBuffer()
                buf.writeString("data: ")
                buf.writeBytes(try encoder.encode(value))
                buf.writeString("\n\n")
                return buf
            }
            func chunk(delta: ChatChoiceMessage?, finish: String?) -> ChatResponse {
                ChatResponse(
                    id: id, object: "chat.completion.chunk", created: now, model: model,
                    choices: [ChatChoice(index: 0, message: nil, delta: delta,
                                         finish_reason: finish)],
                    usage: nil)
            }

            do {
                let stream = await engine.generateEvents(
                    modelId: model, messages: body.messages, tools: body.tools,
                    parameters: params, stop: body.stop ?? []
                )
                var reason = "stop"
                var usage: ChatUsage?
                var toolIndex = 0

                for try await event in stream {
                    switch event {
                    case .text(let t):
                        guard !t.isEmpty else { continue }
                        try await writer.write(frame(chunk(
                            delta: ChatChoiceMessage(role: .assistant, content: t),
                            finish: nil)))
                    case .toolCall(let tc):
                        let call = payload(tc, index: toolIndex); toolIndex += 1
                        try await writer.write(frame(chunk(
                            delta: ChatChoiceMessage(role: .assistant, content: nil,
                                                     tool_calls: [call]),
                            finish: nil)))
                    case .finished(let u, let r):
                        reason = r
                        if let u {
                            usage = ChatUsage(prompt_tokens: u.promptTokens,
                                              completion_tokens: u.completionTokens,
                                              total_tokens: u.promptTokens + u.completionTokens)
                        }
                    }
                }

                try await writer.write(frame(chunk(delta: nil, finish: reason)))
                if includeUsage, let usage {
                    try await writer.write(frame(ChatResponse(
                        id: id, object: "chat.completion.chunk", created: now, model: model,
                        choices: [], usage: usage)))
                }
                try await writer.write(ByteBuffer(string: "data: [DONE]\n\n"))
                try await writer.finish(nil)
            } catch {
                try? await writer.finish(nil)
            }
        }

        return Response(
            status: .ok,
            headers: [
                .contentType: "text/event-stream",
                .cacheControl: "no-cache",
                .connection: "keep-alive"
            ],
            body: responseBody
        )
    }
}
