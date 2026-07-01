import Foundation

/// A small, curated set of known-good `mlx-community` models — roughly
/// mirroring Ollama's "pull one of these" library experience. Not
/// exhaustive; any Hugging Face `mlx-community` repo id still works with
/// `ModelDownloader.download(id:)`, this just gives the picker sane defaults.
public struct CatalogEntry: Sendable, Identifiable, Equatable {
    public var id: String { repoId }
    public let repoId: String
    public let displayName: String
    public let approxSizeGB: Double
    public let summary: String

    public init(repoId: String, displayName: String, approxSizeGB: Double, summary: String) {
        self.repoId = repoId
        self.displayName = displayName
        self.approxSizeGB = approxSizeGB
        self.summary = summary
    }
}

public enum ModelCatalog {
    public static let all: [CatalogEntry] = [
        CatalogEntry(
            repoId: "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
            displayName: "Qwen2.5 0.5B Instruct",
            approxSizeGB: 0.3,
            summary: "Tiny and fast — good for quick tests"
        ),
        CatalogEntry(
            repoId: "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit",
            displayName: "Qwen2.5 Coder 7B Instruct",
            approxSizeGB: 4.3,
            summary: "Strong general-purpose coding model"
        ),
        CatalogEntry(
            repoId: "mlx-community/Qwen2.5-Coder-14B-Instruct-4bit",
            displayName: "Qwen2.5 Coder 14B Instruct",
            approxSizeGB: 8.2,
            summary: "Larger coding model, better quality"
        ),
        CatalogEntry(
            repoId: "mlx-community/Mistral-Small-24B-Instruct-2501-4bit",
            displayName: "Mistral Small 24B Instruct",
            approxSizeGB: 13.0,
            summary: "General-purpose instruct model"
        ),
        CatalogEntry(
            repoId: "mlx-community/Llama-3.3-70B-Instruct-4bit",
            displayName: "Llama 3.3 70B Instruct",
            approxSizeGB: 40.0,
            summary: "Large, high-quality general model"
        ),
    ]
}
