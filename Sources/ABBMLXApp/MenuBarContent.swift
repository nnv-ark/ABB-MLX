import SwiftUI
import ABBMLXCore

struct MenuBarContent: View {
    @Bindable var controller: ServerController
    @State private var showXcodeHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            modelSection
            if !controller.downloadable.isEmpty {
                downloadSection
            }
            portSection
            if let err = controller.lastError {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .lineLimit(3)
            }
            controlsRow
            Divider()
            footerRow
        }
        .padding(14)
        .frame(width: 380)
        .sheet(isPresented: $showXcodeHelp) {
            XcodeSetupView(baseURL: controller.baseURL) { showXcodeHelp = false }
                .frame(width: 480, height: 420)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("ABB-MLX")
                .font(.title3.weight(.semibold))
            Text(AppVersion.display)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(controller.isRunning ? .green : .secondary)
                    .frame(width: 8, height: 8)
                Text(controller.isRunning ? "Running" : "Stopped")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Model").font(.caption).foregroundStyle(.secondary)
            if controller.installed.isEmpty {
                Text("No models downloaded yet — pick one below")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Picker("", selection: $controller.selectedModel) {
                    ForEach(controller.installed, id: \.id) { m in
                        Text(displayName(for: m.id)).tag(m.id)
                    }
                }
                .labelsHidden()
                .disabled(controller.isRunning)
            }
        }
    }

    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Download a model").font(.caption).foregroundStyle(.secondary)
            ForEach(controller.downloadable) { entry in
                downloadRow(for: entry)
            }
        }
    }

    private func downloadRow(for entry: CatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.displayName).font(.caption)
                    Text(entry.summary).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if let fraction = controller.downloadProgress[entry.repoId] {
                    ProgressView(value: fraction)
                        .frame(width: 80)
                } else {
                    Button("Get (\(String(format: "%.1f", entry.approxSizeGB)) GB)") {
                        controller.download(entry)
                    }
                    .controlSize(.small)
                }
            }
            if let err = controller.downloadErrors[entry.repoId] {
                Text(err).font(.caption2).foregroundStyle(.red).lineLimit(2)
            }
        }
    }

    private var portSection: some View {
        HStack {
            Text("Port").font(.caption).foregroundStyle(.secondary)
            TextField("8080",
                      value: $controller.port,
                      format: .number.grouping(.never))
                .frame(width: 70)
                .textFieldStyle(.roundedBorder)
                .disabled(controller.isRunning)
            Spacer()
            Toggle("Auto-start", isOn: $controller.autoStart)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption)
        }
    }

    private var controlsRow: some View {
        HStack {
            Button(controller.isRunning ? "Stop" : "Start") {
                Task {
                    if controller.isRunning { await controller.stop() }
                    else { await controller.start() }
                }
            }
            .keyboardShortcut(.defaultAction)

            Button("Refresh") { controller.refresh() }

            Spacer()

            Button {
                controller.copyBaseURLToClipboard()
            } label: {
                Label(controller.baseURL, systemImage: "doc.on.doc")
                    .labelStyle(.titleAndIcon)
            }
            .controlSize(.small)
            .help("Copy server URL")
        }
    }

    private var footerRow: some View {
        HStack {
            Button("Connect to Xcode…") { showXcodeHelp = true }
                .controlSize(.small)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .controlSize(.small)
        }
    }

    // MARK: - Helpers

    private func displayName(for id: String) -> String {
        // mlx-community/Qwen2.5-Coder-7B-Instruct-4bit → Qwen2.5-Coder-7B-Instruct-4bit
        id.split(separator: "/").last.map(String.init) ?? id
    }
}
