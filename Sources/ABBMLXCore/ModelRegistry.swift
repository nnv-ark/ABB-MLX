import Foundation
import Hub
import MLXLMCommon

/// Scans the on-disk cache a given `HubApi` reads from and writes to.
/// Deliberately NOT hardcoded to `~/.cache/huggingface/hub` (the Python
/// `huggingface_hub` convention) or any other fixed location — the caller
/// (`ServerController`) owns the configured `HubApi`/storage directory and
/// passes it in explicitly, so every part of the app agrees on where models
/// actually live. A model whose directory merely exists is not necessarily
/// loadable; `isComplete` verifies the weight shards are actually present
/// before calling something "installed".
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

    /// The on-disk directory for `id` under `hub`'s configured storage
    /// location, matching exactly where `LLMModelFactory.loadContainer(hub:)`
    /// looks/writes when given the same `hub`.
    public static func repoDirectory(id: String, hub: HubApi) -> URL {
        hub.localRepoLocation(Hub.Repo(id: id))
    }

    /// The root "models" directory two levels above any repo location,
    /// used to discover whatever has been downloaded without needing a
    /// hardcoded model list.
    private static func modelsRoot(hub: HubApi) -> URL {
        repoDirectory(id: "_placeholder_/_placeholder_", hub: hub)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// True only if the model's weight shard(s) are actually present with
    /// nonzero size — not merely that a directory with this name exists.
    /// This is the check that was missing before: a repo directory can be
    /// created (and even contain small config/tokenizer files) while the
    /// multi-gigabyte weights themselves never finished downloading.
    public static func isComplete(id: String, hub: HubApi) -> Bool {
        let dir = repoDirectory(id: id, hub: hub)
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

    public static func scan(hub: HubApi) -> [Installed] {
        let fm = FileManager.default
        guard let orgDirs = try? fm.contentsOfDirectory(
            at: modelsRoot(hub: hub), includingPropertiesForKeys: [.isDirectoryKey]
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
                guard isComplete(id: id, hub: hub) else { continue }

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
