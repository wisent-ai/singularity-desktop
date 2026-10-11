import AppKit
import Foundation
import WisentErrors

@MainActor
final class BeingStore: ObservableObject {
    @Published private(set) var state: BeingState?
    @Published private(set) var activity: [ActivityLine] = []
    @Published private(set) var issue: String?
    @Published private(set) var refreshedAt: Date?
    /// The being read; nothing is assumed until the operator chooses a
    /// directory or `SINGULARITY_STATE_DIR` names one.
    @Published private(set) var stateDirectory: URL?

    private let defaults: UserDefaults
    private let directoryKey = "singularityDesktop.stateDirectory"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: directoryKey) {
            stateDirectory = URL(fileURLWithPath: stored, isDirectory: true)
        } else if let configured = ProcessInfo.processInfo.environment["SINGULARITY_STATE_DIR"],
            !configured.isEmpty
        {
            stateDirectory = URL(fileURLWithPath: configured, isDirectory: true)
        } else {
            stateDirectory = nil
            issue = Self.noDirectoryIssue
        }
    }

    static let noDirectoryIssue =
        "No state directory is selected. Choose the folder the runtime writes to, or start the app with SINGULARITY_STATE_DIR."

    func selectDirectory(_ url: URL) {
        let selected = url.standardizedFileURL
        stateDirectory = selected
        defaults.set(selected.path, forKey: directoryKey)
        Task { await refresh() }
    }

    func openDirectory() {
        guard let stateDirectory else { return }
        NSWorkspace.shared.open(stateDirectory)
    }
    func importMind(from documentURL: URL) async throws -> MindImportResult {
        guard let stateDirectory else {
            throw StoreFailure(Self.noDirectoryIssue)
        }
        let result = try await MindImportClient.importDocument(
            documentURL,
            stateDirectory: stateDirectory
        )
        await refresh()
        return result
    }

    func monitor() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    func refresh() async {
        guard let stateDirectory else {
            issue = Self.noDirectoryIssue
            return
        }
        do {
            let loadedState = try Self.loadState(
                stateDirectory.appendingPathComponent("state.json"))
            let loadedActivity = try Self.loadActivity(
                stateDirectory.appendingPathComponent("activity.jsonl"))
            state = loadedState
            activity = loadedActivity
            issue = nil
            refreshedAt = Date()
        } catch {
            let message = error.localizedDescription
            // The monitor re-reads every two seconds, so report only when the
            // failure becomes user-visible state, not on every failed poll.
            if issue != message {
                let code =
                    (error as? StoreFailure)?.message.hasPrefix("Missing regular file") == true
                    ? "infra_down"
                    : "unknown"
                WisentFailureReporter.shared.report(
                    failurePoint: "singularity.beingstore.read",
                    code: code,
                    service: "singularity",
                    detail: message,
                    impact: "The being's state and activity cannot be shown."
                )
            }
            issue = message
        }
    }

    nonisolated private static func loadState(_ url: URL) throws -> BeingState {
        let data = try regularFile(url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom(decodeDate)
        let state = try decoder.decode(BeingState.self, from: data)
        guard state.schemaVersion == "being-v1" else {
            throw StoreFailure("Unsupported Singularity state schema: \(state.schemaVersion)")
        }
        return state
    }

    nonisolated private static func loadActivity(_ url: URL) throws -> [ActivityLine] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try regularFile(url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw StoreFailure("Activity journal is not UTF-8")
        }
        // A damaged line fails the load with its line number and cause: left
        // out, the feed showed a shortened history as if it were complete.
        return try text.split(separator: "\n").enumerated().map { index, line in
            // The line's number among the journal's nonempty lines, counted
            // only when one is reported.
            func damaged(_ reason: String) -> StoreFailure {
                let number = text[..<line.endIndex].split(separator: "\n").count
                return StoreFailure("Activity journal line \(number) \(reason)")
            }
            let value: Any
            do {
                value = try JSONSerialization.jsonObject(with: Data(line.utf8))
            } catch {
                throw damaged("is not JSON: \(error.localizedDescription)")
            }
            guard let object = value as? [String: Any] else {
                throw damaged("is not a JSON object")
            }
            guard let type = object["type"] as? String else {
                throw damaged("has no type")
            }
            let timestamp = (object["at"] as? String).flatMap(parseDate)
            let fields = ActivitySummaryField.allCases.compactMap { field -> String? in
                object[field.rawValue].map { "\(field.rawValue)=\($0)" }
            }
            return ActivityLine(
                id: index, type: type, timestamp: timestamp,
                summary: fields.joined(separator: " · "))
        }.reversed()
    }

    nonisolated private static func regularFile(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw StoreFailure("Missing regular file: \(url.lastPathComponent)")
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    nonisolated private static func decodeDate(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let date = parseDate(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid timestamp")
        }
        return date
    }

    nonisolated private static func parseDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
}

private struct StoreFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
