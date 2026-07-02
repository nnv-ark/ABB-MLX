import Foundation
import SwiftUI
import Hub
import ABBMLXCore
import ABBMLXServer

@Observable
@MainActor
final class ServerController {
    // Settings (persisted)
    var port: Int {
        didSet { UserDefaults.standard.set(port, forKey: "abbmlx.port") }
    }
    var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "abbmlx.model") }
    }
    var autoStart: Bool {
        didSet { UserDefaults.standard.set(autoStart, forKey: "abbmlx.autoStart") }
    }
    /// Where model weights are stored/read from. Applies on next launch —
    /// changing it while running doesn't hot-swap the already-constructed
    /// engine/downloader, which is a reasonable simplification for now.
    var modelsDirectory: String {
        didSet { UserDefaults.standard.set(modelsDirectory, forKey: "abbmlx.modelsDirectory") }
    }

    // Live state
    var isRunning = false
    var installed: [ModelRegistry.Installed] = []
    var lastError: String?

    // Downloads
    var downloadProgress: [String: Double] = [:]   // repoId -> 0...1 while in flight
    var downloadErrors: [String: String] = [:]      // repoId -> message

    /// Catalog entries not already installed, for the download picker.
    var downloadable: [CatalogEntry] {
        let installedIds = Set(installed.map(\.id))
        return ModelCatalog.all.filter { !installedIds.contains($0.repoId) }
    }

    /// Configured once at launch from `modelsDirectory`; every model lookup
    /// (registry scan, download, load) goes through this same `HubApi` so
    /// "installed" and "loadable" always agree.
    private let hub: HubApi
    private let server: ABBMLXServer
    private let downloader: ModelDownloader

    init() {
        let defaults = UserDefaults.standard
        self.port = defaults.object(forKey: "abbmlx.port") as? Int ?? 8080
        self.selectedModel = defaults.string(forKey: "abbmlx.model") ?? ""
        self.autoStart = defaults.object(forKey: "abbmlx.autoStart") as? Bool ?? true
        let defaultModelsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Developer/LLM").path
        let modelsDirectory = defaults.string(forKey: "abbmlx.modelsDirectory") ?? defaultModelsDir
        self.modelsDirectory = modelsDirectory

        let hub = HubApi(downloadBase: URL(fileURLWithPath: modelsDirectory))
        self.hub = hub
        self.server = ABBMLXServer(hub: hub, engine: MLXEngine(hub: hub), embedEngine: EmbeddingEngine(hub: hub))
        self.downloader = ModelDownloader(hub: hub)

        refresh()

        if autoStart, !selectedModel.isEmpty {
            Task { await self.start() }
        }
    }

    var baseURL: String { "http://localhost:\(port)" }

    func refresh() {
        installed = ModelRegistry.scan(hub: hub).filter { !ModelRegistry.isVisionModel($0.id) }
        if selectedModel.isEmpty, let first = installed.first {
            selectedModel = first.id
        } else if !installed.contains(where: { $0.id == selectedModel }),
                  let first = installed.first {
            selectedModel = first.id
        }
    }

    func start() async {
        guard !selectedModel.isEmpty else {
            lastError = "Pick a model first."
            return
        }
        do {
            try await server.start(config: .init(port: port))
            isRunning = await server.isRunning
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() async {
        await server.stop()
        isRunning = await server.isRunning
    }

    func download(_ entry: CatalogEntry) {
        guard downloadProgress[entry.repoId] == nil else { return }
        downloadErrors[entry.repoId] = nil
        downloadProgress[entry.repoId] = 0
        Task {
            do {
                try await downloader.download(id: entry.repoId) { progress in
                    Task { @MainActor in
                        self.downloadProgress[entry.repoId] = progress.fraction
                    }
                }
                downloadProgress[entry.repoId] = nil
                refresh()
            } catch {
                downloadProgress[entry.repoId] = nil
                downloadErrors[entry.repoId] = error.localizedDescription
            }
        }
    }

    func copyBaseURLToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(baseURL, forType: .string)
    }

    func revealModelsDirectoryInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: modelsDirectory)
    }
}
