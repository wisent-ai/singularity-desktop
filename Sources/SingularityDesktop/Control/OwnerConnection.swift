import Foundation

struct OwnerConnectionFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum OwnerConnection {
    static func exchange(_ request: Data, socketPath: String, maximumResponseBytes: Int) async throws -> Data {
        let exchange = OwnerSocketExchange(request: request, path: socketPath, maximumResponseBytes: maximumResponseBytes)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { exchange.start($0) }
        } onCancel: {
            exchange.cancel()
        }
    }
}
