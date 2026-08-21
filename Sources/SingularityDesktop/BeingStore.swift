import AppKit
import Foundation

@MainActor
final class BeingStore: ObservableObject {
    @Published private(set) var state: BeingState?
    @Published private(set) var activity: [ActivityLine] = []
    @Published private(set) var issue: String?
    @Published private(set) var refreshedAt: Date?
    @Published private(set) var stateDirectory: URL

    private let defaults: UserDefaults
    private let directoryKey = "singularityDesktop.stateDirectory"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: directoryKey) {
            stateDirectory = URL(fileURLWithPath: stored, isDirectory: true)
        } else if let configured = ProcessInfo.processInfo.environment["SINGULARITY_STATE_DIR"], !configured.isEmpty {
            stateDirectory = URL(fileURLWithPath: configured, isDirectory: true)
        } else {
            stateDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".singularity", isDirectory: true)
        }
    }

    func selectDirectory(_ url: URL) {
        stateDirectory = url.standardizedFileURL
        defaults.set(stateDirectory.path, forKey: directoryKey)
        Task { await refresh() }
    }

    func openDirectory() {
        NSWorkspace.shared.open(stateDirectory)
    }

    func monitor() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    func refresh() async {
        do {
            let loadedState = try Self.loadState(stateDirectory.appendingPathComponent("state.json"))
            let loadedActivity = try Self.loadActivity(stateDirectory.appendingPathComponent("activity.jsonl"))
            state = loadedState
            activity = loadedActivity
            issue = nil
            refreshedAt = Date()
        } catch {
            issue = error.localizedDescription
        }
    }

    nonisolated private static func loadState(_ url: URL) throws -> BeingState {
        let data = try boundedRegularFile(url, limit: 16 * 1024 * 1024)
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
        let data = try boundedRegularFile(url, limit: 16 * 1024 * 1024)
        guard let text = String(data: data, encoding: .utf8) else {
            throw StoreFailure("Activity journal is not UTF-8")
        }
        return text.split(separator: "\n").suffix(2_000).enumerated().compactMap { index, line in
            guard let data = line.data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = value["type"] as? String else { return nil }
            let timestamp = (value["at"] as? String).flatMap(parseDate)
            let fields = ["cycle", "tool", "status", "amount", "source", "message"]
                .compactMap { key -> String? in value[key].map { "\(key)=\($0)" } }
            return ActivityLine(id: index, type: type, timestamp: timestamp, summary: fields.joined(separator: " · "))
        }.reversed()
    }

    nonisolated private static func boundedRegularFile(_ url: URL, limit: UInt64) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw StoreFailure("Missing regular file: \(url.lastPathComponent)")
        }
        guard UInt64(values.fileSize ?? 0) <= limit else {
            throw StoreFailure("\(url.lastPathComponent) exceeds the display limit")
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    nonisolated private static func decodeDate(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let date = parseDate(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid timestamp")
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
