/// The walkthrough as it appears: one card over the window, driven by the
/// controller, and the section on Life that offers to open it again.
///
/// There is no second presentation path and no second window.

import SwiftUI
import WisentDesignSystem
import WisentOnboarding

// MARK: - Presentation

/// The walkthrough itself: one card over the window, driven by the
/// controller's `isPresented`. There is no second presentation path and no
/// second window.
struct BeingOnboardingView: View {
    @ObservedObject var onboarding: BeingOnboardingController
    let beingLoaded: Bool
    let importOutcome: WisentMutationOutcome
    let importMind: () -> Void
    let dismissImportOutcome: () -> Void
    let readBeing: () -> Void

    var body: some View {
        ZStack {
            WisentCanvasBackground()
            WisentDesign.canvas.opacity(0.92)
                .ignoresSafeArea()

            WisentPanel(padding: WisentDesign.Space.x6) {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x5) {
                    header
                    VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                        Text(onboarding.title)
                            .font(WisentTypography.display(30))
                            .foregroundStyle(WisentDesign.ink)
                        Text(onboarding.body)
                            .font(WisentTypography.body(15))
                            .foregroundStyle(WisentDesign.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if onboarding.isFinalScreen {
                        Label(
                            beingLoaded
                                ? "A being is already readable in the selected folder."
                                : "No being has been read yet. Choose the runtime's state folder.",
                            systemImage: beingLoaded ? "checkmark.circle.fill" : "folder.badge.questionmark"
                        )
                        .font(WisentTypography.bodyMedium(13))
                        .foregroundStyle(beingLoaded ? WisentDesign.success : WisentDesign.secondary)
                    }
                    WisentActionButton(
                        action: WisentAction(
                            "Import existing mind…",
                            symbol: "square.and.arrow.down",
                            kind: .secondary,
                            isEnabled: !importOutcome.isWorking
                        ) { importMind() }
                    )
                    if importOutcome != .idle {
                        WisentMutationBar(outcome: importOutcome) {
                            dismissImportOutcome()
                        }
                    }
                    if let errorMessage = onboarding.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(WisentTypography.bodyMedium(13))
                            .foregroundStyle(WisentDesign.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Spacer()
                        // The step's own verb stays put while the journey
                        // advances: `isBusy` shimmers a bar where the word
                        // sits, keeps the accessible name, and refuses the
                        // second press this button used to take by dimming
                        // its own label.
                        WisentActionButton(
                            action: WisentAction(
                                primaryLabel,
                                kind: .primary,
                                isBusy: onboarding.isWorking
                            ) { primaryAction() }
                        )
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .frame(width: 620)
            .padding(WisentDesign.Space.x8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Singularity first-run walkthrough")
    }

    private var header: some View {
        HStack(spacing: WisentDesign.Space.x3) {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WisentDesign.brandStrong)
                .frame(width: 34, height: 34)
                .background(
                    WisentDesign.brandSoft,
                    in: RoundedRectangle(cornerRadius: WisentDesign.Radius.small)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("SINGULARITY")
                    .font(WisentTypeScale.eyebrow())
                    .tracking(0.7)
                    .foregroundStyle(WisentDesign.brand)
                Text("One persistent digital being")
                    .font(WisentTypography.body(13))
                    .foregroundStyle(WisentDesign.secondary)
            }
            Spacer(minLength: WisentDesign.Space.x4)
            if let step = onboarding.step {
                WisentBadge("Step \(step.index) of \(step.total)", symbol: "list.number", tone: .brand)
            }
        }
    }

    private var primaryLabel: String {
        guard onboarding.isFinalScreen else { return "Continue" }
        return beingLoaded ? "Show the being" : "Choose folder"
    }

    private func primaryAction() {
        if onboarding.isFinalScreen {
            readBeing()
        } else {
            Task { await onboarding.advance() }
        }
    }
}

/// The one control that puts the walkthrough back.
///
/// Singularity Desktop has no Settings screen — every destination reports the
/// being, not the application — so this sits last on Life, the destination the
/// window opens on and the only one about the being as a whole.
struct BeingWalkthroughSection: View {
    @ObservedObject var onboarding: BeingOnboardingController

    /// Held here rather than on the journey, so leaving Life clears the line
    /// instead of carrying a stale "Started." onto Mind.
    @State private var outcome: WisentMutationOutcome = .idle

    var body: some View {
        WisentSectionBox(
            title: "First-run walkthrough",
            detail: "See the walkthrough this product shows on a first run."
        ) {
            WisentPanel {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                    WisentActionButton(
                        action: WisentAction(
                            "Show it again",
                            symbol: "arrow.counterclockwise",
                            kind: .secondary,
                            isBusy: isReplaying
                        ) { showAgain() }
                    )
                    if outcome != .idle {
                        WisentMutationBar(outcome: outcome) { outcome = .idle }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var isReplaying: Bool { onboarding.isWorking || outcome.isWorking }

    /// The local `.working` line is what closes the control, not
    /// `onboarding.isWorking`: the controller does not raise that flag until
    /// the task below is scheduled, and a second press lands in the gap.
    private func showAgain() {
        guard !isReplaying else { return }
        outcome = .working("Starting the walkthrough…")
        Task { outcome = await onboarding.replay() }
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func text(_ key: String) -> String? {
        guard case let .string(value)? = self[key] else { return nil }
        return value
    }
}
