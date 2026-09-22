import Foundation
import Combine

@MainActor
final class EcosystemStore: ObservableObject {
    @Published private(set) var status: EcosystemStatus?
    @Published private(set) var opportunities: [EcosystemOpportunity] = []
    @Published private(set) var initiatives: [EcosystemInitiative] = []
    @Published private(set) var opportunityNext: Int64?
    @Published private(set) var initiativeNext: Int64?
    @Published private(set) var records: [EcosystemRecordSummary] = []
    @Published private(set) var recordsNext: Int64?
    @Published private(set) var recordsKind: String?
    @Published private(set) var recordsInitiative: String?
    @Published private(set) var recordChunk: EcosystemRecordChunk?
    @Published private(set) var explanation: String?
    @Published private(set) var issue: String?
    @Published private(set) var busy = false
    private var directory: URL?
    private var operation: UUID?
    private var cancelWork: (@Sendable () -> Void)?

    func refresh(_ selectedDirectory: URL) async {
        guard !Task.isCancelled, directory != selectedDirectory || !busy else { return }
        directory = selectedDirectory
        let request = begin()
        clear()
        issue = nil
        defer { finish(request) }
        do {
            let work = Task {
                async let observedStatus = EcosystemClient.status(selectedDirectory)
                async let observedOpportunities = EcosystemClient.opportunities(selectedDirectory)
                async let observedInitiatives = EcosystemClient.initiatives(selectedDirectory)
                async let observedRecords = EcosystemClient.records(selectedDirectory, kind: nil, initiativeId: nil)
                let status = try await observedStatus
                var opportunities: EcosystemItems<EcosystemOpportunity>?
                var initiatives: EcosystemItems<EcosystemInitiative>?
                var records: EcosystemItems<EcosystemRecordSummary>?
                var issues: [String] = []
                do { opportunities = try await observedOpportunities }
                catch { issues.append("Opportunities: \(error.localizedDescription)") }
                do { initiatives = try await observedInitiatives }
                catch { issues.append("Initiatives: \(error.localizedDescription)") }
                do { records = try await observedRecords }
                catch { issues.append("Records: \(error.localizedDescription)") }
                return (status, opportunities, initiatives, records, issues)
            }
            let values = try await wait(work, request: request)
            try Task.checkCancellation()
            guard operation == request else { return }
            status = values.0
            opportunities = values.1?.items ?? []
            opportunityNext = values.1?.nextCursor
            initiatives = values.2?.items ?? []
            initiativeNext = values.2?.nextCursor
            records = values.3?.items ?? []
            recordsNext = values.3?.nextCursor
            issue = values.4.isEmpty ? nil : values.4.joined(separator: "\n")
        } catch {
            failed(error, request: request)
        }
    }

    func olderOpportunities(_ directory: URL) async {
        guard !Task.isCancelled, self.directory == directory, !busy, let before = opportunityNext else { return }
        let request = begin()
        defer { finish(request) }
        do {
            let result = try await wait(Task { try await EcosystemClient.opportunities(directory, before: before) }, request: request)
            try Task.checkCancellation()
            guard operation == request else { return }
            opportunities = result.items
            opportunityNext = result.nextCursor
            issue = nil
        } catch {
            failed(error, request: request, discardState: false)
        }
    }

    func olderInitiatives(_ directory: URL) async {
        guard !Task.isCancelled, self.directory == directory, !busy, let before = initiativeNext else { return }
        let request = begin()
        defer { finish(request) }
        do {
            let result = try await wait(Task { try await EcosystemClient.initiatives(directory, before: before) }, request: request)
            try Task.checkCancellation()
            guard operation == request else { return }
            initiatives = result.items
            initiativeNext = result.nextCursor
            issue = nil
        } catch {
            failed(error, request: request, discardState: false)
        }
    }

    func loadRecords(_ directory: URL, kind: String?, initiativeId: String?, before: Int64? = nil) async {
        guard !Task.isCancelled, self.directory == directory, !busy else { return }
        let request = begin()
        defer { finish(request) }
        do {
            let result = try await wait(Task {
                try await EcosystemClient.records(directory, kind: kind, initiativeId: initiativeId, before: before)
            }, request: request)
            try Task.checkCancellation()
            guard operation == request else { return }
            records = result.items
            recordsNext = result.nextCursor
            recordsKind = kind
            recordsInitiative = initiativeId
            issue = nil
        } catch {
            failed(error, request: request, discardState: false)
        }
    }

    func readRecord(_ directory: URL, kind: String, id: String, offset: UInt64 = 0, revision: String? = nil) async -> Bool {
        guard !Task.isCancelled, self.directory == directory, !busy else { return false }
        let request = begin()
        recordChunk = nil
        defer { finish(request) }
        do {
            let result = try await wait(Task {
                try await EcosystemClient.record(directory, kind: kind, id: id, offset: offset, revision: revision)
            }, request: request)
            try Task.checkCancellation()
            guard operation == request else { return false }
            recordChunk = result
            issue = nil
            return true
        } catch {
            failed(error, request: request, discardState: false)
            return false
        }
    }

    func setPaused(_ paused: Bool, directory: URL) async {
        guard !Task.isCancelled, self.directory == directory, !busy else { return }
        let request = begin()
        defer { finish(request) }
        do {
            let work = Task { try await EcosystemClient.status(directory, method: paused ? "pause" : "resume") }
            let result = try await wait(work, request: request)
            try Task.checkCancellation()
            guard operation == request else { return }
            status = result
            issue = nil
        } catch {
            failed(error, request: request)
        }
    }

    func explain(_ id: String, directory: URL) async {
        guard !Task.isCancelled, self.directory == directory, !busy else { return }
        let request = begin()
        explanation = nil
        defer { finish(request) }
        do {
            let work = Task { try await EcosystemClient.explain(directory, id: id) }
            let result = try await wait(work, request: request)
            try Task.checkCancellation()
            guard operation == request else { return }
            explanation = result
            issue = nil
        } catch {
            failed(error, request: request, discardState: false)
        }
    }

    func cancel() {
        cancelWork?()
        cancelWork = nil
        operation = nil
        directory = nil
        busy = false
        clear()
    }

    private func wait<Value: Sendable>(_ work: Task<Value, Error>, request: UUID) async throws -> Value {
        guard operation == request else {
            work.cancel()
            throw CancellationError()
        }
        cancelWork = { work.cancel() }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }

    private func begin() -> UUID {
        cancelWork?()
        cancelWork = nil
        let request = UUID()
        operation = request
        busy = true
        return request
    }

    private func finish(_ request: UUID) {
        guard operation == request else { return }
        cancelWork = nil
        operation = nil
        busy = false
    }

    private func failed(_ error: Error, request: UUID, discardState: Bool = true) {
        guard operation == request else { return }
        if discardState { clear() }
        issue = error is CancellationError
            ? "The owner request was cancelled. Its final state was not confirmed."
            : error.localizedDescription
    }

    private func clear() {
        status = nil
        opportunities = []
        initiatives = []
        explanation = nil
        opportunityNext = nil
        initiativeNext = nil
        records = []
        recordsNext = nil
        recordsKind = nil
        recordsInitiative = nil
        recordChunk = nil
    }
}
