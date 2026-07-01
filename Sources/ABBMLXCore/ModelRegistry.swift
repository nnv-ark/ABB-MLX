import Foundation

/// Scans the Hugging Face cache for locally-downloaded MLX models.
/// Same convention AppFactory's MLXService uses.
public enum ModelRegistry {
    public struct Installed: Sendable, Equatable {
        public let id: String           // e.g. mlx-community/Qwen2.5-7B-Instruct-4bit
        public let sizeBytes: Int64
        public init(id: String, sizeBytes: Int64) {
            self.id = id; self.sizeBytes = sizeBytes
        }
    }

    /// Vision/multimodal models live in the same cache dir but need MLXVLM,
    /// not MLXLLM. Hide them from the picker until we add VLM support.
    public static func isVisionModel(_ id: String) -> Bool {
        let n = id.lowercased()
        let markers = ["-vl-", "vision", "llava", "moondream",
                       "pixtral", "paligemma", "internvl", "minicpm-v"]
        return markers.contains(where: { n.contains($0) })
    }

    public static func scan() -> [Installed] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let hubDir = "\(home)/.cache/huggingface/hub"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: hubDir)
        else { return [] }

        var out: [Installed] = []
        for entry in entries where entry.hasPrefix("models--") {
            let stripped = String(entry.dropFirst("models--".count))
            let id = stripped.replacingOccurrences(of: "--", with: "/")
            let url = URL(fileURLWithPath: "\(hubDir)/\(entry)")
            var size: Int64 = 0
            if let walker = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.fileSizeKey]
            ) {
                for case let f as URL in walker {
                    if let s = try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        size += Int64(s)
                    }
                }
            }
            out.append(Installed(id: id, sizeBytes: size))
        }
        return out.sorted { $0.id < $1.id }
    }
}
