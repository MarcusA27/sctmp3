import SwiftUI
import AppKit

@main
struct SCTMP3App: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    var body: some Scene {
        Window("sctmp3", id: "main") {
            ContentView()
        }
        .defaultSize(width: 540, height: 660)
        .windowStyle(.hiddenTitleBar)
    }
}
