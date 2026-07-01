import SwiftUI

struct XcodeSetupView: View {
    let baseURL: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "hammer.fill").font(.title2)
                Text("Connect ABB-MLX to Xcode")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }

            Text("Xcode 26 lets you point its chat panel at any OpenAI-compatible localhost provider. ABB-MLX is exactly that.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            step(number: 1, title: "Open Xcode settings",
                 detail: "Xcode → Settings… → Coding Intelligence")
            step(number: 2, title: "Add a chat provider",
                 detail: "Scroll to Chat → Add a Chat Provider… → Localhost")
            step(number: 3, title: "Paste this URL",
                 detail: baseURL,
                 mono: true)
            step(number: 4, title: "Name it ABB-MLX",
                 detail: "Xcode will call GET /v1/models to populate the model list.")
            step(number: 5, title: "Pick ABB-MLX in the chat panel",
                 detail: "It becomes available wherever you choose a chat model.")

            Spacer()

            HStack {
                Text("Server status:").font(.caption).foregroundStyle(.secondary)
                Text(baseURL).font(.caption.monospaced())
                Spacer()
            }
        }
        .padding(20)
    }

    private func step(number: Int, title: String,
                       detail: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15))
                Text("\(number)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail)
                    .font(mono ? .callout.monospaced() : .callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}
