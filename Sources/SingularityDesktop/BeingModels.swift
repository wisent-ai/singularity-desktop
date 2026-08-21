import Foundation

struct BeingState: Decodable, Sendable {
    let schemaVersion: String
    let identity: BeingIdentity
    let mind: BeingMind
    let status: String
    let cycle: UInt64
    let budget: BeingBudget
    let recentActions: [BeingAction]
    let startedAt: Date
    let updatedAt: Date
}

struct BeingIdentity: Decodable, Sendable {
    let agentID: String
    let name: String
    let ticker: String
    let agentType: String
    let specialty: String
    let role: String
    let environment: String
    let host: String
    let workloadID: String
}

struct BeingMind: Decodable, Sendable {
    let systemPrompt: String
    let rules: [String]
    let learnings: [String]
    let memories: [BeingMemory]
    let children: [BeingChild]
    let currentModel: String
}

struct BeingMemory: Decodable, Identifiable, Sendable {
    let id: UUID
    let kind: String
    let text: String
    let createdAt: Date
}

struct BeingChild: Decodable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let ticker: String
    let stateDir: String
    let createdAt: Date
    let status: String
}

struct BeingAction: Decodable, Identifiable, Sendable {
    let cycle: UInt64
    let tool: String
    let status: String
    let at: Date
    var id: String { "\(cycle)-\(tool)-\(at.timeIntervalSince1970)" }
}

struct BeingBudget: Decodable, Sendable {
    let starting: FlexibleDecimal
    let remaining: FlexibleDecimal
    let apiSpent: FlexibleDecimal
    let instanceSpent: FlexibleDecimal
    let totalTokens: UInt64
    let earned: FlexibleDecimal

    var netProfit: Decimal { earned.value - apiSpent.value - instanceSpent.value }
}

struct FlexibleDecimal: Decodable, Sendable {
    let value: Decimal

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self), let value = Decimal(string: string) {
            self.value = value
            return
        }
        if let number = try? container.decode(Double.self) {
            value = Decimal(number)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected decimal string or number")
    }
}

struct ActivityLine: Identifiable, Sendable {
    let id: Int
    let type: String
    let timestamp: Date?
    let summary: String
}
