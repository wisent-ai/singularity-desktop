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
    private static let directoryKey = "singularityDesktop.stateDirectory"
    private static let stateName = "state.json"
    private static let journalName = "activity.jsonl"
    /// The watch over the directory being shown, while `monitor()` runs.
    private var watch: StateDirectoryWatch?
    /// Ends `monitor()`'s wait for a directory to read.
    private var chosen: AsyncStream<Void>.Continuation?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stateDirectory = Self.configuredDirectory(defaults)
        if stateDirectory == nil {
            issue = Self.noDirectoryIssue
        }
    }

    /// The directory the operator chose before, or the one
    /// `SINGULARITY_STATE_DIR` names; none when neither says one.
    private static func configuredDirectory(_ defaults: UserDefaults) -> URL? {
        if let stored = defaults.string(forKey: directoryKey) {
            return URL(fileURLWithPath: stored, isDirectory: true)
        }
        if let configured = ProcessInfo.processInfo.environment["SINGULARITY_STATE_DIR"],
            !configured.isEmpty
        {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }
        return nil
    }

    static let noDirectoryIssue =
        "No state directory is selected. Choose the folder the runtime writes to, or start the app with SINGULARITY_STATE_DIR."

    func selectDirectory(_ url: URL) {
        let selected = url.standardizedFileURL
        stateDirectory = selected
        defaults.set(selected.path, forKey: Self.directoryKey)
        // `monitor()` reads the chosen directory and watches it instead.
        watch?.stop()
        chosen?.yield()
    }

    func openDirectory() {
        guard let stateDirectory else { return }
        NSWorkspace.shared.open(stateDirectory)
    }
    func importMind(from documentURL: URL) async throws -> MindImportResult {
        guard let stateDirectory else {
            throw StoreFailure(Self.noDirectoryIssue, code: .config)
        }
        let result = try await MindImportClient.importDocument(
            documentURL,
            stateDirectory: stateDirectory
        )
        await refresh()
        return result
    }

    /// Reads the being, then reads it again after each change the runtime
    /// makes to the state directory, until the task running this ends. Choosing
    /// another directory moves the watch there. When there is no directory,
    /// or it cannot be watched, the issue says so and this waits for a choice.
    func monitor() async {
        while !Task.isCancelled {
            await refresh()
            guard let stateDirectory else {
                await nextChoice()
                continue
            }
            do {
                let watch = try StateDirectoryWatch(
                    directory: stateDirectory,
                    journal: stateDirectory.appendingPathComponent(Self.journalName))
                self.watch = watch
                defer { self.watch = nil }
                for try await _ in watch.changes {
                    watch.taken()
                    await refresh()
                }
            } catch {
                show(error, at: "singularity.beingstore.watch")
                await nextChoice()
            }
        }
    }

    private func nextChoice() async {
        let made = AsyncStream<Void>.makeStream()
        chosen = made.continuation
        defer { chosen = nil }
        for await _ in made.stream { return }
    }

    func refresh() async {
        guard let stateDirectory else {
            issue = Self.noDirectoryIssue
            return
        }
        do {
            let loadedState = try Self.loadState(
                stateDirectory.appendingPathComponent(Self.stateName))
            let loadedActivity = try Self.loadActivity(
                stateDirectory.appendingPathComponent(Self.journalName))
            state = loadedState
            activity = loadedActivity
            issue = nil
            refreshedAt = Date()
        } catch {
            show(error, at: "singularity.beingstore.read")
        }
    }

    /// Shows a failure and reports it when it first becomes the shown issue;
    /// a read after every runtime write repeats it until the cause is gone.
    private func show(_ error: Error, at failurePoint: String) {
        let message = error.localizedDescription
        if issue != message {
            WisentFailureReporter.shared.report(
                failurePoint: failurePoint,
                code: Self.code(of: error).rawValue,
                service: "singularity",
                detail: message,
                impact: "The being's state and activity cannot be shown."
            )
        }
        issue = message
    }

    /// A failure this store raised carries its code; a file the system could
    /// not find is the runtime not having written it; anything else is the
    /// catalogue's unknown, reported with its own description.
    nonisolated private static func code(of error: Error) -> Code {
        if let failure = error as? StoreFailure { return failure.code }
        if let cocoa = error as? CocoaError, cocoa.code == .fileReadNoSuchFile { return .infraDown }
        return .unknown
    }

    nonisolated private static func loadState(_ url: URL) throws -> BeingState {
        let data = try regularFile(url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom(decodeDate)
        let state = try decoder.decode(BeingState.self, from: data)
        guard state.schemaVersion == "being-v1" else {
            throw StoreFailure(
                "Unsupported Singularity state schema: \(state.schemaVersion)", code: .refused)
        }
        return state
    }

    nonisolated private static func loadActivity(_ url: URL) throws -> [ActivityLine] {
        let data: Data
        do {
            data = try regularFile(url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw StoreFailure("Activity journal is not UTF-8", code: .refused)
        }
        // Keep physical line positions; only the final line terminator is not a record.
        if text.isEmpty { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let records = text.hasSuffix("\n") ? lines.dropLast() : lines[...]
        return try records.enumerated().map { index, line in
            func damaged(_ reason: String) -> StoreFailure {
                StoreFailure("Activity journal line \(index + 1) \(reason)", code: .refused)
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
            throw StoreFailure("Missing regular file: \(url.lastPathComponent)", code: .infraDown)
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

/// A read this store refuses, with the catalogue code it is reported under:
/// `.infraDown` when the runtime has not written a file, `.refused` when what
/// it wrote cannot be shown, `.config` when no directory is chosen.
private struct StoreFailure: LocalizedError {
    let message: String
    let code: Code
    init(_ message: String, code: Code) {
        self.message = message
        self.code = code
    }
    var errorDescription: String? { message }
}
