import Foundation
import SwiftUI
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

    private let server = ABBMLXServer()
    private let downloader = ModelDownloader()

    init() {
        let defaults = UserDefaults.standard
        self.port = defaults.object(forKey: "abbmlx.port") as? Int ?? 8080
        self.selectedModel = defaults.string(forKey: "abbmlx.model") ?? ""
        self.autoStart = defaults.object(forKey: "abbmlx.autoStart") as? Bool ?? true

        refresh()

        if autoStart, !selectedModel.isEmpty {
            Task { await self.start() }
        }
    }

    var baseURL: String { "http://localhost:\(port)" }

    func refresh() {
        installed = ModelRegistry.scan().filter { !ModelRegistry.isVisionModel($0.id) }
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
}
