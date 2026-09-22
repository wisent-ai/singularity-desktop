import SwiftUI
import UniformTypeIdentifiers
import WisentDesignSystem

struct RootView: View {
    @ObservedObject var store: BeingStore
    @StateObject private var onboarding = BeingOnboardingController()
    @State private var destination: BeingDestination = .life
    @State private var choosingDirectory = false
    @State private var choosingImport = false
    @State private var importOutcome: WisentMutationOutcome = .idle

    var body: some View {
        HStack(spacing: 0) {
            BeingSidebar(
                store: store,
                destination: $destination,
                chooseDirectory: { choosingDirectory = true }
            )
            detail
        }
        .frame(
            minWidth: WisentAppLayout.minimumWindowWidth,
            minHeight: WisentAppLayout.minimumWindowHeight
        )
        .background(WisentDesign.canvas)
        .tint(WisentDesign.brand)
        // Every fact Singularity reports is selectable, and therefore
        // copyable. The window exists to state things a person then quotes
        // somewhere else — a being's system prompt, a balance, an activity
        // line, the sentence explaining why a state directory could not be
        // read — and SwiftUI's `Text` refuses selection on macOS unless a
        // view asks for it, which left 12 of 15 text sites dead to Cmd-C
        // while three had been fixed one at a time.
        //
        // `.textSelection` travels through the environment, so one call here
        // covers every screen, present and future, including the loading
        // panel and the unavailable notice that `detail` renders instead of
        // a screen. It sits on this body rather than in `SingularityApp`
        // because both windows the app can open — the `WindowGroup` scene
        // and the delegate's `wisentEnsureWindow` fallback — render exactly
        // this view, so this is the one place that reaches both.
        .textSelection(.enabled)
        .fileImporter(isPresented: $choosingDirectory, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result { store.selectDirectory(url) }
        }
        .fileImporter(isPresented: $choosingImport, allowedContentTypes: [.json]) { result in
            guard case let .success(url) = result else { return }
            importOutcome = .working("Validating with the being's state owner…")
            Task {
                do {
                    let imported = try await store.importMind(from: url)
                    importOutcome = imported.accepted
                        ? .succeeded(imported.summary)
                        : .failed(imported.summary)
                    destination = .mind
                } catch {
                    importOutcome = .failed(
                        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                    )
                }
            }
        }
        .task { await store.monitor() }
        .task { await onboarding.start() }
        // The walkthrough sits over this window and nowhere else: one overlay
        // driven by the controller's gate, so a completed journey is silent and
        // an unloadable one never stands in front of the being.
        .overlay {
            if onboarding.isPresented {
                BeingOnboardingView(
                    onboarding: onboarding,
                    beingLoaded: store.state != nil,
                    importOutcome: importOutcome,
                    importMind: { choosingImport = true },
                    dismissImportOutcome: { importOutcome = .idle },
                    readBeing: readBeing
                )
            }
        }
        // The last step is finished by a being, not by the button that closed
        // the card: the store's decoded `state.json` arriving is the fact.
        .onChange(of: store.state != nil) { _, loaded in
            guard loaded else { return }
            Task { await onboarding.beingStateObserved() }
        }
    }

    /// The walkthrough's final step hands the window back. A being already
    /// readable needs no folder prompt; otherwise the same importer the sidebar
    /// opens is what the operator needs next.
    private func readBeing() {
        onboarding.prepareToReadBeing()
        if store.state == nil {
            choosingDirectory = true
        } else {
            Task { await onboarding.beingStateObserved() }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if destination == .ecosystem {
            EcosystemScreen(directory: store.stateDirectory)
        } else if let state = store.state {
            screen(state)
        } else if let issue = store.issue {
            unavailable(issue)
        } else {
            WisentScreen(
                title: destination.title,
                scope: scope,
                actions: actions
            ) {
                BeingLoadingSkeleton(destination: destination)
            }
        }
    }

    @ViewBuilder
    private func screen(_ state: BeingState) -> some View {
        switch destination {
        case .life:
            BeingLifeScreen(
                state: state,
                activity: store.activity,
                chrome: chrome,
                onboarding: onboarding
            )
        case .mind:
            BeingMindScreen(state: state, chrome: chrome)
        case .economy:
            BeingEconomyScreen(state: state, chrome: chrome)
        case .children:
            BeingChildrenScreen(state: state, chrome: chrome)
        case .activity:
            BeingActivityScreen(state: state, activity: store.activity, chrome: chrome)
        case .ecosystem:
            EcosystemScreen(directory: store.stateDirectory)
        }
    }

    private func unavailable(_ issue: String) -> some View {
        WisentScreen(
            title: destination.title,
            scope: scope,
            actions: actions
        ) {
            if issue.hasPrefix("Missing regular file") {
                WisentEmptyPanel(
                    title: "No being found",
                    detail: "Choose a folder containing a being.",
                    symbol: "folder.badge.questionmark",
                    action: WisentAction("Choose folder", symbol: "folder", kind: .primary) {
                        choosingDirectory = true
                    }
                )
            } else {
                WisentAlertPanel(
                    tone: .danger,
                    title: "The being could not be read",
                    detail: "Choose another folder or try again.",
                    actions: [
                        WisentAction("Choose folder", symbol: "folder", kind: .secondary) {
                            choosingDirectory = true
                        },
                    ]
                )
            }
        }
    }

    private var scope: String? {
        store.state?.identity.name
    }

    private var freshness: String? {
        store.refreshedAt.map { "Read at \($0.formatted(date: .omitted, time: .standard))" }
    }

    private var actions: [WisentAction] {
        [
            WisentAction("Refresh", symbol: "arrow.clockwise", kind: .secondary) {
                Task { await store.refresh() }
            },
            WisentAction("Import", symbol: "square.and.arrow.down", kind: .secondary) {
                choosingImport = true
            },
            WisentAction("Folder", symbol: "folder", kind: .secondary) {
                choosingDirectory = true
            },
        ]
    }

    private var chrome: BeingScreenChrome {
        BeingScreenChrome(
            scope: scope,
            freshness: freshness,
            actions: actions,
            importOutcome: importOutcome,
            dismissImportOutcome: { importOutcome = .idle },
            issue: store.issue
        )
    }
}


