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
        let encoded = try await Task.detached(priority: .userInitiated) {
            try encodeDocument(documentURL)
        }.value
        try Task.checkCancellation()
        let socketURL = stateDirectory.appendingPathComponent("state-import.sock")
        let response = try await OwnerConnection.exchange(
            encoded, socketPath: socketURL.path, maximumResponseBytes: maximumResponseBytes
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(MindImportWireResponse.self, from: response)
        guard envelope.ok, let result = envelope.result else {
            throw MindImportFailure(
                message: envelope.error ?? "The Singularity state owner refused the import without a reason."
            )
        }
        return result
    }

    private static func encodeDocument(_ documentURL: URL) throws -> Data {
        let accessing = documentURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { documentURL.stopAccessingSecurityScopedResource() }
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
        return try JSONEncoder().encode(request)
    }

}
