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

    // MARK: - Chat (sync)

    private static func syncChat(body: ChatRequest, engine: MLXEngine) async throws -> ChatResponse {
        let params = MLXEngine.GenerationParameters(
            temperature: body.temperature ?? 0.7,
            topP: body.top_p ?? 1.0,
            maxTokens: body.max_tokens ?? 1024,
            seed: body.seed
        )
        var full = ""
        let stream = await engine.generate(
            modelId: body.model, messages: body.messages, parameters: params
        )
        for try await chunk in stream { full += chunk }
        let id = "chatcmpl-" + UUID().uuidString
        let now = Int(Date().timeIntervalSince1970)
        let choice = ChatChoice(
            index: 0,
            message: ChatChoiceMessage(role: .assistant, content: full),
            delta: nil,
            finish_reason: "stop"
        )
        return ChatResponse(id: id, object: "chat.completion", created: now,
                            model: body.model, choices: [choice], usage: nil)
    }

    // MARK: - Chat (streaming SSE)

    private static func streamChat(body: ChatRequest, engine: MLXEngine) -> Response {
        let id = "chatcmpl-" + UUID().uuidString
        let now = Int(Date().timeIntervalSince1970)
        let model = body.model

        let params = MLXEngine.GenerationParameters(
            temperature: body.temperature ?? 0.7,
            topP: body.top_p ?? 1.0,
            maxTokens: body.max_tokens ?? 1024,
            seed: body.seed
        )

        let responseBody = ResponseBody { (writer: inout any ResponseBodyWriter) in
            do {
                let stream = await engine.generate(
                    modelId: model, messages: body.messages, parameters: params
                )
                let encoder = JSONEncoder()
                var previous = ""
                for try await chunk in stream {
                    let delta: String
                    if chunk.hasPrefix(previous) {
                        delta = String(chunk.dropFirst(previous.count))
                    } else {
                        delta = chunk
                    }
                    previous = chunk
                    guard !delta.isEmpty else { continue }
                    let payload = ChatResponse(
                        id: id, object: "chat.completion.chunk", created: now, model: model,
                        choices: [ChatChoice(
                            index: 0, message: nil,
                            delta: ChatChoiceMessage(role: .assistant, content: delta),
                            finish_reason: nil)],
                        usage: nil)
                    let data = try encoder.encode(payload)
                    try await writer.write(ByteBuffer(string: "data: "))
                    try await writer.write(ByteBuffer(bytes: data))
                    try await writer.write(ByteBuffer(string: "\n\n"))
                }
                let final = ChatResponse(
                    id: id, object: "chat.completion.chunk", created: now, model: model,
                    choices: [ChatChoice(index: 0, message: nil, delta: nil,
                                          finish_reason: "stop")],
                    usage: nil)
                let data = try encoder.encode(final)
                try await writer.write(ByteBuffer(string: "data: "))
                try await writer.write(ByteBuffer(bytes: data))
                try await writer.write(ByteBuffer(string: "\n\ndata: [DONE]\n\n"))
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
