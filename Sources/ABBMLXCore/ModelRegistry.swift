import Foundation
import Hub
@preconcurrency import MLXLMCommon

/// `defaultHubApi` is a library-level `var`, initialized once at process
/// start and never reassigned. `HubApi` itself is `Sendable`; the
/// `@preconcurrency` import above is what's needed to read this specific
/// un-isolated global from Swift 6 strict-concurrency code.
let sharedHub = defaultHubApi

/// Scans the on-disk cache `LLMModelFactory` actually reads from and writes
/// to (`defaultHubApi`, which resolves to `~/Library/Caches/models/<org>/<repo>`)
/// — deliberately NOT `~/.cache/huggingface/hub` (the Python `huggingface_hub`
/// convention), which is a different, unrelated cache that this app's MLX
/// stack never touches. A model whose directory merely exists there is not
/// necessarily loadable; `isComplete` verifies the weight shards are actually
/// present before calling something "installed".
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

    /// The on-disk directory for `id`, matching exactly where
    /// `LLMModelFactory.shared.loadContainer` looks/writes. Derived from
    /// `defaultHubApi` itself (rather than re-deriving `~/Library/Caches`)
    /// so this stays correct if that default ever changes upstream.
    public static func repoDirectory(id: String) -> URL {
        sharedHub.localRepoLocation(Hub.Repo(id: id))
    }

    /// The root "models" directory two levels above any repo location,
    /// used to discover whatever has been downloaded without needing a
    /// hardcoded model list.
    private static var modelsRoot: URL {
        repoDirectory(id: "_placeholder_/_placeholder_")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// True only if the model's weight shard(s) are actually present with
    /// nonzero size — not merely that a directory with this name exists.
    /// This is the check that was missing before: a repo directory can be
    /// created (and even contain small config/tokenizer files) while the
    /// multi-gigabyte weights themselves never finished downloading.
    public static func isComplete(id: String) -> Bool {
        let dir = repoDirectory(id: id)
        let fm = FileManager.default

        func nonEmpty(_ url: URL) -> Bool {
            guard let size = try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64
            else { return false }
            return size > 0
        }

        let indexURL = dir.appendingPathComponent("model.safetensors.index.json")
        if fm.fileExists(atPath: indexURL.path) {
            guard let data = try? Data(contentsOf: indexURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let weightMap = json["weight_map"] as? [String: String]
            else { return false }
            let shards = Set(weightMap.values)
            guard !shards.isEmpty else { return false }
            return shards.allSatisfy { nonEmpty(dir.appendingPathComponent($0)) }
        }

        return nonEmpty(dir.appendingPathComponent("model.safetensors"))
    }

    public static func scan() -> [Installed] {
        let fm = FileManager.default
        guard let orgDirs = try? fm.contentsOfDirectory(
            at: modelsRoot, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        var out: [Installed] = []
        for orgURL in orgDirs {
            guard (try? orgURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }
            guard let repoDirs = try? fm.contentsOfDirectory(
                at: orgURL, includingPropertiesForKeys: [.isDirectoryKey]
            ) else { continue }

            for repoURL in repoDirs {
                guard (try? repoURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                else { continue }
                let id = "\(orgURL.lastPathComponent)/\(repoURL.lastPathComponent)"
                guard isComplete(id: id) else { continue }

                var size: Int64 = 0
                if let walker = fm.enumerator(
                    at: repoURL, includingPropertiesForKeys: [.fileSizeKey]
                ) {
                    for case let f as URL in walker {
                        if let s = try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                            size += Int64(s)
                        }
                    }
                }
                out.append(Installed(id: id, sizeBytes: size))
            }
        }
        return out.sorted { $0.id < $1.id }
    }
}
