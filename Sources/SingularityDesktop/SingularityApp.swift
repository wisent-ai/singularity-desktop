import AppKit
import SwiftUI
import WisentDesignSystem
import WisentDesktopUpdate

@main
struct SingularityApp: App {
    @StateObject private var store = BeingStore()
    @StateObject private var updater = WisentUpdater()

    var body: some Scene {
        WindowGroup("Singularity") {
            RootView(store: store)
                .tint(WisentDesign.brand)
                .textSelection(.enabled)
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                WisentCheckForUpdatesCommand(updater: updater)
            }
        }
    }
}
