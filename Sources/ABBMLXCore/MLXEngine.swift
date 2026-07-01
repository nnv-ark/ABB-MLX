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

    public private(set) var currentModelId: String?
    private var container: ModelContainer?

    public init() {}

    /// Load (or switch to) a model by Hugging Face id, e.g.
    /// "mlx-community/Qwen2.5-7B-Instruct-4bit". Idempotent — re-loading
    /// the same id is a no-op.
    public func load(modelId: String,
                     onProgress: @escaping @Sendable (LoadProgress) -> Void = { _ in }) async throws {
        if currentModelId == modelId, container != nil { return }
        // Free previous container before loading the next one.
        container = nil
        MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)

        let configuration = ModelConfiguration(id: modelId)
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

    /// Streams generated text chunks. Cancelling the surrounding Task
    /// stops generation at the next token boundary.
    public func generate(
        modelId: String,
        messages: [ChatMessage],
        parameters: GenerationParameters
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.load(modelId: modelId)
                    guard let container = self.container else {
                        throw EngineError.notLoaded
                    }

                    if let seed = parameters.seed { MLXRandom.seed(seed) }

                    let userInputMessages: [[String: String]] = messages.map {
                        ["role": $0.role.rawValue, "content": $0.content]
                    }

                    let gp = GenerateParameters(
                        temperature: parameters.temperature,
                        topP: parameters.topP
                    )

                    try await container.perform { context in
                        let input = try await context.processor.prepare(
                            input: .init(messages: userInputMessages)
                        )
                        _ = try MLXLMCommon.generate(
                            input: input,
                            parameters: gp,
                            context: context
                        ) { tokens in
                            if Task.isCancelled {
                                return .stop
                            }
                            // Decode just the newly generated tokens and stream.
                            let text = context.tokenizer.decode(tokens: tokens)
                            continuation.yield(text)
                            return tokens.count >= parameters.maxTokens ? .stop : .more
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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
