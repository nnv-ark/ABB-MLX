import Foundation
import MLX
import MLXEmbedders

/// Wraps `MLXEmbedders` for `/v1/embeddings`. Holds one loaded model.
public actor EmbeddingEngine {
    public private(set) var currentModelId: String?
    private var container: ModelContainer?

    public init() {}

    public func load(modelId: String) async throws {
        if currentModelId == modelId, container != nil { return }
        container = nil
        let configuration = ModelConfiguration(id: modelId)
        container = try await MLXEmbedders.loadModelContainer(configuration: configuration)
        currentModelId = modelId
    }

    public func unload() {
        container = nil
        currentModelId = nil
    }

    public func embed(modelId: String, texts: [String]) async throws -> [[Float]] {
        try await load(modelId: modelId)
        guard let container else { throw MLXEngine.EngineError.notLoaded }

        return await container.perform { (model, tokenizer, pooling) -> [[Float]] in
            // Encode each input. swift-transformers' Tokenizer exposes
            // callAsFunction(text) -> [Int].
            let encoded: [[Int]] = texts.map { tokenizer.encode(text: $0) }
            let padToken = 0
            let maxLen = encoded.map(\.count).max() ?? 0

            var idsFlat = [Int32]()
            idsFlat.reserveCapacity(texts.count * maxLen)
            var maskFlat = [Int32]()
            maskFlat.reserveCapacity(texts.count * maxLen)

            for row in encoded {
                for tok in row { idsFlat.append(Int32(tok)); maskFlat.append(1) }
                if row.count < maxLen {
                    for _ in 0..<(maxLen - row.count) {
                        idsFlat.append(Int32(padToken)); maskFlat.append(0)
                    }
                }
            }

            let shape = [texts.count, maxLen]
            let inputIds = MLXArray(idsFlat, shape)
            let attentionMask = MLXArray(maskFlat, shape)
            let tokenTypeIds = MLXArray.zeros(like: inputIds)

            let output = model(
                inputIds,
                positionIds: nil,
                tokenTypeIds: tokenTypeIds,
                attentionMask: attentionMask
            )
            let pooled = pooling(output, mask: attentionMask,
                                 normalize: true, applyLayerNorm: false)

            let dim = pooled.shape.last ?? 0
            let flat: [Float] = pooled.asArray(Float.self)
            return stride(from: 0, to: flat.count, by: dim).map {
                Array(flat[$0..<min($0 + dim, flat.count)])
            }
        }
    }
}
