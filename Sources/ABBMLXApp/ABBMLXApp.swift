import SwiftUI
import ABBMLXCore
import ABBMLXServer

public enum AppVersion {
    public static let short = "1.0.0"
    public static let channel = "beta"
    public static var display: String { "\(short) \(channel)" }
}

@main
struct ABBMLXAppMain: App {
    @State private var controller = ServerController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(controller: controller)
        } label: {
            Image(systemName: controller.isRunning
                  ? "cpu.fill" : "cpu")
        }
        .menuBarExtraStyle(.window)
    }
}
