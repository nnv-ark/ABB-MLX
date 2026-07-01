import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// Token-streaming LLM engine wrapping `mlx-swift-examples` MLXLLM.
///
/// One engine instance holds at most one loaded text model. Switching
/// models unloads the previous one (MLX is memory-hungry, you really do
/// only want one resident at a time on consumer Macs).
public actor MLXEngine {
    public struct LoadProgress: Sendable { public let fraction: Double }
    public struct GenerationParameters: Sendable {
        public var temperature: Float
        public var topP: Float
        public var maxTokens: Int
        public var seed: UInt64?
        public init(temperature: Float = 0.7, topP: Float = 1.0,
                    maxTokens: Int = 1024, seed: UInt64? = nil) {
            self.temperature = temperature; self.topP = topP
            self.maxTokens = maxTokens; self.seed = seed
        }
    }

    /// A tool call surfaced by the model, decoupled from MLX types so the
    /// server layer never has to import MLXLMCommon.
    public struct ToolCallData: Sendable {
        public let name: String
        /// JSON-encoded arguments string (OpenAI convention).
        public let argumentsJSON: String
    }

    public struct Usage: Sendable {
        public let promptTokens: Int
        public let completionTokens: Int
    }

    /// Streaming output of `generateEvents`.
    public enum Event: Sendable {
        case text(String)
        case toolCall(ToolCallData)
        /// Terminal event. `usage` is nil when generation was cut by a stop
        /// sequence (token counts aren't finalized in that path).
        case finished(usage: Usage?, reason: String)  // "stop" | "length" | "tool_calls"
    }

    public private(set) var currentModelId: String?
    private var container: ModelContainer?

    /// Metal buffer cache limit. The old hard-coded 20 MB minimized idle
    /// memory but forced constant reallocation during generation; expose it so
    /// callers can trade memory for throughput. Default keeps prior behavior.
    private var gpuCacheLimit = 20 * 1024 * 1024
    public func setGPUCacheLimit(_ bytes: Int) { gpuCacheLimit = bytes }

    public init() {}

    /// Load (or switch to) a model by Hugging Face id, e.g.
    /// "mlx-community/Qwen2.5-7B-Instruct-4bit". Idempotent — re-loading
    /// the same id is a no-op.
    public func load(modelId: String,
                     onProgress: @escaping @Sendable (LoadProgress) -> Void = { _ in }) async throws {
        if currentModelId == modelId, container != nil { return }
        // Free previous container before loading the next one.
        container = nil
        MLX.GPU.set(cacheLimit: gpuCacheLimit)

        // A modelId that names an existing local directory loads directly from
        // disk, bypassing Hub entirely — useful for models placed outside the
        // Hub cache convention (e.g. a flat folder, not org--repo/snapshots/...).
        var isDirectory: ObjCBool = false
        let configuration: ModelConfiguration
        if FileManager.default.fileExists(atPath: modelId, isDirectory: &isDirectory), isDirectory.boolValue {
            configuration = ModelConfiguration(directory: URL(fileURLWithPath: modelId))
        } else {
            configuration = ModelConfiguration(id: modelId)
        }
        let loaded = try await LLMModelFactory.shared.loadContainer(
            configuration: configuration
        ) { progress in
            onProgress(LoadProgress(fraction: progress.fractionCompleted))
        }
        container = loaded
        currentModelId = modelId
    }

    public func unload() {
        container = nil
        currentModelId = nil
    }

    /// Streams generation events (text chunks, tool calls, and a terminal
    /// summary). Cancelling the surrounding Task stops generation at the next
    /// token boundary. Tools are passed as OpenAI function schemas and rendered
    /// into the prompt by the model's chat template.
    public func generateEvents(
        modelId: String,
        messages: [ChatMessage],
        tools: [JSONValue]?,
        parameters: GenerationParameters,
        stop: [String]
    ) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.load(modelId: modelId)
                    guard let container = self.container else {
                        throw EngineError.notLoaded
                    }
                    if let seed = parameters.seed { MLXRandom.seed(seed) }

                    let maxTokens = parameters.maxTokens
                    let gp = GenerateParameters(
                        maxTokens: maxTokens,
                        temperature: parameters.temperature, topP: parameters.topP)

                    let stops = stop.filter { !$0.isEmpty }
                    let holdBack = stops.map(\.count).max() ?? 0

                    try await container.perform { ctx in
                        // Build the untyped chat-template inputs *inside* the
                        // model actor so no non-Sendable value crosses a boundary.
                        let msgDicts: [[String: String]] = messages.map {
                            ["role": $0.role.rawValue, "content": $0.content ?? ""]
                        }
                        let toolSpecs: [[String: Any]]? = tools?.compactMap {
                            if case .object(let o) = $0 { return o.mapValues(\.anyValue) }
                            return nil
                        }

                        let userInput = UserInput(messages: msgDicts, tools: toolSpecs)
                        let lm = try await ctx.processor.prepare(input: userInput)
                        let stream = try MLXLMCommon.generate(
                            input: lm, parameters: gp, context: ctx)

                        var full = ""
                        var emitted = 0
                        var stopped = false
                        var sawToolCall = false
                        var completionTokens = 0
                        var promptTokens = 0
                        var reason = "stop"

                        genLoop: for await g in stream {
                            if Task.isCancelled { break }
                            switch g {
                            case .chunk(let s):
                                full += s
                                if !stops.isEmpty,
                                   let cut = Self.earliestStop(in: full, stops: stops) {
                                    if cut > emitted {
                                        continuation.yield(.text(Self.slice(full, emitted, cut)))
                                        emitted = cut
                                    }
                                    stopped = true; reason = "stop"
                                    break genLoop
                                }
                                let safeEnd = max(emitted, full.count - holdBack)
                                if safeEnd > emitted {
                                    continuation.yield(.text(Self.slice(full, emitted, safeEnd)))
                                    emitted = safeEnd
                                }
                            case .toolCall(let tc):
                                sawToolCall = true
                                let argsData =
                                    (try? JSONEncoder().encode(tc.function.arguments))
                                    ?? Data("{}".utf8)
                                let args = String(data: argsData, encoding: .utf8) ?? "{}"
                                continuation.yield(.toolCall(
                                    ToolCallData(name: tc.function.name, argumentsJSON: args)))
                            case .info(let info):
                                completionTokens = info.generationTokenCount
                                promptTokens = info.promptTokenCount
                            }
                        }

                        if !stopped, emitted < full.count {
                            continuation.yield(.text(Self.slice(full, emitted, full.count)))
                        }

                        if !stopped, completionTokens >= maxTokens { reason = "length" }
                        if sawToolCall { reason = "tool_calls" }
                        let usage = stopped
                            ? nil
                            : Usage(promptTokens: promptTokens, completionTokens: completionTokens)
                        continuation.yield(.finished(usage: usage, reason: reason))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Character offset of the earliest stop-sequence occurrence, if any.
    private static func earliestStop(in text: String, stops: [String]) -> Int? {
        var best: Int?
        for s in stops {
            if let r = text.range(of: s) {
                let off = text.distance(from: text.startIndex, to: r.lowerBound)
                best = min(best ?? off, off)
            }
        }
        return best
    }

    private static func slice(_ text: String, _ start: Int, _ end: Int) -> String {
        let a = text.index(text.startIndex, offsetBy: start)
        let b = text.index(text.startIndex, offsetBy: end)
        return String(text[a..<b])
    }

    public enum EngineError: LocalizedError {
        case notLoaded
        public var errorDescription: String? {
            switch self {
            case .notLoaded: return "No model is currently loaded."
            }
        }
    }
}
