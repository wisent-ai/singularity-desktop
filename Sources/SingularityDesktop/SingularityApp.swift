import AppKit
import SwiftUI
import WisentAuth
import WisentDesignSystem
import WisentDesktopUpdate

@MainActor
final class SingularityAppDelegate: NSObject, NSApplicationDelegate {
    let store = BeingStore()
    let auth = WisentAuthStore(productName: "Singularity")
    private var fallbackWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [self] in
            fallbackWindow = wisentEnsureWindow(
                title: "Singularity",
                size: CGSize(width: 1_180, height: 760)
            ) {
                WisentAuthGate(store: self.auth) {
                    RootView(store: self.store)
                }
            }
        }
    }
}

@main
struct SingularityApp: App {
    @NSApplicationDelegateAdaptor(SingularityAppDelegate.self) private var delegate
    @StateObject private var updater = WisentUpdater()

    var body: some Scene {
        WindowGroup("Singularity") {
            WisentAuthGate(store: delegate.auth) {
                RootView(store: delegate.store)
            }
        }
        .defaultSize(width: 1_180, height: 760)
        .windowResizability(.contentMinSize)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                WisentCheckForUpdatesCommand(updater: updater)
            }
        }
    }
}
