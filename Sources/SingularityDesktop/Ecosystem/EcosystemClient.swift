import Foundation

struct EcosystemStatus: Decodable, Sendable {
    let paused: Bool
    let lasCatalogReady: Bool
    let owner: EcosystemOwner
    let runtime: EcosystemRuntime
    let updatedAt: String
    let lastProgressAt: String?
    let activeCount: Int
    let observationCount: Int
    let opportunityCount: Int
    let initiativeCount: Int
    let spentUsd: String
    let reservedUsd: String
    let budgetUsd: String
    let issues: [EcosystemIssue]
}
struct EcosystemRuntime: Decodable, Sendable {
    let version: String
    let sourceRevision: String?
}
struct EcosystemOwner: Decodable, Sendable {
    let agentId: String
    let role: String
    let environment: String
    let workloadId: String
}


struct EcosystemIssue: Decodable, Sendable {
    let operation: String
    let code: String
    let message: String
}

struct EcosystemOpportunity: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let description: String
    let productId: String?
    let kind: String
    let rationale: String
    let evidenceRefs: [String]
    let expectedOutcome: String
    let rejectionCondition: String
    let alternatives: [String]
    let estimatedCostUsd: String
    let uncertainty: String
    let status: String
}

struct EcosystemInitiative: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let productId: String?
    let state: String
    let budgetUsd: String
    let spentUsd: String
    let reservedUsd: String
    let blockedReason: String?
}

struct EcosystemItems<Item: Decodable & Sendable>: Decodable, Sendable {
    let items: [Item]
    let nextCursor: Int64?
}

struct EcosystemRecordKey: Hashable, Sendable {
    let kind: String
    let id: String
}

struct EcosystemRecordSummary: Decodable, Sendable {
    let kind: String
    let id: String
    let createdAt: String
    let updatedAt: String
    let totalBytes: UInt64
    let preview: String
    let state: String?
    var key: EcosystemRecordKey { .init(kind: kind, id: id) }
}

struct EcosystemRecordChunk: Decodable, Sendable {
    let kind: String
    let id: String
    let offset: UInt64
    let totalBytes: UInt64
    let contentSha256: String
    let text: String
    let nextOffset: UInt64?
}

private struct EcosystemRequest: Encodable {
    let schemaVersion = OwnerProtocol.ecosystemSchemaVersion
    let method: String
    let params: Params
    struct Params: Encodable {
        var id: String? = nil
        var kind: String? = nil
        var initiativeId: String? = nil
        var before: Int64? = nil
        var limit: Int? = nil
        var offset: UInt64? = nil
        var bytes: Int? = nil
        var revision: String? = nil
    }
}

private struct EcosystemEnvelope<Result: Decodable>: Decodable {
    let schemaVersion: Int
    let ok: Bool
    let result: Result?
    let error: EcosystemIssue?
}

enum EcosystemClient {
    static func status(_ directory: URL, method: String = "status") async throws -> EcosystemStatus {
        try await request(directory, method: method)
    }

    static func opportunities(_ directory: URL, before: Int64? = nil) async throws -> EcosystemItems<EcosystemOpportunity> {
        try await request(directory, method: "opportunities", params: .init(before: before, limit: 50))
    }

    static func initiatives(_ directory: URL, before: Int64? = nil) async throws -> EcosystemItems<EcosystemInitiative> {
        try await request(directory, method: "initiatives", params: .init(before: before, limit: 50))
    }

    static func records(_ directory: URL, kind: String?, initiativeId: String?, before: Int64? = nil) async throws -> EcosystemItems<EcosystemRecordSummary> {
        try await request(directory, method: "records", params: .init(kind: kind, initiativeId: initiativeId, before: before, limit: 50))
    }

    static func record(_ directory: URL, kind: String, id: String, offset: UInt64 = 0, revision: String? = nil) async throws -> EcosystemRecordChunk {
        let value: EcosystemRecordChunk = try await request(directory, method: "record",
            params: .init(id: id, kind: kind, offset: offset, bytes: 65_536, revision: revision))
        let (end, overflow) = offset.addingReportingOverflow(UInt64(value.text.utf8.count))
        guard value.kind == kind, value.id == id, value.offset == offset, !overflow,
              value.text.utf8.count <= 65_536, end <= value.totalBytes,
              value.nextOffset == (end < value.totalBytes ? end : nil),
              end > offset || end == value.totalBytes,
              value.contentSha256.utf8.count == 64,
              value.contentSha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              revision == nil || revision == value.contentSha256 else {
            throw OwnerConnectionFailure(message: "The owner returned a mismatched record fragment. No mixed contents were displayed.")
        }
        return value
    }

    static func explain(_ directory: URL, id: String) async throws -> String {
        let data = try await exchange(directory, method: "explain", params: .init(id: id))
        let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard envelope?["schema_version"] as? Int == OwnerProtocol.ecosystemSchemaVersion,
              envelope?["ok"] as? Bool == true, let result = envelope?["result"] else {
            let issue = (envelope?["error"] as? [String: Any])?["message"] as? String
            throw OwnerConnectionFailure(message: issue ?? "The owner returned an invalid explanation.")
        }
        let rendered = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: rendered, as: UTF8.self)
    }

    private static func request<Result: Decodable & Sendable>(_ directory: URL, method: String, params: EcosystemRequest.Params = .init()) async throws -> Result {
        let data = try await exchange(directory, method: method, params: params)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(EcosystemEnvelope<Result>.self, from: data)
        guard envelope.schemaVersion == OwnerProtocol.ecosystemSchemaVersion else {
            throw OwnerConnectionFailure(message: "The owner returned an unsupported ecosystem protocol.")
        }
        guard envelope.ok, let result = envelope.result else {
            throw OwnerConnectionFailure(message: envelope.error.map { "\($0.operation): \($0.code): \($0.message)" }
                ?? "The owner refused the ecosystem operation without a reason.")
        }
        return result
    }

    private static func exchange(_ directory: URL, method: String, params: EcosystemRequest.Params = .init()) async throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        var body = try encoder.encode(EcosystemRequest(method: method, params: params))
        body.append(OwnerProtocol.newline)
        guard body.count <= OwnerProtocol.maximumEcosystemRequestBytes else {
            throw OwnerConnectionFailure(message: "The ecosystem request exceeds \(OwnerProtocol.maximumEcosystemRequestBytes) bytes.")
        }
        let response = try await OwnerConnection.exchange(body,
            socketPath: directory.appendingPathComponent("ecosystem.sock").path,
            maximumResponseBytes: OwnerProtocol.maximumEcosystemResponseBytes)
        guard response.last == OwnerProtocol.newline else {
            throw OwnerConnectionFailure(message: "The owner returned an incomplete ecosystem response.")
        }
        return response
    }
}
