import Foundation
import WisentOnboarding

/// Refuses a central bundle that is not the journey this build was written
/// against, so a mismatched publish falls back to the bundled definition
/// instead of presenting screens whose evidence nothing here reports.
struct BeingJourneyTransport: JourneyTransport {
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
