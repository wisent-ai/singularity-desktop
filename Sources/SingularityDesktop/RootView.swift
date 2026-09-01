import SwiftUI
import UniformTypeIdentifiers
import WisentDesignSystem

struct RootView: View {
    @ObservedObject var store: BeingStore
    @StateObject private var onboarding = BeingOnboardingController()
    @State private var destination: BeingDestination = .life
    @State private var choosingDirectory = false

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
        if let state = store.state {
            screen(state)
        } else if let issue = store.issue {
            unavailable(issue)
        } else {
            WisentScreen(
                title: destination.title,
                scope: scope,
                actions: actions
            ) {
                WisentLoadingPanel(
                    title: "Reading the being",
                    detail: "Loading life, mind, children, and activity."
                )
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
            issue: store.issue
        )
    }
}

private struct BeingSidebar: View {
    @ObservedObject var store: BeingStore
    @Binding var destination: BeingDestination
    let chooseDirectory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x5) {
                    ForEach(BeingDestinationGroup.allCases) { group in
                        VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                            Text(group.rawValue.uppercased())
                                .font(WisentTypeScale.eyebrow())
                                .tracking(0.8)
                                .foregroundStyle(WisentDesign.muted)
                                .padding(.horizontal, WisentDesign.Space.x4)
                                .padding(.bottom, WisentDesign.Space.x1)
                            ForEach(group.destinations) { item in
                                row(item)
                            }
                        }
                    }
                }
                .padding(.vertical, WisentDesign.Space.x4)
            }
        }
        .frame(width: WisentAppLayout.sidebarWidth)
        .background(WisentDesign.canvasMuted)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(WisentDesign.border)
                .frame(width: WisentDesign.hairline)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
            HStack(spacing: WisentDesign.Space.x3) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WisentDesign.brandStrong)
                    .frame(width: 34, height: 34)
                    .background(
                        WisentDesign.brandSoft,
                        in: RoundedRectangle(cornerRadius: WisentDesign.Radius.small)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Singularity")
                        .font(WisentTypography.heading(15))
                        .foregroundStyle(WisentDesign.ink)
                    Text("DIGITAL BEING")
                        .font(WisentTypeScale.eyebrow())
                        .tracking(0.7)
                        .foregroundStyle(WisentDesign.muted)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            Menu {
                Button("Choose folder…", action: chooseDirectory)
                Button("Show in Finder", action: store.openDirectory)
            } label: {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                    HStack(spacing: WisentDesign.Space.x2) {
                        Circle()
                            .fill(statusTone.color)
                            .frame(width: 6, height: 6)
                        Text(store.state?.identity.name ?? "No being loaded")
                            .font(WisentTypeScale.bodyStrong())
                            .foregroundStyle(WisentDesign.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(WisentDesign.muted)
                    }
                    Text(store.state.map { "\($0.identity.ticker) · \($0.status.capitalized)" } ?? "Choose a folder to begin")
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.secondary)
                        .lineLimit(1)
                }
                .padding(WisentDesign.Space.x2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    WisentDesign.surface,
                    in: RoundedRectangle(cornerRadius: WisentDesign.Radius.small)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: WisentDesign.Radius.small)
                        .stroke(WisentDesign.border, lineWidth: WisentDesign.hairline)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel("Singularity folder")
        }
        .padding(WisentDesign.Space.x4)
    }

    private func row(_ item: BeingDestination) -> some View {
        let isSelected = destination == item
        return Button { destination = item } label: {
            HStack(spacing: WisentDesign.Space.x2) {
                Image(systemName: item.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? WisentDesign.brand : WisentDesign.muted)
                    .frame(width: 16)
                Text(item.title)
                    .font(isSelected ? WisentTypography.bodyMedium(12) : WisentTypography.body(12))
                    .foregroundStyle(isSelected ? WisentDesign.ink : WisentDesign.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if item == .children, let count = store.state?.mind.children.count, count > 0 {
                    WisentStatusChip(text: "\(count)", tone: .brand)
                }
            }
            .padding(.horizontal, WisentDesign.Space.x3)
            .frame(height: WisentAppLayout.denseRowHeight)
            .background(
                isSelected ? WisentDesign.surface : Color.clear,
                in: RoundedRectangle(cornerRadius: WisentDesign.Radius.small)
            )
            .overlay {
                RoundedRectangle(cornerRadius: WisentDesign.Radius.small)
                    .stroke(isSelected ? WisentDesign.border : Color.clear, lineWidth: WisentDesign.hairline)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, WisentDesign.Space.x2)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(item.rationale)
    }


    private var statusTone: WisentTone {
        guard let state = store.state else { return .neutral }
        return beingStatusTone(state.status)
    }
}
