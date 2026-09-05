import Darwin
import Foundation

struct MindImportResult: Decodable, Sendable {
    let accepted: Bool
    let sourceKind: String
    let sourceId: String
    let imported: Int
    let attributed: Int
    let unchanged: Int
    let conflicting: Int
    let rejected: Int
    let issues: [MindImportIssue]

    var summary: String {
        if accepted {
            return "Imported \(imported), attributed \(attributed), unchanged \(unchanged). No identity, prompt, budget, finance policy, or tool setting was changed."
        }
        let detail = issues.first.map { " First issue: \($0.category) \($0.itemId) — \($0.reason)." } ?? ""
        return "Import refused: \(conflicting) conflicting and \(rejected) rejected item(s). No state was changed.\(detail)"
    }
}

struct MindImportIssue: Decodable, Sendable {
    let category: String
    let itemId: String
    let reason: String
}

private struct MindImportWireRequest: Encodable {
    let version = 1
    let operation = "mind_import"
    let documentBase64: String

    private enum CodingKeys: String, CodingKey {
        case version
        case operation
        case documentBase64 = "document_base64"
    }
}

private struct MindImportWireResponse: Decodable {
    let ok: Bool
    let result: MindImportResult?
    let error: String?
}

private struct MindImportFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum MindImportClient {
    private static let maximumDocumentBytes = 16 * 1024 * 1024
    private static let maximumResponseBytes = 1024 * 1024

    static func importDocument(_ documentURL: URL, stateDirectory: URL) async throws -> MindImportResult {
        try await Task.detached(priority: .userInitiated) {
            let accessing = documentURL.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    documentURL.stopAccessingSecurityScopedResource()
                }
            }
            let values = try documentURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw MindImportFailure(message: "The import must be a regular JSON file, not a folder or symbolic link.")
            }
            guard (values.fileSize ?? 0) <= maximumDocumentBytes else {
                throw MindImportFailure(message: "The import exceeds the 16 MiB limit.")
            }
            let document = try Data(contentsOf: documentURL, options: [.mappedIfSafe])
            guard document.count <= maximumDocumentBytes else {
                throw MindImportFailure(message: "The import exceeds the 16 MiB limit.")
            }
            let request = MindImportWireRequest(documentBase64: document.base64EncodedString())
            let encoded = try JSONEncoder().encode(request)
            let socketURL = stateDirectory.appendingPathComponent("state-import.sock")
            let response = try exchange(encoded, socketPath: socketURL.path)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let envelope = try decoder.decode(MindImportWireResponse.self, from: response)
            guard envelope.ok, let result = envelope.result else {
                throw MindImportFailure(
                    message: envelope.error ?? "The Singularity state owner refused the import without a reason."
                )
            }
            return result
        }.value
    }

    private static func exchange(_ request: Data, socketPath: String) throws -> Data {
        let pathCapacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        guard socketPath.utf8.count < pathCapacity else {
            throw MindImportFailure(message: "The selected state directory path is too long for the local import service.")
        }
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw MindImportFailure(message: "Could not create a local import connection: \(posixMessage()).")
        }
        defer { Darwin.close(descriptor) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { destination in
                _ = socketPath.withCString { source in strcpy(destination, source) }
            }
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, length)
            }
        }
        guard connected == 0 else {
            throw MindImportFailure(
                message: "The being's local state owner is not available. Start `singularity run` for this state directory, or use `singularity import` while it is stopped."
            )
        }

        try request.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < raw.count {
                let written = Darwin.write(descriptor, base.advanced(by: sent), raw.count - sent)
                if written < 0 {
                    throw MindImportFailure(message: "Could not send the import to Singularity: \(posixMessage()).")
                }
                sent += written
            }
        }
        guard Darwin.shutdown(descriptor, SHUT_WR) == 0 else {
            throw MindImportFailure(message: "Could not finish the local import request: \(posixMessage()).")
        }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 32 * 1024)
        while true {
            let readCount = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if readCount < 0 {
                throw MindImportFailure(message: "Could not read the Singularity import result: \(posixMessage()).")
            }
            if readCount == 0 { break }
            response.append(contentsOf: buffer.prefix(readCount))
            if response.count > maximumResponseBytes {
                throw MindImportFailure(message: "The Singularity import result exceeds the 1 MiB response limit.")
            }
        }
        return response
    }

    private static func posixMessage() -> String {
        String(cString: strerror(errno))
    }
}
