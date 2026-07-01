import Foundation
import Hub
import MLXLMCommon

/// Downloads a model's weights and config into the exact cache location
/// `LLMModelFactory` reads from (`defaultHubApi`), so a completed download
/// is immediately loadable via `MLXEngine.load(modelId:)` with no extra
/// wiring — one download mechanism, one cache, no separate bookkeeping.
public actor ModelDownloader {
    public struct DownloadProgress: Sendable { public let fraction: Double }

    public private(set) var activeDownloads: Set<String> = []

    public init() {}

    /// Fetches weights (`*.safetensors`), config/tokenizer JSON (`*.json`),
    /// and BPE merge tables (`*.txt`) — the full set a text model needs to
    /// load, not just the narrower weights-only glob `LLMModelFactory` uses
    /// internally (which relies on a separate tokenizer fetch for `.txt`
    /// files; fetching everything up front avoids that split entirely).
    public func download(
        id: String,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void = { _ in }
    ) async throws {
        guard !activeDownloads.contains(id) else { return }
        activeDownloads.insert(id)
        defer { activeDownloads.remove(id) }

        let repo = Hub.Repo(id: id)
        _ = try await sharedHub.snapshot(
            from: repo,
            matching: ["*.safetensors", "*.json", "*.txt"]
        ) { progress in
            onProgress(DownloadProgress(fraction: progress.fractionCompleted))
        }
    }
}
