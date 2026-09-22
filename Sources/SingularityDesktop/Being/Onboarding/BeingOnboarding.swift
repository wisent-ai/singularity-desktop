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
        static let journeyVersion = "2026-09-04.1"
        static let firstSuccessFact = "being_state_observed"
        static let evidenceRevision = "singularity-desktop-first-use-2026-09-04"
        static let fallbackVersionID = UUID(uuidString: "2BC9E3AC-831F-4E96-A93A-E93756AE9F87")!
        static let resource = "singularity-desktop-first-use"
        static let storageNamespace = "ai.wisent.singularity.onboarding.2026-09-04.1"
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

