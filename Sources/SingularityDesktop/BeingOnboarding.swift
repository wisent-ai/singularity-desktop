import Foundation
import SwiftUI
import WisentDesignSystem
import WisentOnboarding

/// The first run of Singularity Desktop, and every later run that asks for it.
///
/// The window opened straight onto Life with no statement of what it does or
/// what it deliberately refuses to do, so the read-only boundary — the reason
/// this app is safe to point at a running being — was discoverable only by
/// reading the source. The journey states it once, in three steps that are all
/// real: what the window shows, what the runtime keeps, and one actual being
/// read from disk.
@MainActor
final class BeingOnboardingController: ObservableObject {
    private enum Constants {
        static let productID = "singularity-desktop"
        static let journeyID = "first-use"
        static let journeyVersion = "2026-09-01.1"
        static let firstSuccessFact = "being_state_observed"
        static let evidenceRevision = "singularity-desktop-first-use-2026-09-01"
        static let fallbackVersionID = UUID(uuidString: "3F5C1B90-1D64-4D2C-9E4B-27A3C0F5D611")!
        static let resource = "singularity-desktop-first-use"
        static let storageNamespace = "ai.wisent.singularity.onboarding.2026-09-01.1"
        static let deviceIDKey = "ai.wisent.singularity.onboarding.device-id"
    }

    private enum Presentation: Equatable {
        /// Before `start()` has answered.
        case loading
        /// The walkthrough is on screen.
        case presenting
        /// The last step handed the window back so a being can be read.
        case awaitingBeing
        case completed
        /// The journey could not be loaded. Singularity keeps working; a
        /// walkthrough that cannot load must never stand in front of the
        /// facts the window exists to report.
        case unavailable
    }

    @Published private(set) var screen: JourneyScreen?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isWorking = false
    @Published private var presentation: Presentation = .loading

    private var client: JourneyClient?
    private var hasStarted = false

    var isPresented: Bool { presentation == .presenting }
    var isFinalScreen: Bool { screen?.transitions.isEmpty == true }

    var title: String {
        screen?.presentation.text("title") ?? "Watch one digital being live"
    }

    var body: String {
        screen?.presentation.text("body") ?? ""
    }

    /// Which of the journey's steps is on screen, for the badge.
    var step: (index: Int, total: Int)? {
        guard let screen, let index = screenIDs.firstIndex(of: screen.screenId) else { return nil }
        return (index + 1, screenIDs.count)
    }

    private var screenIDs: [String] = []

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        isWorking = true
        defer { isWorking = false }

        do {
            let (client, progress) = try await bootstrap()
            self.client = client
            screen = await client.currentScreen
            if progress.status == .completed {
                presentation = .completed
                try? await client.flush()
            } else {
                presentation = .presenting
                try await client.expose(evidenceRevision: Constants.evidenceRevision)
            }
        } catch {
            presentation = .unavailable
            screen = nil
        }
    }

    func advance() async {
        guard let client, !isFinalScreen else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            guard try await client.advance(
                evidence: [:],
                evidenceRevision: Constants.evidenceRevision
            ) != nil else { return }
            screen = await client.currentScreen
            try await client.expose(evidenceRevision: Constants.evidenceRevision)
        } catch {
            errorMessage = "This step could not be saved on this Mac. Try again."
        }
    }

    /// The last step hands the window back: the walkthrough closes so the
    /// operator can choose a folder and look at the being, and completion is
    /// reported by the store's own read rather than by this button.
    func prepareToReadBeing() {
        guard isFinalScreen else { return }
        errorMessage = nil
        presentation = .awaitingBeing
    }

    /// A real being is on screen. Nothing else completes this journey: the
    /// fact is the store's decoded `state.json`, not a click.
    func beingStateObserved() async {
        guard presentation == .awaitingBeing, let client else { return }
        let completed = try? await client.complete(
            evidence: [Constants.firstSuccessFact: .boolean(true)],
            evidenceRevision: Constants.evidenceRevision
        )
        guard completed == true else {
            presentation = .presenting
            errorMessage = "The being was read, but finishing the guide could not be saved."
            return
        }
        presentation = .completed
        screen = nil
        try? await client.flush()
    }

    /// Settings asking for the walkthrough a second time.
    ///
    /// The journey is reset through the same client that recorded it, so Echo
    /// sees one `onboarding_reset` for this subject instead of a second
    /// parallel attempt, and the walkthrough goes back on screen in this
    /// session rather than waiting for a launch that would not show it either.
    /// The outcome is returned rather than stored, so the row that was pressed
    /// is where the answer appears.
    func replay() async -> WisentMutationOutcome {
        isWorking = true
        defer { isWorking = false }
        do {
            let client: JourneyClient
            if let existing = self.client {
                client = existing
            } else {
                (client, _) = try await bootstrap()
                self.client = client
                hasStarted = true
            }
            if await client.progress == nil {
                _ = try await client.start(evidenceRevision: Constants.evidenceRevision)
            }
            try await client.reset(evidenceRevision: Constants.evidenceRevision)
            screen = await client.currentScreen
            errorMessage = nil
            presentation = .presenting
            try await client.expose(evidenceRevision: Constants.evidenceRevision)
            try? await client.flush()
            return .succeeded("Started. The walkthrough is in front of this window.")
        } catch {
            return .failed(Self.replayFailure(error))
        }
    }

    /// Why a replay failed, in a sentence an operator can act on.
    ///
    /// `JourneyClientError` carries no localization, so `localizedDescription`
    /// renders it as "error 3" and names nothing.
    private static func replayFailure(_ error: Error) -> String {
        guard let journeyError = error as? JourneyClientError else {
            return (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
        switch journeyError {
        case .notStarted:
            return "The walkthrough did not load in this session, so there is nothing to show."
        case .storage:
            return "The walkthrough's progress could not be written on this Mac."
        case .transport:
            return "The onboarding service could not be reached."
        case let .invalid(reason):
            return reason
        }
    }

    private func bootstrap() async throws -> (JourneyClient, JourneyProgress) {
        let fallback = try Self.loadFallback()
        screenIDs = fallback.definition.screens.map(\.screenId)
        let transport = BeingJourneyTransport(
            upstream: EnvironmentJourneyTransport(
                tokenEnvironmentKey: "SINGULARITY_DESKTOP_STADO_INTEGRATION_TOKEN"
            ),
            requiredJourneyVersion: Constants.journeyVersion,
            requiredFirstSuccessFact: Constants.firstSuccessFact
        )
        let client = try JourneyClient(
            productId: Constants.productID,
            journeyId: Constants.journeyID,
            subjectHash: JourneySubject.scoped([Constants.productID, Self.deviceID()]),
            scope: .device,
            transport: transport,
            storage: UserDefaultsJourneyStorage(namespace: Constants.storageNamespace),
            fallback: fallback
        )
        let (bundle, progress) = try await client.start(evidenceRevision: Constants.evidenceRevision)
        screenIDs = bundle.definition.screens.map(\.screenId)
        return (client, progress)
    }

    /// The bundled definition, which is also the identity the client is built
    /// with: `JourneyRouter.validate` compares `productId` and `journeyId`
    /// against the bundle, so a disagreement here is a refusal, not a
    /// fallback.
    private static func loadFallback() throws -> JourneyBundle {
        // One loader for the whole fleet: JourneyResource resolves the
        // packaged bundle and throws a named error saying which paths it
        // tried, instead of SwiftPM's accessor trapping on a machine that
        // never built this binary.
        let definition = try String(
            decoding: JourneyResource.definitionData(
                resource: Constants.resource,
                bundleName: "SingularityDesktop_SingularityDesktop.bundle"
            ),
            as: UTF8.self
        )
        let bundle = try JourneyRouter.makeBundle(
            canonicalDefinition: definition,
            journeyVersionId: Constants.fallbackVersionID
        )
        guard bundle.definition.productId == Constants.productID,
              bundle.definition.journeyId == Constants.journeyID,
              bundle.definition.journeyVersion == Constants.journeyVersion,
              bundle.definition.firstSuccessFact == Constants.firstSuccessFact
        else { throw JourneyClientError.invalid("bundled first-use journey identity") }
        return bundle
    }

    private static func deviceID() -> String {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: Constants.deviceIDKey), !stored.isEmpty {
            return stored
        }
        let created = UUID().uuidString.lowercased()
        defaults.set(created, forKey: Constants.deviceIDKey)
        return created
    }
}

/// Refuses a central bundle that is not the journey this build was written
/// against, so a mismatched publish falls back to the bundled definition
/// instead of presenting screens whose evidence nothing here reports.
private struct BeingJourneyTransport: JourneyTransport {
    let upstream: EnvironmentJourneyTransport
    let requiredJourneyVersion: String
    let requiredFirstSuccessFact: String

    func readBundle(productId: String, journeyId: String) async throws -> JourneyBundle {
        let bundle = try await upstream.readBundle(productId: productId, journeyId: journeyId)
        guard bundle.definition.journeyVersion == requiredJourneyVersion,
              bundle.definition.firstSuccessFact == requiredFirstSuccessFact
        else { throw JourneyClientError.invalid("central journey identity") }
        return bundle
    }

    func readState(productId: String, attemptId: UUID, subjectHash: String) async throws -> JSONValue? {
        try await upstream.readState(productId: productId, attemptId: attemptId, subjectHash: subjectHash)
    }

    func assignExperiment(request: JourneyAssignmentRequest) async throws -> JourneyAssignmentResponse {
        try await upstream.assignExperiment(request: request)
    }

    func collect(event: JourneyRuntimeEvent) async throws {
        try await upstream.collect(event: event)
    }
}

// MARK: - Presentation

/// The walkthrough itself: one card over the window, driven by the
/// controller's `isPresented`. There is no second presentation path and no
/// second window.
struct BeingOnboardingView: View {
    @ObservedObject var onboarding: BeingOnboardingController
    let beingLoaded: Bool
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
                    if let errorMessage = onboarding.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(WisentTypography.bodyMedium(13))
                            .foregroundStyle(WisentDesign.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Spacer()
                        Button(action: primaryAction) {
                            Text(primaryLabel)
                                .opacity(onboarding.isWorking ? 0.35 : 1)
                        }
                        .buttonStyle(WisentPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .disabled(onboarding.isWorking)
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
                            isEnabled: !isReplaying
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
